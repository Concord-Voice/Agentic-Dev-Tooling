"""Regression tests for tier/readiness separation and fail-closed tier admission."""
from contextlib import redirect_stdout
from copy import deepcopy
import io
import json
from pathlib import Path
import runpy
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
CLASSIFIER = ROOT / "plugins/release-ops/skills/weekly-deps/classify.py"
classify = runpy.run_path(str(CLASSIFIER))["classify"]


class RiskPolicy(unittest.TestCase):
    def setUp(self):
        self.config = {"weekly_deps": {
            "risk_policy": "evidence-v1",
            "tiers": {
                "A": {"lint": {"packages": ["lint"], "dependency_type": "development",
                               "directories": ["client"], "max_bump": "minor"}},
                "B": {"lint major": {"packages": ["lint"], "dependency_type": "development",
                                     "directories": ["client"], "max_bump": "major"}},
            },
            "bundled_engines": ["electron"],
        }}
        self.pr = {"ecosystem": "npm", "directories": ["client"],
                   "footprint_verified": True, "surprise_diff": False,
                   "bundled_engine": False, "confirmed_risk": False,
                   "members": [{"package": "lint", "old": "1.1.0", "new": "1.2.0",
                                "dependency_type": "development", "surface": "routine",
                                "security_sensitive": False, "release": "clear"}]}

    def classify(self):
        return classify(self.config, self.pr)

    def test_readiness_is_outside_classification(self):
        baseline = self.classify()
        self.assertEqual(baseline["tier"], "A")
        self.assertTrue(baseline["eligible_policy"])
        self.pr.update(ci="failure", approved=False, behind_by=10, mergeable="CONFLICTING")
        self.assertEqual(self.classify(), baseline)

    def test_routine_major_and_actual_breakage(self):
        self.pr["members"][0]["new"] = "2.0.0"
        self.assertEqual(self.classify()["tier"], "B")
        self.assertTrue(self.classify()["eligible_policy"])
        self.pr["members"][0]["release"] = "breaking"
        self.assertEqual(self.classify()["tier"], "C")

    def test_critical_patch_minor_major_and_unknown(self):
        member = self.pr["members"][0]
        member["surface"] = "critical"
        for version, tier in (("1.1.1", "A"), ("1.2.0", "B"), ("2.0.0", "C")):
            member["new"] = version
            self.assertEqual(self.classify()["tier"], tier)
        member.update(new="1.1.1", release="unknown")
        self.assertEqual(self.classify()["tier"], "C")

    def test_sensitive_requires_review_even_with_clean_patch(self):
        self.pr["members"][0].update(security_sensitive=True, new="1.1.1")
        result = self.classify()
        self.assertEqual(result["tier"], "A")
        self.assertTrue(result["security_review_required"])

    def test_emergency_requires_live_evidence_and_respects_c_overrides(self):
        self.pr["members"][0].update(package="critical-service", surface="critical", new="1.1.1")
        self.pr["advisory"] = {"severity": "high", "applies_to_exact_versions": True,
                               "exposed_in_live_production": False,
                               "advisory_id": "GHSA-example",
                               "advisory_source": "official advisory record",
                               "live_exposure_receipt": "verified deployment receipt"}
        self.assertEqual(self.classify()["tier"], "UNKNOWN")
        self.pr["advisory"]["exposed_in_live_production"] = True
        self.assertEqual(self.classify()["tier"], "A")
        self.assertTrue(self.classify()["eligible_policy"])
        self.assertTrue(self.classify()["security_review_required"])
        self.pr["advisory"]["severity"] = "medium"
        self.assertEqual(self.classify()["tier"], "B")
        self.pr["bundled_engine"] = True
        self.assertEqual(self.classify()["tier"], "C")

    def test_engine_docker_and_surprise_override_known_patch(self):
        original = deepcopy(self.pr)
        for override in ({"bundled_engine": True}, {"ecosystem": "docker"}, {"surprise_diff": True}):
            self.pr = {**original, **override}
            self.assertEqual(self.classify()["tier"], "C")
        self.pr = original
        self.pr["members"][0]["package"] = "electron"
        self.assertEqual(self.classify()["tier"], "C")

    def test_scope_applies_to_every_member_without_becoming_a_risk_tier(self):
        self.pr["members"] += [{**self.pr["members"][0], "package": "unknown-to-policy"}]
        result = self.classify()
        self.assertEqual(result["tier"], "A")
        self.assertFalse(result["eligible_policy"])
        self.pr["members"][1]["release"] = "unknown"
        self.assertEqual(self.classify()["tier"], "UNKNOWN")

    def test_cli_preserves_pr_identity_and_policy_decision(self):
        identity = "example/product#12"
        self.pr["members"][0].update(old="v1.0.0", new="v1.1.0")
        evidence = io.StringIO(json.dumps({"config": self.config, "records": {identity: self.pr}}))
        output = io.StringIO()
        with patch("sys.argv", [str(CLASSIFIER)]), patch("sys.stdin", evidence), redirect_stdout(output):
            runpy.run_path(str(CLASSIFIER), run_name="__main__")
        self.assertEqual(json.loads(output.getvalue()), {identity: self.classify()})

    def test_incomplete_or_invalid_input_cannot_authorize_automatic_handling(self):
        rule = self.config["weekly_deps"]["tiers"]["A"]["lint"]
        rule["packages"] = "lint"
        self.assertFalse(self.classify()["eligible_policy"])
        member = self.pr["members"][0]
        for old, new in (("1.1.0", "1.1.0-beta.3"), ("1.1.0-rc.2", "1.1.0-rc.1"),
                         ("1.1.0", None)):
            member.update(old=old, new=new)
            self.assertEqual(self.classify()["tier"], "UNKNOWN")
        member.update(old="1.1.0-rc.2", new="1.1.0-rc.10")
        self.assertEqual(self.classify()["tier"], "B")

    def test_emergency_requires_named_advisory_and_live_receipts(self):
        self.pr["members"][0]["new"] = "1.1.1"
        self.pr["advisory"] = {"severity": "critical", "applies_to_exact_versions": True,
                               "exposed_in_live_production": True}
        self.assertEqual(self.classify()["tier"], "UNKNOWN")

    def test_consumer_security_overlay_overrides_false_input(self):
        self.config["weekly_deps"]["security_sensitive_extra"] = ["lint"]
        self.pr["members"][0]["new"] = "1.1.1"
        self.assertTrue(self.classify()["security_review_required"])
        self.pr["members"][0]["release"] = "unknown"
        self.assertEqual(self.classify()["tier"], "C")

    def test_explicit_c_rule_does_not_require_parseable_version(self):
        self.config["weekly_deps"]["tiers"]["C"] = {"packaging": {"packages": ["lint"]}}
        self.pr["members"][0]["new"] = "unversioned"
        self.assertEqual(self.classify()["tier"], "C")

    def test_explicit_c_rules_accept_directory_only_or_ecosystem_only_scope(self):
        tiers = self.config["weekly_deps"]["tiers"]
        for scope in ({"directories": ["client"]}, {"ecosystems": ["npm"]}):
            with self.subTest(scope=scope):
                tiers["C"] = {"protected scope": scope}
                result = self.classify()
                self.assertEqual(result["tier"], "C")
                self.assertEqual(result["matching_rules"], ["protected scope"])
                self.assertFalse(result["eligible_policy"])

    def test_invalid_dependency_type_cannot_admit_untyped_package(self):
        rule = self.config["weekly_deps"]["tiers"]["A"]["lint"]
        del self.pr["members"][0]["dependency_type"]
        for dependency_type in (None, "unexpected"):
            with self.subTest(dependency_type=dependency_type):
                rule["dependency_type"] = dependency_type
                result = self.classify()
                self.assertEqual(result["tier"], "A")
                self.assertFalse(result["eligible_policy"])


if __name__ == "__main__":
    unittest.main()
