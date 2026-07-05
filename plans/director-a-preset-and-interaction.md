# Director A - Preset And Interaction

## Objective

Own the app-facing interaction layer above capture and shared-engine inheritance:
- Feature 1 - Preset Deck
- Feature 2 - Live Control Surface
- Feature 3 - Before/After Magic

This document is the execution artifact for Director A. It defines what may be delegated, what must stay within app-facing ownership, what evidence subordinate agents must return, and when work stops instead of drifting into adjacent domains.

Director A operates under Simon root orchestration:
- root authority: `plans/00-simon-root-orchestration.md`
- milestone sequencing: `plans/M1-SHADERGLASS-PLAYGROUND-ORCHESTRATION.md`
- owned feature plans only:
  - `plans/01-preset-deck.md`
  - `plans/02-live-control-surface.md`
  - `plans/03-before-after-magic.md`

Current truth:
- Features 1-3 already exist in the mac app
- work in this band is preservation, regression control, and bounded extension
- no feature in this band is authorized to reopen engine architecture locally

## Procedure

### Stage 0 - Ownership Boundary

Director A owns only the app-facing preset, parameter, and compare surfaces:
- `app/SGAppDelegate.h`
- `app/SGAppDelegate.mm`
- `app/LivePipeline.h`
- `app/LivePipeline.mm`
- app-facing portions of `app/EngineBridge.h`
- app-facing portions of `app/EngineBridge.mm`
- `app/main.mm` when selftest or compare menu wiring changes
- `app/build.sh` when selftest coverage changes
- curated app shader assets under `spike/*.metal` only when Feature 1-3 behavior depends on them
- plan maintenance for:
  - `plans/01-preset-deck.md`
  - `plans/02-live-control-surface.md`
  - `plans/03-before-after-magic.md`

Director A does not own:
- ScreenCaptureKit target enumeration, capture policy, or permission strategy beyond the UI handshake
- release packaging, codesigning, notarization, or ship criteria
- shared-engine inheritance design except for narrow app bridge seams already approved by root orchestration
- unrelated roadmap plans or implementation files owned by other directors

Concurrency rule:
- do not revert or overwrite concurrent edits
- prefer additive plan deltas and explicit dependency notes over speculative cleanup
- if another director changes an upstream contract, record the new dependency and stop at the boundary rather than silently absorbing the work

### Stage 1 - Current Status Snapshot

Verified current status:
- Feature 1 is implemented and serves as the baseline preset-selection path.
- Feature 2 is implemented and serves as the baseline parameter-control path.
- Feature 3 hold-to-bypass is implemented.
- Feature 3 split compare is implemented and strongly verified.
- Feature 3 already has app selftest coverage through `app/main.mm` and `app/build.sh selftest`.

Planning consequence:
- Feature 1 and Feature 2 are no longer implementation-first tracks. They are preservation, regression, and bounded extension tracks.
- Feature 3 is no longer blocked on target ownership. It moves into preservation, regression coverage, and next-cut triage.

### Stage 2 - Root Dependencies

Director A may proceed only within these root-level assumptions:
- Feature 1 preserves the descriptor-driven preset catalog already wired through `app/LivePipeline.*` and `app/SGAppDelegate.mm`.
- Feature 2 consumes app-facing parameter metadata from `app/EngineBridge.*`; it does not define a second contract.
- Feature 3 may rely on the existing compare output path and split selftest, but any new render-target or backend lifetime requirement routes to Director C.
- Capture policy, target enumeration, TCC handling, export semantics, and release packaging remain Director B surfaces even when the UI handshake is visible in `app/SGAppDelegate.mm`.

If any of those assumptions stop being true, Director A stops and escalates to root instead of normalizing the drift locally.

### Stage 3 - Subordinate Agent Roster

Director A may spawn only these subordinate agents for roadmap work under this slice.

Feature 1 agents:
- `preset-regression-agent`
  - owns preset catalog invariants, stable identifier drift checks, and preset-launch restoration coverage
- `deck-polish-agent`
  - owns bounded deck UX follow-ups that do not change preset identity or persistence contracts
