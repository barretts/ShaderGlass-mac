# Feature 5 - Export Moment

## Objective

Preserve the implemented export baseline while compare and app work continue around it: a user-facing export action that saves the rendered shader output as a PNG from both static and live capture modes, with thread ownership, cancellation behavior, and UI feedback kept explicit.

The exported image remains the processed ShaderGlass output, not the raw capture frame. Compare work does not change that contract unless Director B explicitly reopens scope.

Root placement:
- owner: `director-b-capture-and-shipping`
- root sequence position: Feature 5 follows Feature 4 and must be current before Feature 6 review
- private-release signoff is blocked if export evidence is stale after compare or render-path changes

## Procedure

### Stage 0 - Preserved Export Contract

The baseline to preserve is already implemented:
- export entry exists in the app surface
- `LivePipeline` owns export orchestration
- export is single-flight
- live export resolves against the processed output path
- stop, quit, and resize behavior are already defined and should not drift silently

Contract statements that remain load-bearing:
- `LivePipeline` is the public export boundary
- `EngineBridge` and backend readback stay behind that boundary
- main-thread UI may request export but may not own pixel readback
- compare mode may affect what is shown on screen, but default export target remains the processed frame unless Director B records a new decision

### Stage 1 - File Touchpoints

Primary files:
- `app/LivePipeline.h`
- `app/LivePipeline.mm`
- `app/EngineBridge.h`
- `app/EngineBridge.mm`
- `app/SGAppDelegate.mm`

Secondary files that can force reevaluation without changing ownership:
- `backend/IRenderBackend.h`
- `backend/MetalBackend.mm`
- `capture/SCKCapture.mm`
- `release/private-build.sh`

### Stage 2 - Ownership Boundaries And Agent Roster

Director: `director-b-capture-and-shipping`

Director B owns:
- export semantics and truthfulness
- render-thread ownership verification
- regression review when compare/app changes touch export-related code paths
- evidence required before private release can claim export remains healthy

Director B does not own:
- compare mode UX or compositor design except where those changes threaten export semantics
- broad backend architecture beyond the bounded export contract
- new batch or history export features

Subordinate agents:
- `export-contract-agent`: verify that exported pixels still mean processed output and not an accidental compare composite.
- `render-thread-agent`: inspect `LivePipeline` and `EngineBridge` changes for ownership drift, double completion, or queue ambiguity.
- `export-compare-impact-agent`: inspect compare-specific changes only for export-surface or split-mode side effects.
- `export-ui-agent`: verify menu, save panel, pending state, and status messaging remain bounded and accurate.
- `export-qa-agent`: produce PNG, dimension, resize, stop, and quit evidence.

Artifacts expected back from each agent:
- contract note
- code-impact note
- verification artifact reference
- explicit blocker if export truth can no longer be stated clearly

### Stage 2A - Intake Packet For Future Work

Before implementation or verification, assemble a Feature 5 intake packet with:
- branch SHA
- touched files within `LivePipeline`, `EngineBridge`, `SGAppDelegate`, and relevant backend paths
- compare-related churn summary:
  - no compare impact
  - compare UI only
  - compare texture/compositor impact
- lifecycle impact summary:
  - resize path touched
  - stop/quit path touched
  - save panel or export UI path touched
- last known good export artifacts and whether they are still valid for this SHA

Decision from the intake packet:
- `preserve-only`: no export-relevant touchpoint moved
- `verify-only`: touchpoint moved but export contract is still likely intact
- `bounded-fix`: current branch state threatens export truth or lifecycle correctness

### Stage 3 - Implementation Stages

1. preserve export contract:
   - keep exported frame bound to processed ShaderGlass output
   - keep compare presentation separate from export unless explicitly reopened
2. preserve ownership boundaries:
   - keep export orchestration in `LivePipeline`
   - keep backend readback behind `EngineBridge`
3. preserve single-flight behavior:
   - keep one in-flight export at a time
   - keep UI disablement and completion signaling consistent
4. preserve lifecycle correctness:
   - keep resize, stop, and quit behavior deterministic while export is pending
   - keep completion or cancellation emitted exactly once
5. refresh evidence when branch touchpoints moved:
   - rerun export smoke after compare, texture-retention, or render-path edits
   - carry evidence forward only when no export-relevant touchpoint changed

### Stage 3A - Agent Release Packets

`export-contract-agent`
- files: `app/LivePipeline.*`, `app/EngineBridge.*`, compare-related call sites when touched
- task: state exactly what pixels the current export path writes
- must return:
  - processed-output contract note
  - ambiguity note if on-screen compare presentation diverges

`render-thread-agent`
- files: `app/LivePipeline.*`, `app/EngineBridge.*`, backend readback path when touched
- task: verify single-flight ownership and exactly-once completion behavior
- must return:
  - ownership map
  - resize/stop/quit impact note
  - blocker if queue ownership is no longer clear

`export-compare-impact-agent`
- files: compare UI/compositor paths that changed
- task: determine whether compare churn changes retained-texture choice or export surface selection
- must return:
  - no-impact note, or
  - concrete ambiguity that requires root review

