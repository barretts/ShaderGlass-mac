# Feature 2 - Live Control Surface

## Objective

Preserve the implemented live control surface as the authoritative parameter-editing baseline, keep parameter metadata and persistence stable, and constrain follow-up work to regression coverage and bounded ergonomic improvements.

Current status:
- implemented baseline
- app-facing parameter metadata and update flows exist
- per-preset persistence is already part of the working surface

This plan is now an execution artifact for keeping the baseline healthy while allowing only narrow extensions that do not widen ownership into shared-engine redesign.

## Procedure

### Stage 0 - Ownership Boundary

This feature owns:
- app-facing parameter metadata consumption
- control-surface interaction behavior
- render-safe parameter mutation routing through the app pipeline
- per-preset override persistence and reset flows
- app file touchpoints:
  - `app/EngineBridge.h`
  - `app/EngineBridge.mm`
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
  - `app/build.sh` when parameter coverage is added to selftest

This feature does not own:
- preset browsing and catalog layout beyond the hooks needed to react to preset changes
- compare state or compare-specific restore semantics except through public parameter APIs
- arbitrary exposure of internal engine uniforms
- shared-engine architecture outside the approved app bridge contract

### Stage 1 - Current Baseline Contract

The implemented baseline must continue to guarantee:
- active editable parameters are surfaced through app-facing metadata rather than raw engine pointers
- parameter writes stay on the safe pipeline path
- per-preset overrides stay keyed by stable preset id
- reset flows restore expected defaults without leaking values across presets
- switching presets clears or replaces stale control state before new writes land

If a proposed follow-up breaks any of these guarantees, stop and replan.

### Stage 2 - Root Dependencies

This feature runs after Feature 1 inside the Director A stack.

Upstream dependency:
- stable preset ids from Feature 1 remain the persistence key for overrides

Downstream dependency:
- Feature 3 assumes parameter restore remains exact when compare exits

Cross-director dependency:
- if app-facing metadata from `app/EngineBridge.*` can no longer shield the UI from shared-engine internals, route the seam problem to Director C

### Stage 3 - Subordinate Agent Roster

Director-approved agents for this feature:
- `parameter-regression-agent`
  - validates metadata drift, parameter identifier stability, and reset correctness
- `control-surface-polish-agent`
  - handles bounded UI layout, disabled-state, and interaction-feedback improvements
- `param-persistence-agent`
  - validates override replay, stale-value rejection, and migration behavior keyed by preset id

Agent ownership split:
- metadata and reset correctness belong to `parameter-regression-agent`
- visual and ergonomic control updates belong to `control-surface-polish-agent`
- persistence and replay semantics belong to `param-persistence-agent`

### Stage 3.1 - Intake Packet

Every future pass on Feature 2 should start with this intake packet:
1. Request
   - what parameter-editing behavior is being preserved or improved
2. Baseline to preserve
   - current metadata-driven controls, reset behavior, and per-preset replay that must remain true
3. Writable surface
   - exact files to edit, or `plan-only`
4. Dependency gates in play
   - preset id stability, public parameter contract, mutation safety, sparse-set tolerance
5. Required return artifacts
   - build/selftest log path, control-surface screenshot, replay note
6. Stop trigger
   - the first condition that forces escalation to Director A or root

### Stage 3.2 - Agent Release Packets

`parameter-regression-agent`
- assignment:
  - prove the metadata contract, identifier stability, and reset paths still behave as the UI expects
- writable files:
  - `app/EngineBridge.h`
  - `app/EngineBridge.mm`
  - `app/LivePipeline.h`
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
  - `app/build.sh` only when coverage changes
- required checks:
  - parameter delta
  - reset exactness
  - sparse metadata handling
- return artifacts:
  - `.logs/...` build or selftest log
  - screenshot of a valid edited state
  - note confirming whether identifiers/defaults changed
- stop rule:
  - halt if the UI needs raw engine state instead of app-facing metadata

`control-surface-polish-agent`
- assignment:
  - improve grouping, disabled states, or interaction clarity without changing the parameter contract
- writable files:
  - `app/SGAppDelegate.mm`
- required checks:
  - live mutation safety
  - disabled-state and preset-switch reflection
- return artifacts:
  - before/after screenshots if UI changed
  - note confirming no persistence or identifier contract changes
- stop rule:
  - halt if polish requires exposing new engine internals or changing persistence semantics

`param-persistence-agent`
- assignment:
  - validate replay, stale-value rejection, and migration behavior keyed by preset id
- writable files:
  - `app/EngineBridge.mm`
  - `app/LivePipeline.mm`
  - `app/SGAppDelegate.mm`
- required checks:
  - persistence replay
  - sparse metadata handling
  - reset exactness
- return artifacts:
  - `.logs/...` validation log
  - replay note describing preserved or changed storage behavior
  - file-touch summary
- stop rule:
  - halt if replay can no longer remain keyed by stable preset id

### Stage 4 - Implementation Stages

