export const meta = {
  name: 'design-panel',
  description: 'Phase-2 Architecture & Design panel: architect philosophy → parallel specialists → frontend reconciliation → architect synthesis',
  whenToUse: 'Invoked by /dev-lifecycle Phase 2 for any nontrivial design. Realizes the Architecture & Design team hierarchy, which subagents cannot express directly (a subagent cannot dispatch a subagent).',
  phases: [
    { title: 'Philosophy', detail: 'architect drafts the design philosophy the panel builds against', model: 'fable' },
    { title: 'Panel', detail: 'system-engineer / ui-designer / ux-designer work the brief in parallel' },
    { title: 'Reconcile', detail: 'frontend-designer merges the UI and UX positions into one handoff spec', model: 'opus' },
    { title: 'Synthesis', detail: 'architect reconciles every panel output into the final spec', model: 'fable' },
  ],
}

// args: {
//   issue:       "1234",                 // issue number (string or number)
//   brief:       "<issue brief text>",   // required — the /issue-brief output
//   backend:     true,                   // dispatch system-engineer
//   frontend:    true,                   // dispatch ui-designer + ux-designer (as a PAIR)
//   philosophy:  "<text>",               // optional — skip Phase 1 if the architect already ran Mode 2
//   libraryIds:  "/vercel/next.js, …",   // optional — Context7 ids the design must be current against
// }
// ponytail: some harnesses hand `args` through as a JSON string rather than an
// object, which made every field read undefined and surfaced as the misleading
// "args.brief is required" below. Accept either shape; drop the string branch
// once the harness reliably passes `args` through as an object.
let a = args || {}
if (typeof a === 'string') {
  try {
    a = JSON.parse(a)
  } catch (err) {
    // The parser's own message ("Unexpected token } at position 47") localizes the
    // fault far better than the payload prefix does; keep both. JSON.stringify
    // delimits the excerpt so whitespace-only input doesn't render as nothing.
    throw new Error(
      `design-panel: args was a string but is not valid JSON (${err.message}) — got: ${JSON.stringify(a.slice(0, 120))}`,
    )
  }
}
// Array.isArray is load-bearing: typeof [] === 'object', so without it a stray
// array falls through to the "args.brief is required" throw below — reproducing
// the exact misleading-error class this normalization exists to remove.
if (a === null || Array.isArray(a) || typeof a !== 'object') {
  const got = a === null ? 'null' : Array.isArray(a) ? 'array' : typeof a
  throw new Error(`design-panel: args must be an object (or its JSON string) — got ${got}`)
}

const ISSUE = String(a.issue ?? 'unknown')
if (a.issue === undefined || a.issue === null || a.issue === '') {
  log('WARN: design-panel called without args.issue — spec will be headed "## Issue #unknown"')
}
const BRIEF = a.brief ?? ''
const BACKEND = a.backend !== false
const FRONTEND = a.frontend === true
const LIBS = a.libraryIds ? `\n\nContext7 library IDs in scope (fetch current docs before designing against them): ${a.libraryIds}` : ''

if (!BRIEF) throw new Error('design-panel: args.brief is required (pass the /issue-brief output)')
if (!BACKEND && !FRONTEND) throw new Error('design-panel: at least one of args.backend / args.frontend must be true')

const context = `## Issue #${ISSUE}\n\n${BRIEF}${LIBS}`

// ── Phase 1: Philosophy ───────────────────────────────────────────────────────
phase('Philosophy')
const philosophy =
  a.philosophy ??
  (await agent(
    `Run Mode 2 (Phase 2: Design Philosophy). Produce the design philosophy the specialist panel will build against.\n\n${context}`,
    { agentType: 'architect', label: 'architect:philosophy', phase: 'Philosophy' },
  ))

if (!philosophy) throw new Error('design-panel: architect produced no design philosophy — aborting before the panel')

const panelBrief = `${context}\n\n## Architect's Design Philosophy\n\n${philosophy}`