- `thumbnail-integrity-agent`
  - owns thumbnail cache behavior, placeholder fallback, and resource-staleness checks

Feature 2 agents:
- `parameter-regression-agent`
  - owns parameter metadata drift checks, reset behavior coverage, and per-preset override replay verification
- `control-surface-polish-agent`
  - owns compact UI adjustments, disabled-state correctness, and value reflection after preset changes
- `param-persistence-agent`
  - owns persistence schema stability, migration notes, and stale-override rejection behavior

Feature 3 agents:
- `compare-regression-agent`
  - owns bypass and split compare regression coverage, pixel-position checks, and restore-exactness verification
- `compare-polish-agent`
  - owns bounded UX follow-ups for compare affordances without changing preset or parameter persistence semantics
- `frame-lifetime-agent`
  - owns evidence that compare still respects capture-texture and offscreen-texture lifetime rules as adjacent code evolves

Cross-feature support agent:
- `director-a-integration-agent`
  - owns narrow cross-feature checks where preset, parameter, and compare flows interact, but may not redesign any feature contract

### Stage 4 - Delegation Contract

Every subordinate agent assignment must specify:
- owned feature and boundary
- exact files or surfaces under review
- dependency gate being validated
- deliverable format
- verification artifact required before merge recommendation
- explicit stop condition

Required return artifacts from a subordinate agent:
1. a short status note: `done`, `blocked`, or `needs-root`
2. file-level impact summary
3. dependency findings
4. verification artifact list with literal paths where applicable
5. stop-condition trigger if work was halted

No subordinate agent may:
- widen shared-engine scope
- repurpose compare as preset persistence
- change capture policy
- absorb release or packaging work

### Stage 4.1 - Intake Packet

Before Director A releases any work packet, capture this intake in the feature plan or task note:
- requested outcome
- affected feature: `01`, `02`, or `03`
- current baseline statement to preserve
- exact app files expected to change, or `plan-only`
- dependency gates that must remain true
- required evidence on return
- explicit no-go surfaces outside Director A

Minimum intake example:
1. Request
   - one-sentence implementation or preservation task
2. Baseline to preserve
   - the user-visible behavior that must still hold after the pass
3. Writable surface
   - exact files the agent may edit
4. Evidence
   - log path, screenshot path, and plan note required on return
5. Stop gates
   - the first condition that forces the worker to halt and escalate

### Stage 4.2 - Agent Release Packet

Director A should release work to subordinate agents in this packet shape:
1. Assignment
   - feature id and named subordinate agent
2. Scope
   - exact owned behavior to preserve or extend
3. Writable files
   - literal file list, with `plan-only` if no code edits are authorized
4. Invariants
   - contract bullets that must remain unchanged
5. Required checks
   - the verification matrix rows the agent must execute
6. Return artifacts
   - literal `.logs/...` path, screenshot path, and short manifest note
7. Stop rule
   - the boundary condition that forces `blocked` or `needs-root`

### Stage 4.3 - Release Readiness Check

Director A should not release a packet unless all of the following are already true:
- the feature baseline statement is still accurate against current code
- the writable files fall fully inside Director A ownership
- at least one verification artifact is named before work starts
- the stop gate names the cross-director failure mode explicitly
- the packet can be executed without asking root to reinterpret the feature contract

### Stage 5 - Feature Execution Model

Director A executes each feature with the same bounded loop:

1. Baseline re-read
   - confirm the feature still matches the current code and root plan
   - confirm the write surface is still inside Director A ownership
2. Regression contract freeze
   - list the invariants that must not move
   - name the exact files where those invariants currently live
3. Bounded extension triage
   - separate safe polish from changes that alter contracts
   - route contract-shifting requests back to root
4. Verification artifact capture
   - require literal log paths, screenshots, or manifest notes before calling the feature healthy
5. Stop or release
   - release only when the owned feature plan is executable in isolation
   - stop immediately on cross-director drift

Stage exits:
- Exit Stage 1 only when the feature plan states the current truth in present tense
- Exit Stage 2 only when every dependency is mapped to a named feature or director
- Exit Stage 3 only when each subordinate agent has one distinct job, not overlapping charter language
- Exit Stage 4 only when a release packet can be copied into a delegated task without interpretation
- Exit Stage 5 only when the feature plan includes feature-specific artifacts and stop gates

