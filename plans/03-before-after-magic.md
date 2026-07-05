# Feature 3 - Before/After Magic

## Objective

Preserve the implemented compare system, keep bypass and split compare strongly verified as adjacent rendering code evolves, and define only the next bounded compare cuts that do not contaminate preset identity, parameter persistence, or frame-lifetime safety.

Current status:
- hold-to-bypass implemented
- split compare implemented
- split compare strongly verified

This feature is no longer an implementation sequence for compare cut 2. It is a preservation and delegation plan focused on regression coverage, lifetime safety, and disciplined next-step triage.

## Procedure

### Stage 0 - Ownership Boundary

This feature owns:
- transient compare state
- compare interaction affordances
- bypass and split compare rendering behavior
- compare-specific verification for restore exactness and split-position correctness
- app file touchpoints:
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/EngineBridge.h`
  - `app/EngineBridge.mm`
  - `app/SGAppDelegate.mm`
  - `app/main.mm`
  - `app/build.sh`
  - compare-specific shader assets under `spike/*.metal` only when the compare baseline itself changes

This feature does not own:
- selected preset persistence semantics
- parameter persistence schema
- capture policy or ScreenCaptureKit ownership rules
- broad shared-engine render architecture beyond the approved app bridge seam already in place

### Stage 1 - Current Baseline Contract

The implemented baseline must continue to guarantee:
- compare is transient and does not rewrite the selected preset or preset persistence state
- bypass restores the prior preset and parameter state exactly
- split compare respects the current processed-target and frame-lifetime rules
- compare UI remains distinguishable from normal preset-selection behavior
- 0 percent, 50 percent, and 100 percent split positions remain deterministic

If any proposed follow-up threatens one of these guarantees, stop and replan.

### Stage 2 - Root Dependencies

This feature runs after Feature 1 and Feature 2 inside Director A.

Upstream dependencies:
- preset selection and restore identity from Feature 1 remain stable
- parameter reset and replay behavior from Feature 2 remain exact

Cross-director dependency:
- render-target lifetime, backend copy semantics, and output texture ownership remain Director C territory when they move beyond the currently approved app bridge

### Stage 3 - Subordinate Agent Roster

Director-approved agents for this feature:
- `compare-regression-agent`
  - validates bypass equivalence, split-position correctness, and restore exactness across static and live paths
- `compare-polish-agent`
  - handles bounded compare affordance improvements without changing persistence semantics
- `frame-lifetime-agent`
  - validates that compare still respects texture ownership and consumption rules as adjacent code changes

Agent ownership split:
- behavioral regressions belong to `compare-regression-agent`
- UX follow-ups belong to `compare-polish-agent`
- texture-lifetime and ownership proof belong to `frame-lifetime-agent`

### Stage 3.1 - Intake Packet

Every future pass on Feature 3 should start with this intake packet:
1. Request
   - what compare behavior is being preserved or improved
2. Baseline to preserve
   - current bypass, split compare, restore exactness, and transient-state behavior that must remain true
3. Writable surface
   - exact files to edit, or `plan-only`
4. Dependency gates in play
   - preset and parameter isolation, lifetime safety, deterministic composition, UI clarity
5. Required return artifacts
   - selftest/build log path, compare screenshots, lifetime note
6. Stop trigger
   - the first condition that forces escalation to Director A or root

### Stage 3.2 - Agent Release Packets

`compare-regression-agent`
- assignment:
  - prove bypass equivalence, restore exactness, and split determinism still hold after the pass
- writable files:
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
  - `app/main.mm`
  - `app/build.sh`
- required checks:
  - bypass equivalence
  - restore exactness
  - split-position determinism
- return artifacts:
  - `.logs/...` selftest or validation log
  - compare screenshots
  - note confirming whether selftest expectations changed
- stop rule:
  - halt if exact restore cannot be maintained through existing preset and parameter APIs

`compare-polish-agent`
- assignment:
  - improve compare affordances and transient-state clarity without changing persistence or lifetime rules
- writable files:
  - `app/SGAppDelegate.mm`
- required checks:
  - UI clarity
  - restore exactness
- return artifacts:
  - before/after screenshots if UI changed
  - note confirming compare remained transient
- stop rule:
  - halt if the request turns compare into a durable mode or requires new preset semantics

`frame-lifetime-agent`
- assignment:
  - validate that compare still respects output ownership and texture lifetime assumptions
- writable files:
  - `app/EngineBridge.h`
  - `app/EngineBridge.mm`
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/main.mm`
  - `app/build.sh`
- required checks:
  - live safety
  - boundary discipline
  - split-position determinism where lifetime handling is involved
- return artifacts:
  - `.logs/...` validation log
  - lifetime note naming the preserved rule or the precise seam that broke
  - file-touch summary
- stop rule:
  - halt if a safe fix requires a new backend contract or output-texture ownership model

### Stage 4 - Implementation Stages

Stage 4.1 - Freeze compare contract
- re-read compare mode state, bypass behavior, and split-position plumbing in `app/LivePipeline.*` and `app/SGAppDelegate.mm`
- confirm compare is still transient and visibly distinct from normal preset mode

Stage 4.2 - Audit render path touchpoints
- verify `app/EngineBridge.*` still exposes only the compare-safe output hooks the app needs
- verify selftest coverage in `app/main.mm` and `app/build.sh` still represents the compare baseline honestly

Stage 4.3 - Preserve restore exactness
- keep preset and parameter restoration exact on compare exit
- keep split positions deterministic at supported checkpoints

Stage 4.4 - Bounded extension triage
- allow compare affordance polish and tighter regression automation
- reject new durable compare modes, freeze-frame flows, or lifetime-expanding render behavior without root review

Stage 4.5 - Verification capture
- require artifacts proving bypass equivalence, split determinism, and texture-lifetime safety assumptions still hold

Stage exits:
- Exit 4.1 only when compare's transient contract is written explicitly in the packet
- Exit 4.2 only when compare-safe output hooks and selftest ownership are reconfirmed
- Exit 4.3 only when restore exactness and supported split checkpoints are named explicitly
- Exit 4.4 only when allowed polish is separated from new compare-mode requests
- Exit 4.5 only when the packet names literal artifact paths or a predeclared capture plan

### Stage 5 - Dependency Gates

Gate 1 - Preset and parameter isolation:
- compare must continue to consume public preset and parameter APIs without mutating their persistence semantics

Gate 2 - Lifetime safety:
- processed output ownership and capture-texture usage must remain explicit and verifiable

Gate 3 - Deterministic composition:
- split compare must remain pixel-position deterministic for the supported position set

Gate 4 - UI clarity:
- compare controls must stay visibly transient and separate from baseline preset browsing

### Stage 6 - Verification Artifacts

Required deliverables from any active work on this feature:
1. baseline contract summary
2. explicit statement of whether compare state or lifetime rules changed
3. regression checklist result
4. verification artifacts
5. bounded next-cut or backlog note if follow-up work is deferred

Expected verification artifacts:
- literal build or selftest log path, typically from `app/build.sh selftest`
- one screenshot for bypass held or equivalent preserved evidence
- one screenshot for split compare at a representative position
- one short note confirming the active texture-ownership rule, or confirming no change
- one note stating whether `app/main.mm` split-selftest expectations changed or remained unchanged

Artifact acceptance:
- screenshots without a lifetime or selftest note are insufficient
- a lifetime note without a literal log path is insufficient when compare behavior changed
- `plan-only` edits must still return the compare baseline statement that was revalidated

### Stage 7 - Verification Matrix

Minimum regression checks:
1. Bypass equivalence
   - confirm compare-held bypass still matches passthrough behavior in a representative scene
2. Restore exactness
   - rapidly enter and exit compare and confirm the prior preset and parameter values return exactly
3. Split-position determinism
   - confirm 0 percent, 50 percent, and 100 percent positions still behave as expected
4. Live safety
   - hold compare and exercise split compare through live frames without obvious stale-texture use, deadlock, or state corruption
5. Boundary discipline
   - confirm compare interactions do not rewrite selected preset persistence or parameter override stores

Use existing project validation commands appropriate to the touched code path and record literal log locations in `.logs/` when commands are run.

### Stage 8 - Stop Gates

Stop and escalate when:
- compare needs a new output-texture contract, new backend verb, or long-lived borrowed texture behavior
- bypass can no longer restore preset and parameter state exactly through existing public APIs
- split compare correctness depends on implicit behavior not covered by current selftest or artifact capture
- another director owns the only safe fix for a discovered lifetime bug

Stop-gate routing:
- return `blocked` when the issue is local to compare preservation but unresolved in the current pass
- return `needs-root` when the work demands new texture ownership, new backend contracts, or durable compare-state semantics

### Stage 9 - Next Cuts

Allowed next cuts for this feature:
- bounded compare affordance polish
- clearer mode labeling or transient-state signaling
- minor split-position interaction tuning
- targeted regression automation additions around compare restore and split-position checks

Cuts that require root review before work starts:
- freeze-frame or timeline-oriented compare flows
- compare state that persists as part of normal preset identity
- any approach that widens compare into shared-engine redesign
- any change that depends on retaining borrowed capture textures beyond the current safe rule

## Stopping Conditions

Stop and escalate when:
- compare can only progress by rewriting preset or parameter persistence rules
- texture ownership or frame-lifetime assumptions become unclear
- a UI request would force compare to act like a durable preset mode instead of a transient interaction
- concurrent upstream edits change the approved output-target seam or invalidate lifetime assumptions outside Director A ownership

## Procedure Risks

- The main risk is regression disguised as polish: compare already works, so teams may skip the exact restore and split-position checks that keep it trustworthy.
- Texture-lifetime safety remains the load-bearing technical risk as adjacent rendering code changes.
- UX simplification can accidentally blur the boundary between compare state and baseline preset state.

## Evaluation

This feature is in good shape when:
- bypass and split compare remain implemented, verified, and clearly transient
- regression checks are explicit enough for subordinate agents to run without re-deriving the compare contract
- next cuts are clearly bounded to polish and coverage, not architectural expansion
- the plan keeps compare preservation ahead of speculative new compare modes
