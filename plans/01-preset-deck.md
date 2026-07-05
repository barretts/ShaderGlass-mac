# Feature 1 - Preset Deck

## Objective

Preserve the implemented preset deck as the authoritative preset-selection baseline, keep preset identity stable, and define only the next bounded polish cuts that do not disturb selection, persistence, or render-thread ownership.

Current status:
- implemented baseline
- stable preset identifiers are already in use
- preset selection is already part of the working app surface

This plan is no longer an implementation sequence for first ship. It is a maintenance and delegation artifact for regression coverage, bounded polish, and contract preservation.

## Procedure

### Stage 0 - Ownership Boundary

This feature owns:
- preset catalog identity
- deck selection behavior
- deck keyboard and focus behavior
- thumbnail presentation and placeholder fallback
- selected-preset persistence keyed by stable preset id
- app file touchpoints:
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
  - `app/EngineBridge.h` only if preset metadata fields exposed to the app change
  - `app/EngineBridge.mm` only if preset metadata plumbing changes
  - `app/build.sh` only if preset coverage is added to selftest

This feature does not own:
- shader authoring workflow beyond curated preset inventory already in repo
- parameter controls and override persistence semantics
- compare mode state
- capture selection, export, packaging, or shared-engine redesign

### Stage 1 - Current Baseline Contract

The implemented baseline must continue to guarantee:
- each curated preset has one stable id
- deck selection resolves by stable id rather than enum ordinal assumptions
- relaunch restores the selected preset only when the descriptor still exists
- missing thumbnail output degrades to placeholder behavior instead of a broken deck

If any proposed follow-up threatens one of these guarantees, stop and replan before changing code.

### Stage 2 - Root Dependencies

This feature sits first in the Director A sequence.

Downstream consumers:
- Feature 2 depends on stable preset identifiers for per-preset override replay
- Feature 3 depends on stable preset identifiers for exact restore after bypass or split compare flows

Upstream assumptions:
- curated preset descriptors remain sourced from the current app catalog in `app/LivePipeline.mm`
- preset application remains routed through the current pipeline handoff in `app/SGAppDelegate.mm`

If either assumption changes, stop and escalate to root before editing local plan or code.

### Stage 3 - Subordinate Agent Roster

Director-approved agents for this feature:
- `preset-regression-agent`
  - validates preset id stability, deck selection invariants, and relaunch restoration behavior
- `deck-polish-agent`
  - handles bounded UI follow-ups such as layout tuning, selection affordance clarity, or keyboard/focus polish
- `thumbnail-integrity-agent`
  - validates thumbnail generation, cache invalidation assumptions, and placeholder fallback

Agent ownership split:
- identity and selection regressions belong to `preset-regression-agent`
- visual and ergonomic follow-ups belong to `deck-polish-agent`
- image and cache integrity issues belong to `thumbnail-integrity-agent`

### Stage 3.1 - Intake Packet

Every future pass on Feature 1 should start with this intake packet:
1. Request
   - what deck behavior is being preserved or improved
2. Baseline to preserve
   - current preset selection, restore, and thumbnail behavior that must survive the pass
3. Writable surface
   - exact files to edit, or `plan-only`
4. Dependency gates in play
   - stable id contract, persistence isolation, render-path safety, resource tolerance
5. Required return artifacts
   - selftest/build log path, deck screenshot, preset-id manifest note
6. Stop trigger
   - the first condition that forces escalation to Director A or root

### Stage 3.2 - Agent Release Packets

`preset-regression-agent`
- assignment:
  - prove the existing deck still selects and restores presets by stable id
- writable files:
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
  - `app/build.sh` only when coverage changes
- required checks:
  - catalog integrity
  - selection behavior
  - persistence
- return artifacts:
  - `.logs/...` build or selftest log
  - deck screenshot
  - note confirming whether stable ids changed
- stop rule:
  - halt if any fix requires changing id semantics or persistence keys

`deck-polish-agent`
- assignment:
  - improve layout, focus, and selection clarity without touching preset identity
- writable files:
  - `app/SGAppDelegate.mm`
- required checks:
  - selection behavior
  - keyboard/focus behavior
- return artifacts:
  - before/after screenshots if UI changed
  - note confirming no contract change
- stop rule:
  - halt if polish pressure requires new app-chrome ownership or preset model changes

`thumbnail-integrity-agent`
- assignment:
  - validate thumbnail generation, fallback, and cache tolerance
- writable files:
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
- required checks:
  - thumbnail fallback
  - catalog integrity
- return artifacts:
  - screenshot showing placeholder or valid thumbnail state
  - note confirming cache assumptions touched or preserved
- stop rule:
  - halt if thumbnail handling would block launch, first frame, or require external asset management redesign

### Stage 4 - Implementation Stages