### Stage 6 - Dependency Gates

Director A may advance work only when these gates hold:

Gate A - Preset identity stability:
- preset ids remain stable across deck, persistence, and compare restore paths

Gate B - Parameter contract stability:
- app-facing parameter metadata remains authoritative for the control surface
- preset switches and compare restore do not write stale values into a new parameter set

Gate C - Compare lifetime safety:
- split compare continues to respect the existing processed-target and frame-lifetime rules

Gate D - UI boundary discipline:
- top-level app interaction changes do not require unplanned capture, release, or shared-engine redesign

### Stage 7 - Verification Artifacts

Every Director A feature plan must name literal evidence, not implied confidence.

Accepted artifact types:
- build or selftest log under `.logs/`
- screenshot artifact path produced during manual or scripted verification
- manifest note inside the relevant feature plan when no code contract changed
- file-level impact summary naming the exact app files touched or intentionally left untouched

Preferred command surfaces:
- `backend/build_test.sh`
- `capture/build_test.sh`
- `app/build.sh selftest`

Feature-specific minimums:
- Feature 1: deck screenshot plus selected-preset persistence note
- Feature 2: control-surface screenshot plus parameter replay note
- Feature 3: split compare screenshot plus selftest log proving compare baseline still holds

Artifact manifest discipline:
- every artifact path must be literal, not described abstractly
- if no code changes occur, return a `plan-only` manifest note explaining what was revalidated
- if a worker claims baseline preservation, the artifacts must show the preserved behavior directly
- if the worker cannot produce the named artifact set, the packet returns `blocked`

### Stage 8 - Deliverables By Feature

Feature 1 deliverables:
- preserved baseline plan with regression matrix
- identified bounded polish backlog
- verification artifact list for preset identity, deck behavior, and thumbnail fallback

Feature 2 deliverables:
- preserved baseline plan with regression matrix
- identified bounded polish backlog
- verification artifact list for parameter metadata, reset behavior, and persistence replay

Feature 3 deliverables:
- preserved baseline plan with regression matrix
- identified next-cut candidates after split compare
- verification artifact list for bypass equivalence, split-position correctness, and frame-lifetime safety

Director-level deliverable:
- this plan plus the three feature plans must let root orchestration spawn subagents without re-deriving ownership or stop rules
- each feature plan must contain an intake packet, agent packet structure, implementation stages, artifact manifest, and stop-gate table that can survive handoff to another worker

## Stopping Conditions

Stop and escalate to root when:
- a requested change crosses from app-facing behavior into shared-engine redesign
- preset identity or parameter persistence would need to regress to enable compare or polish work
- compare lifetime safety depends on a contract Director A does not own
- concurrent edits invalidate a dependency assumption and the safe resolution belongs to another director
- a subordinate agent cannot produce verification artifacts for a claimed baseline-preservation change
- the same app file becomes an active write surface for another director and the boundary is no longer clean
- an implementation request treats Features 1-3 as unfinished greenfield tracks instead of baseline-preservation work

## Procedure Risks

- The main failure mode is scope creep: preservation work can drift into engine redesign if boundaries are not enforced.
- Feature 1 and Feature 2 are at highest risk of quiet contract drift because they already work and can be broken by unrelated app polish.
- Feature 3 is at highest risk of regression in texture-lifetime assumptions as adjacent rendering code changes.
- Too many small agents can create reporting overhead without improving correctness. Spawn only when ownership is genuinely separable.
- `app/SGAppDelegate.mm` is a shared pressure point across all three features, so sequencing discipline matters more than parallel edits on that file.

## Evaluation

Director A is operating correctly when:
- each feature plan reads as an executable delegation artifact rather than a speculative design memo
- Features 1 and 2 are framed as implemented baselines with preservation and bounded follow-up work
- Feature 3 is framed as implemented and strongly verified, with emphasis on regression coverage and next cuts
- subordinate agents can be spawned with clear boundaries, deliverables, and stop rules
- no plan text implies ownership of capture, release, or broad shared-engine work
