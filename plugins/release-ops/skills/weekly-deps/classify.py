"""Classify verified dependency evidence without consulting merge readiness."""
import argparse
from fnmatch import fnmatchcase
import json
from pathlib import Path
import re


BUMP_RANK = {"patch": 0, "minor": 1, "major": 2}
RULE_FIELDS = {"groups", "ungrouped", "packages", "ecosystems", "directories",
               "dependency_type", "max_bump"}


def matches(values, patterns):
    return bool(values) and all(any(fnmatchcase(value, pattern) for pattern in patterns)
                                for value in values)


def bump_shape(before, after):
    def version(text):
        match = re.fullmatch(r"v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(-[0-9A-Za-z.-]+)?"
                             r"(?:\+[0-9A-Za-z.-]+)?", text or "")
        return (*map(int, match.groups()[:3]), match[4]) if match else None

    old, new = version(before), version(after)
    if old is None or new is None:
        return None
    if old[:3] > new[:3] or old == new:
        return None
    if old[3] or new[3] or old[0] != new[0]:
        return "major"
    if old[1] != new[1]:
        return "major" if old[0] == 0 else "minor"
    if old[0] == 0:
        return "major" if old[1] == 0 else "minor"
    return "patch"


def rule_matches(tier, rule, pr, bumps):
    if not rule or rule.keys() - RULE_FIELDS:
        return False
    if not (rule.get("groups") or rule.get("ungrouped") is True or rule.get("packages")):
        return False
    members = pr["members"]
    group = pr.get("group")
    return (
        ("groups" not in rule or group in rule["groups"])
        and ("ungrouped" not in rule or
             rule["ungrouped"] is True and not group and len(members) == 1)
        and ("packages" not in rule or matches([member["package"] for member in members], rule["packages"]))
        and ("ecosystems" not in rule or pr.get("ecosystem") in rule["ecosystems"])
        and ("directories" not in rule or matches(pr.get("directories", []), rule["directories"]))
        and ("dependency_type" not in rule or
             all(member.get("dependency_type") == rule["dependency_type"] for member in members))
        and (tier == "C" or (
            rule.get("max_bump", "minor") in BUMP_RANK
            and all(bump is not None and BUMP_RANK[bump] <= BUMP_RANK[rule.get("max_bump", "minor")]
                    for bump in bumps)
        ))
    )


def classify(config, pr):
    """Use maintainer-verified facts. CI, approval, base and conflict are separate."""
    policy = config.get("weekly_deps", {})
    members = pr["members"]
    packages = [member["package"] for member in members]
    bumps = [bump_shape(member.get("old"), member.get("new")) for member in members]
    security_review = any(member.get("security_sensitive") is True for member in members)
    rule_matches_by_tier = {
        tier: [name for name, rule in policy.get("tiers", {}).get(tier, {}).items()
               if rule_matches(tier, rule, pr, bumps)]
        for tier in ("A", "B", "C")
    }

    def result(tier, reason, *, emergency=False):
        return {"tier": tier, "reason": reason,
                "matching_rules": rule_matches_by_tier.get(tier, []),
                "eligible_policy": tier in ("A", "B") and (
                    emergency or bool(rule_matches_by_tier[tier])),
                "security_review_required": security_review or emergency}

    if policy.get("risk_policy") != "evidence-v1":
        return result("UNKNOWN", "Evidence-based policy is not enabled")
    engine_patterns = policy.get("bundled_engines", [])
    group = pr.get("group")
    if (pr.get("ecosystem") == "docker" or pr.get("bundled_engine") is True
            or any(matches([package], engine_patterns) for package in packages)
            or (group and matches([group], engine_patterns))):
        return result("C", "Bundled engine or image changed")
    if pr.get("surprise_diff") is True:
        return result("C", "Unexpected dependency diff footprint")
    if pr.get("confirmed_risk") is True or any(m.get("release") == "breaking" for m in members):
        return result("C", "Confirmed breaking change or dependency risk")
    if rule_matches_by_tier["C"]:
        return result("C", "Matched an explicit Tier C rule")

    critical = [
        member.get("surface") == "critical"
        or member.get("security_sensitive") is True
        or matches([member["package"]], policy.get("critical_packages", []))
        for member in members
    ]
    if any(core and (bump == "major" or member.get("release") != "clear")
           for member, core, bump in zip(members, critical, bumps)):
        return result("C", "Critical-surface major or unresolved release risk")
    if (not members or pr.get("footprint_verified") is not True
            or pr.get("bundled_engine") is not False
            or pr.get("surprise_diff") is not False
            or pr.get("confirmed_risk") is not False
            or any(bump is None or member.get("release") != "clear"
                   or member.get("surface") not in ("routine", "critical")
                   or type(member.get("security_sensitive")) is not bool
                   for member, bump in zip(members, bumps))):
        return result("UNKNOWN", "Tier evidence is incomplete")

    advisory = pr.get("advisory") or {}
    severity = advisory.get("severity")
    if (
        all(bump == "patch" for bump in bumps)
        and advisory.get("applies_to_exact_versions") is True
        and advisory.get("exposed_in_live_production") is True
        and severity in ("medium", "high", "critical")
    ):
        tier = "A" if severity in ("high", "critical") else "B"
        return result(tier, f"Verified live {severity} security patch", emergency=True)
    if advisory:
        return result("UNKNOWN", "Security patch needs verified version and live exposure evidence")

    if any(bump == ("minor" if core else "major")
           for bump, core in zip(bumps, critical)):
        return result("B", "Critical minor or routine major with clear release evidence")
    return result("A", "Routine patch/minor or critical patch with clear release evidence")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args()
    config = json.loads(args.config.read_text())
    records = json.loads(args.evidence.read_text())
    print(json.dumps({key: classify(config, pr) for key, pr in records.items()}, indent=2))


if __name__ == "__main__":
    main()