// ── Phase 2: Panel (parallel) ─────────────────────────────────────────────────
// ui-designer and ux-designer are dispatched as a PAIR or not at all — the
// reconciliation step exists to resolve their tension.
phase('Panel')
// Tagged thunks: results are read BY KEY, never by positional index. A positional
// walk (`results[i++]`) silently mis-assigns every downstream value if the array is
// ever not positionally aligned with the thunks — e.g. ui-designer output landing in
// `technical` with no detectable error.
const thunks = []
if (BACKEND) {
  thunks.push(() =>
    agent(
      `Produce the technical approach realizing the architect's design philosophy below. Backend / media-plane / infrastructure scope only.\n\n${panelBrief}`,
      { agentType: 'system-engineer', label: 'system-engineer', phase: 'Panel' },
    ).then((r) => ({ key: 'technical', value: r })),
  )
}
if (FRONTEND) {
  thunks.push(() =>
    agent(
      `Produce the UI spec (visual + interactive layer) for the change below. Flag genuine tensions with the UX position as [PANEL: …].\n\n${panelBrief}`,
      { agentType: 'ui-designer', label: 'ui-designer', phase: 'Panel' },
    ).then((r) => ({ key: 'uiSpec', value: r })),
  )
  thunks.push(() =>
    agent(
      `Produce the UX spec (journey, IA, flows, copy) for the change below. Flag genuine tensions with the UI position as [PANEL: …].\n\n${panelBrief}`,
      { agentType: 'ux-designer', label: 'ux-designer', phase: 'Panel' },
    ).then((r) => ({ key: 'uxSpec', value: r })),
  )
}

const results = await parallel(thunks)
// parallel() resolves a failed thunk to null, so a tag may be missing entirely —
// read by key and default to null rather than assuming alignment or length.
const byKey = Object.fromEntries(
  results.filter((r) => r && typeof r === 'object' && r.key).map((r) => [r.key, r.value]),
)
const technical = byKey.technical ?? null
const uiSpec = byKey.uiSpec ?? null
const uxSpec = byKey.uxSpec ?? null

if (BACKEND && !technical) log('WARN: system-engineer returned nothing — synthesis will note the gap')
if (FRONTEND && (!uiSpec || !uxSpec)) log('WARN: a frontend panelist returned nothing — reconciliation will be one-sided')

// ── Phase 3: Reconcile ────────────────────────────────────────────────────────
let handoff = null
if (FRONTEND && (uiSpec || uxSpec)) {
  phase('Reconcile')
  handoff = await agent(
    `Reconcile the two frontend panel positions below into ONE handoff spec. Inventory every [PANEL: …] flag plus any unflagged contradiction, resolve each explicitly against the architect's philosophy, then run the accessibility pass over the MERGED result.\n\n` +
      `${panelBrief}\n\n## UI Designer Spec\n\n${uiSpec ?? '(missing — note this gap rather than inventing content)'}\n\n## UX Designer Spec\n\n${uxSpec ?? '(missing — note this gap rather than inventing content)'}`,
    { agentType: 'frontend-designer', label: 'frontend-designer', phase: 'Reconcile' },
  )
}

// ── Phase 4: Synthesis ────────────────────────────────────────────────────────
phase('Synthesis')
const final = await agent(
  `Run Mode 3 (Phase 2: Reconciliation). Produce the FINAL spec from the panel outputs below. Resolve contradictions explicitly — name the conflict, the winner, and why. Where a specialist's evidence invalidates your Mode-2 recommendation, adopt the better answer and say so. Include the mandatory acceptance-criteria table and a "Docs to update" criterion.\n\n` +
    `${panelBrief}\n\n## Technical Approach (system-engineer)\n\n${technical ?? '(not dispatched — backend out of scope)'}\n\n## Frontend Handoff Spec (frontend-designer)\n\n${
      handoff ??
      (FRONTEND
        ? '(frontend panel dispatched but produced no usable output — treat as a GAP, not as out-of-scope)'
        : '(not dispatched — frontend out of scope)')
    }`,
  { agentType: 'architect', label: 'architect:synthesis', phase: 'Synthesis' },
)

log(`design-panel complete — issue #${ISSUE}: philosophy${BACKEND ? ' + technical' : ''}${FRONTEND ? ' + ui/ux + handoff' : ''} → final spec`)

return {
  issue: ISSUE,
  philosophy,
  technical,
  uiSpec,
  uxSpec,
  handoff,
  finalSpec: final,
}