`export-ui-agent`
- files: `app/SGAppDelegate.mm` and save-panel call sites
- task: verify reentry disablement, status messaging, and completion feedback
- must return:
  - UI state note for pending, success, and failure paths

`export-qa-agent`
- files: none required beyond runnable app and notes
- task: produce the smallest current evidence set that matches the touched surfaces
- must return:
  - PNG references
  - resize/shutdown result note
  - explicit blocked note if a scenario could not be rerun

### Stage 4 - Dependency Gates

Trigger review when any of these branch surfaces move:
- `app/LivePipeline.*`
- `app/EngineBridge.*`
- `app/SGAppDelegate.*`
- compare compositor or compare-mode UI paths that change what textures are retained or selected
- resize, shutdown, or capture-state handling that can affect pending export completion

Gate rules:
1. if compare changes alter only UI selection without touching retained textures or pipeline state, carry forward prior export evidence
2. if compare changes touch processed textures, split composition, or live render flow, rerun export regression checks
3. if export behavior and compared view diverge, keep the processed-output export contract unless root explicitly approves a scope change
4. if resize, stop, or quit semantics become unclear, block Feature 6 release signoff until new evidence exists

Dependencies on other features:
- depends on Feature 4 for trustworthy live capture entry and stable running state
- depends on Feature 3 only for compare-surface impact review, not compare redesign
- must be current before Feature 6 private release can claim export health

### Stage 5 - Deliverables

Required deliverables for an active branch:
- contract statement: export target is still the processed output
- regression checklist:
  - static export writes a readable nonblank PNG
  - live export writes a readable nonblank PNG
  - export remains single-flight
  - resize during export resolves without deadlock or corrupt dimensions
  - stop and quit while export is pending resolve exactly once
- compare interaction note:
  - whether current compare changes touch export-relevant textures
  - whether any new ambiguity exists between compared view and exported frame

Implementation packet output for future delegated work:
- issue statement:
  - which branch change threatened export semantics or lifecycle behavior
- bounded change list:
  - exact Director B-owned files allowed for implementation
- verification bundle:
  - which export checks were rerun on this SHA
  - which evidence was carried forward unchanged
- release implication:
  - whether Feature 6 remains blocked on refreshed export proof

### Stage 6 - Verification Artifacts

Primary artifacts:

```sh
app/build.sh selftest
backend/build_test.sh
capture/build_test.sh
```

Manual or artifact-backed checks to refresh after relevant branch changes:
- one static-mode exported PNG
- one live capture exported PNG
- one resize-while-exporting result
- one stop-or-quit-while-exporting result
- one note comparing exported output with on-screen compare state when split compare paths changed

Artifact expectations:
- one current exported PNG from static mode
- one current exported PNG from live mode when live-path code changed
- one current note covering resize or shutdown behavior under pending export
- one explicit contract note when compare-related branch changes were reviewed and found not to alter export semantics

Preferred evidence bundle names for delegated work:
- `feature-5-intake.md`
- `feature-5-contract-note.md`
- `feature-5-export-checklist.md`
- `feature-5-lifecycle-note.md`

If these are not created as files, the same packet structure must still be reflected in the returned notes or plan update.

## Stopping Conditions

This feature remains acceptable only when all of the following are still true:
- Static mode exports a nonblank PNG.
- Live window capture exports a nonblank PNG.
- Export requests are render-thread owned, not main-thread owned.
- Resize during export does not crash, deadlock, or write corrupt dimensions.
- Stop and quit while export is pending resolve exactly once with a clean failure or cancellation.
- Export UI disables reentry while a request is pending.

Stop and replan when any of the following becomes true:
- compare/app changes make it unclear whether export should reflect processed output or compared composition
- correct export now requires invasive backend redesign outside bounded readback ownership
- queue ownership becomes ambiguous between capture, AppKit, and backend layers
- pending export completion behavior can no longer be stated confidently for resize, stop, or quit
- the exported PNG can no longer be tied to a single retained processed-output path with current evidence

Delegation stop gates:
- stop `export-contract-agent` if exported-surface policy now requires a product decision rather than a code fix
- stop `render-thread-agent` if completion correctness depends on shared backend redesign outside Director B scope
- stop `export-ui-agent` if UI truth depends on behavior that the export path cannot currently guarantee
- stop the whole Feature 5 pass if no current artifact can prove what output surface is being exported on this SHA

## Procedure Risks

- Compare work can create user expectations that diverge from the preserved export contract if the branch does not state the difference clearly.
- The retained output texture may not match final composed output in every presentation mode.
- Capture frames are transient; export logic must not retain borrowed frame resources beyond their safe lifetime.
- Waiting for GPU completion too often will degrade live performance; synchronization must be export-scoped.
- App-surface changes can quietly reintroduce overlapping export requests or stale status messaging.

## Evaluation

This plan is healthy when:
- export semantics are still explicit enough to survive compare churn without hand-waving
- release signoff can point to current export evidence instead of historical assumptions
- any mismatch between compared view and exported output is documented as an intentional contract, not an accident

## Open Risks To Carry Forward

- Overlay display export may need a follow-on decision if "engine output" and "final screen composition" diverge materially.
- Batch export or repeated capture snapshots are out of scope for this milestone and should not be smuggled into the single-flight API.