Stage 4.1 - Freeze metadata contract
- re-read the current parameter snapshot and reset APIs in `app/EngineBridge.h`
- confirm the UI still consumes metadata objects, not raw engine state

Stage 4.2 - Audit control ownership
- verify `app/SGAppDelegate.mm` still owns control creation, labeling, and disabled-state handling
- verify `app/LivePipeline.*` remains only the routing surface for live updates

Stage 4.3 - Preserve persistence rules
- keep per-preset override storage keyed by preset id
- keep reset-one and reset-all behavior exact

Stage 4.4 - Bounded extension triage
- allow ergonomic improvements, grouping, and value-reflection polish
- reject contract expansion that exposes arbitrary engine internals

Stage 4.5 - Verification capture
- require artifacts proving live mutation, reset exactness, and replay safety

Stage exits:
- Exit 4.1 only when the metadata source and public app contract are named explicitly
- Exit 4.2 only when control creation and mutation routing owners are reconfirmed
- Exit 4.3 only when replay and reset semantics are stated in feature-language, not implied
- Exit 4.4 only when allowed polish is separated from contract expansion requests
- Exit 4.5 only when the packet lists literal artifact paths or a predeclared capture plan

### Stage 5 - Dependency Gates

Gate 1 - Preset id stability:
- override persistence is only valid while Feature 1 preset ids remain stable

Gate 2 - Public parameter contract:
- UI work must consume the existing app-facing parameter metadata contract, not shared-engine internals

Gate 3 - Mutation safety:
- parameter writes must continue to route through the existing safe app pipeline path

Gate 4 - Sparse-set tolerance:
- switching between presets with different parameter sets must not leave stale UI or stale writes behind

### Stage 6 - Verification Artifacts

Required deliverables from any active work on this feature:
1. baseline contract summary
2. touched parameter identifiers or a confirmation that identifiers did not change
3. reset and persistence regression result
4. verification artifacts
5. bounded backlog note for any deferred UI follow-up

Expected verification artifacts:
- literal build or selftest log path
- one screenshot of the control surface in a non-default but valid state
- one short parameter note confirming the active identifiers/defaults touched by the change, or confirming no contract change
- one replay note confirming whether per-preset override storage changed or stayed identical

Artifact acceptance:
- a screenshot without a replay or contract note is insufficient
- a replay note without a literal log path is insufficient when behavior changed
- `plan-only` edits must still return the metadata contract statement that was revalidated

### Stage 7 - Verification Matrix

Minimum regression checks:
1. Parameter delta
   - apply a visible parameter change and confirm rendered output changes
2. Reset exactness
   - reset one parameter and reset all parameters, then confirm the expected default state returns
3. Persistence replay
   - relaunch and verify overrides restore only for the matching preset id
4. Sparse metadata handling
   - switch between presets with different control sets and verify stale controls do not write into the new preset
5. Live mutation safety
   - exercise control changes during live rendering and confirm there is no obvious thread violation, deadlock, or frame corruption

Use existing project validation commands appropriate to the touched code path and record literal log locations in `.logs/` when commands are run.

### Stage 8 - Stop Gates

Stop and escalate when:
- the UI needs direct ownership of raw engine objects or unmanaged lifetimes
- parameter identifiers stop being stable enough for persistence replay
- reset semantics differ between static and live rendering without an approved reason
- Feature 3 requests compare-specific persistence behavior instead of consuming the existing public parameter contract

Stop-gate routing:
- return `blocked` when the issue is within Feature 2 ownership but cannot be resolved in the current pass
- return `needs-root` when the work requires new engine-surface exposure, persistence-key redesign, or a boundary change with Director C

### Stage 9 - Next Cuts

Allowed next cuts for this feature:
- tighter layout or clearer grouping of existing controls
- better disabled-state and empty-state handling
- bounded coalescing or pacing improvements if slider traffic becomes noisy
- additional curated controls only when the parameter contract is explicit and already supported by the app-facing bridge

Cuts that require root review before work starts:
- generic exposure of internal engine uniforms
- live shader recompilation as part of the control loop
- direct AppKit ownership of raw shared-engine objects or pointers
- persistence changes that stop being keyed by stable preset id

## Stopping Conditions

Stop and escalate when:
- parameter metadata can no longer be trusted as the app-facing contract
- a UI request depends on raw engine pointers or direct shared-engine lifetime management
- reset or replay semantics become ambiguous across preset switches
- concurrent upstream edits move the parameter ownership seam outside Director A

## Procedure Risks

- Metadata drift is the primary risk because the feature already works and can be broken by small contract changes.
- Persistence bugs are easy to miss if relaunch and preset-switch checks are not paired.
- Control-surface polish can accidentally widen into a demand for engine-surface redesign if the public contract is not enforced.

## Evaluation

This feature is in good shape when:
- the current control surface remains the authoritative parameter-editing path
- parameter metadata, reset behavior, and per-preset persistence remain stable
- subordinate agents have clear boundaries between regression work, persistence work, and UI polish
- any next cut is obviously bounded and does not reopen the shared-engine design