Stage 4.1 - Freeze baseline contract
- re-read current preset descriptor construction and deck selection flow
- confirm stable ids still originate from the descriptor layer, not button position or enum order

Stage 4.2 - Audit touchpoints
- verify `app/LivePipeline.mm` still owns the curated catalog
- verify `app/SGAppDelegate.mm` still owns deck layout, active selection state, and persistence handshake

Stage 4.3 - Bounded preservation work
- tighten regression language around restore behavior, placeholder fallback, and deck-state updates
- allow only polish that keeps selection contract unchanged

Stage 4.4 - Extension triage
- keep safe follow-ups limited to layout, focus, browseability, and thumbnail integrity
- route any request for external preset manifests, user-authored presets, or id model changes back to root

Stage 4.5 - Verification capture
- require artifacts before claiming deck work is healthy

Stage exits:
- Exit 4.1 only when the stable-id source is named in the packet
- Exit 4.2 only when ownership of catalog and deck UI is reconfirmed
- Exit 4.3 only when the preserved invariants are listed explicitly
- Exit 4.4 only when deferred cuts are split into `allowed next cuts` or `root review`
- Exit 4.5 only when the artifact list contains literal paths or an explicit `pending capture` note before execution starts

### Stage 5 - Dependency Gates

Gate 1 - Stable id contract:
- no follow-up may reintroduce enum-ordinal dependence as a source of truth

Gate 2 - Persistence isolation:
- selected preset persistence must remain separate from favorites, recents, compare state, and parameter overrides

Gate 3 - Render-path safety:
- preset switching must remain routed through the existing safe pipeline path

Gate 4 - Resource tolerance:
- missing or stale thumbnail artifacts must fail into placeholders, not blank or broken selection cells

### Stage 6 - Verification Artifacts

Required deliverables from any active work on this feature:
1. baseline contract summary
2. explicit list of touched preset-selection invariants
3. regression checklist result
4. verification artifacts
5. bounded backlog note for any deferred polish cut

Expected verification artifacts:
- literal build or selftest log path, usually from `app/build.sh selftest`
- one screenshot showing the populated deck in a valid state
- one short manifest note listing the current stable preset ids or confirming no id changes
- one file-touch note stating whether `app/LivePipeline.mm` and `app/SGAppDelegate.mm` were affected

Artifact acceptance:
- a screenshot without a corresponding contract note is insufficient
- a contract note without a literal artifact path is insufficient when code changed
- `plan-only` edits must still return the baseline statement that was revalidated

### Stage 7 - Verification Matrix

Minimum regression checks:
1. Catalog integrity
   - iterate the available presets and confirm every selectable tile maps to a valid preset id
2. Selection behavior
   - switch across multiple presets in static mode and live mode without losing frame updates
3. Persistence
   - relaunch and verify the last selected preset restores only if still present in the catalog
4. Thumbnail fallback
   - confirm placeholder behavior remains explicit when a thumbnail is missing or invalid

Use existing project validation commands appropriate to the touched code path and record literal log locations in `.logs/` when commands are run.

### Stage 8 - Stop Gates

Stop and escalate when:
- a polish request would alter preset identifier generation or persistence keys
- the deck starts using compare or parameter internals instead of descriptor-level state
- preset switching requires direct raw-engine access instead of the current app pipeline call path
- another director needs simultaneous edits in the same preset touchpoints and root sequencing has not resolved it

Stop-gate routing:
- return `blocked` when the issue is local but unresolved inside Feature 1 ownership
- return `needs-root` when the request changes preset id semantics, introduces new preset sources, or collides with another director's writable surface

### Stage 9 - Next Cuts

Allowed next cuts for this feature:
- keyboard/focus polish that does not change the selection contract
- deck layout density or browseability improvements within the current app shell
- thumbnail cache correctness work
- favorites or recents refinement only if kept strictly separate from descriptor source data

Cuts that require root review before work starts:
- external preset manifests
- user-authored preset editing
- broad app-chrome redesign driven by the deck
- any change that alters preset id semantics or persistence keys

## Stopping Conditions

Stop and escalate when:
- a polish request would alter the stable preset id contract
- deck behavior starts depending on parameter or compare internals instead of public APIs
- thumbnail behavior requires blocking launch or first-frame delivery
- concurrent upstream edits change preset-selection APIs and the safe owner is outside Director A

## Procedure Risks

- The largest risk is quiet identity drift: a small UX cleanup can accidentally reintroduce unstable selection assumptions.
- Thumbnail behavior can regress silently if cache invalidation and placeholder fallback are not checked together.
- Because the feature is already implemented, teams may under-test baseline behavior after seemingly minor polish work.

## Evaluation

This feature is in good shape when:
- the deck remains the authoritative preset-selection surface
- preset identity and restoration invariants are explicit and preserved
- subordinate agents know exactly which regressions they own
- future polish work is clearly separated from contract-changing work
