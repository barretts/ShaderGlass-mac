# Director B - Capture And Shipping

## Objective

Own the preserved baseline for the reliable live-entry path and the private-shipping path: capture target selection, export behavior, and private release packaging.

Owned features:
- Feature 4 - Capture Picker Polish
- Feature 5 - Export Moment
- Feature 6 - Private Release Build

Root orchestration context:
- root scheduler: `expert-orchestrator-simon`
- Director B runs after Feature 2 baseline stability and before Feature 7 shipping claims
- the job is preservation and truthful shipping, not scope expansion

## Procedure

### Stage 0 - Director Contract

Current state to preserve:
- Feature 4 is implemented and live smoke has already passed for display, window, and overlay flows.
- Feature 5 is implemented and exports PNG from the retained processed-output path.
- Feature 6 is implemented with `release/private-build.sh`, strict signing mode, release manifests, and gate logging.

Director B is not reopening these features for redesign. The operating mode is preservation:
- keep the current contracts explicit
- catch regressions introduced by compare/app changes
- keep release claims truthful as the branch moves

Director B success condition:
- Feature 4 remains a believable live-entry path
- Feature 5 remains a truthful processed-output export path
- Feature 6 remains a truthful private-shipping path
- each accepted claim is backed by a current artifact, log, or explicit blocked note

### Stage 1 - Ownership Boundary

Director B owns:
- capture-target UX and stale-target recovery behavior in `app/SGAppDelegate.*`
- capture-layer coordination in `capture/SCKCapture.*`
- export orchestration through `app/LivePipeline.*` and `app/EngineBridge.*`
- release scripts, manifests, and shipping docs under `release/`, `dist/`, and `RUNNING.md`
- plan execution and verification artifacts for Features 4, 5, and 6

Director B does not own:
- preset catalog design
- compare mode UX beyond export interaction policy and branch-gate review
- shared-engine inheritance scope
- compare compositor design or mode semantics, except where those changes alter export truth or live-state safety
- root release criteria outside the bounded private-release contract

Primary file touchpoints inside Director B scope:
- `app/SGAppDelegate.h`
- `app/SGAppDelegate.mm`
- `app/LivePipeline.h`
- `app/LivePipeline.mm`
- `app/EngineBridge.h`
- `app/EngineBridge.mm`
- `capture/SCKCapture.h`
- `capture/SCKCapture.mm`
- `release/private-build.sh`
- `dist/manifest.json`
- `dist/checksums.txt`
- `dist/release-notes.txt`
- `RUNNING.md`

### Stage 2 - Subordinate Agent Roster

Director B may create only bounded subagents tied to one feature contract at a time.

Feature 4 roster:
- `capture-regression-agent`: verify target restore, stale-target recovery, and start/stop safety after app-side changes.
- `permission-state-agent`: verify denied, revoked, and relaunch-needed states remain honest.
- `overlay-safety-agent`: verify control-window and overlay exclusion still hold for display capture.
- `capture-qa-agent`: collect smoke evidence, screenshots, and command logs for live-entry behavior.

Feature 5 roster:
- `export-contract-agent`: enforce that export still means processed frame output unless Director B explicitly changes scope.
- `render-thread-agent`: verify queue ownership, single-flight behavior, and resize/stop/quit handling after compare or app edits.
- `export-compare-impact-agent`: inspect compare-related app changes only for export-surface drift.
- `export-qa-agent`: collect exported PNG evidence, dimensions, and failure-mode logs.

Feature 6 roster:
- `release-runner-agent`: run and inspect the bounded private-release flow without widening scope to public distribution.
- `signing-truth-agent`: verify identity use, fallback behavior, and recorded signing diagnostics.
- `gate-audit-agent`: verify branch gates, log capture, and manifest references remain truthful.
- `distribution-agent`: verify packaged artifact naming, checksum integrity, and tester-facing notes.

Cross-feature support:
- `branch-watch-agent`: watch `app/`, `capture/`, and `release/` deltas that can destabilize Features 4-6.
- `evidence-agent`: keep a durable list of verification artifacts and unresolved blockers for root review.

Spawn rule:
- Spawn subagents only when work can run independently and hand back a concrete artifact.
- Keep work single-threaded when the change is only plan maintenance or one verification pass.

### Stage 3 - Dependency Gates

Release order inherited from root:
1. preserve Feature 4 after incoming app/capture churn
2. preserve Feature 5 after compare or render-path churn
3. allow Feature 6 shipping review only after current Feature 4 and Feature 5 evidence exists

Director B proceeds feature by feature through these gates:
1. intake gate: identify whether branch changes touched `SGAppDelegate`, `LivePipeline`, `EngineBridge`, `SCKCapture`, or release scripts
2. contract gate: decide whether the change preserves or threatens the existing Feature 4, 5, or 6 contract
3. evidence gate: collect the minimum regression artifacts before accepting the branch state
4. release gate: allow private packaging only if Features 4 and 5 still have truthful verification coverage

Specific incoming dependencies:
- Director A compare/app changes may alter top-bar behavior, compare textures, export triggers, or live-state transitions.
- Director C engine planning may expose M2 branch churn that touches render paths but is not allowed to redefine Feature 5 output semantics.
- Root orchestration may reorder branch gates, but Director B still owns truthfulness for Features 4-6 before private release claims are made.

### Stage 3A - Director Intake Packet

Every future Director B pass should begin by assembling one intake packet before any implementation or verification work starts.

Required intake fields:
- branch identifier and `git rev-parse HEAD`
- touched Director B surfaces:
  - `app/SGAppDelegate.*`
  - `app/LivePipeline.*`
  - `app/EngineBridge.*`
  - `capture/SCKCapture.*`
  - `release/private-build.sh`
  - `dist/*`
  - `RUNNING.md`
- upstream source of churn: Director A, Director C, release hygiene, or standalone regression fix
- feature impact classification:
  - Feature 4 affected / unaffected
  - Feature 5 affected / unaffected
  - Feature 6 affected / unaffected
- evidence freshness classification:
  - current on this SHA
  - stale because owned surface moved
  - blocked by local machine/runtime constraint
- release recommendation state:
  - not eligible for review
  - eligible pending evidence refresh
  - eligible for private-release review

Packet output:
- one short branch-state note in this file
- one pointer to the feature plan packets that need refresh
- one explicit "do not touch" note for unaffected features

### Stage 4 - Deliverables By Feature

Feature 4 deliverables:
- preserved capture contract in [04-capture-picker-polish.md](/Users/ephem/lcode/ShaderGlass/mac/plans/04-capture-picker-polish.md)
- current regression checklist for display, window, stale-target, and permission states
- durable evidence references for live smoke and any blocked scenarios

Feature 5 deliverables:
- preserved export contract in [05-export-moment.md](/Users/ephem/lcode/ShaderGlass/mac/plans/05-export-moment.md)
- explicit compare-to-export decision record: processed output remains default unless root approves a different scope
- evidence list for static export, live export, resize behavior, and stop/quit resolution

Feature 6 deliverables:
- truthful release gate in [06-private-release-build.md](/Users/ephem/lcode/ShaderGlass/mac/plans/06-private-release-build.md)
- required release artifact list: zip, manifest, checksums, release notes, gate logs
- explicit block list for missing signing, missing logs, or failed branch gates

Director-level deliverables:
- this execution artifact
- one current list of subordinate agents and their bounded outputs
- one clear escalation path when compare/app changes threaten preserved contracts

### Stage 4A - Agent Release Packets

Subordinate work should be handed out as release packets, not general reminders.

Each packet must include:
- target feature and branch SHA
- exact owned files or behaviors under review
- required artifact to return
- stop gate that forces handback instead of speculative fixing
- maximum scope:
  - plan refresh only
  - verification only
  - bounded implementation plus verification

Packet templates:

`capture-regression-agent`
- input: `SGAppDelegate` and `SCKCapture` diffs, last known picker evidence
- work: identify whether selection state, restore, stale-target recovery, or start enablement changed
- return: updated regression checklist plus one note per changed behavior
- stop gate: any need to redesign capture model or compare UX

`permission-state-agent`
- input: signing/app identity changes, permission UI/status changes
- work: verify whether denied, revoked, or relaunch-required messaging drifted from real OS behavior
- return: permission truth note with exact affected states
- stop gate: permission truth depends on unsigned or identity-unstable builds only

`overlay-safety-agent`
- input: window-layering or display-capture changes
- work: verify exclusion/click-through policy still matches display-capture contract
- return: one overlay safety note tied to current branch state
- stop gate: fix would require ownership outside Director B surface

`export-contract-agent`
- input: `LivePipeline`/`EngineBridge` diffs and compare churn summary
- work: determine whether export still means processed output
- return: one contract note plus ambiguity list, if any
- stop gate: exported surface cannot be stated without root policy change

`render-thread-agent`
- input: export path diffs
- work: inspect single-flight ownership, completion path, and resize/stop/quit handling
- return: one ownership note plus concrete regression findings
- stop gate: resolution requires backend redesign beyond bounded export path

`release-runner-agent`
- input: release script diff and current gate status
- work: verify the private-build flow still matches documented packaging truth
- return: release-run log reference plus truth summary
- stop gate: required gate or signing precondition cannot run honestly

`gate-audit-agent`
- input: current gate set and `.logs/` outputs
- work: map every claimed gate to an actual log or blocked note
- return: gate ledger with pass/fail/blocked state
- stop gate: any shipping claim lacks artifact backing

### Stage 5 - Verification Artifacts

Shared branch-gate artifacts:

```sh
backend/build_test.sh
capture/build_test.sh
app/build.sh selftest
```

Feature-specific artifacts to keep current:
- Feature 4: picker smoke notes, stale-target note, permission-state note, overlay note
- Feature 5: static export PNG, live export PNG, resize or quit export note
- Feature 6: `release/private-build.sh` log, `dist/manifest.json`, `dist/checksums.txt`, packaged-app verification notes

Director B treats `.logs/`, generated PNGs, and release manifest files as the primary evidence set.

### Stage 6 - Active Work Loop

Primary loop:
1. read incoming compare/app/release diffs that intersect Director B surface area
2. classify impact by feature contract
3. assign at most one bounded subagent per independent verification stream
4. require an artifact back from each stream: checklist, log reference, screenshot, manifest note, or blocked-state note
5. update the relevant feature plan only when the contract, gate, or evidence requirement changed
6. release Feature 6 review only when Feature 4 and Feature 5 evidence is current on the same branch state

Immediate priorities on the current branch:
1. confirm compare cut 2 does not silently change what Feature 5 exports
2. preserve Feature 4 picker correctness if compare/app changes alter live-state controls or status handling
3. keep Feature 6 private-release verification aligned with actual branch health, not historical green runs
4. stop any release recommendation that lacks current evidence for export or live-entry behavior

### Stage 6A - Future Implementation Pass Shape

When Director B is asked to do more than plan maintenance, the future pass should run in this bounded order:
1. assemble the Director intake packet
2. classify whether work is preservation-only or bounded follow-on implementation
3. dispatch only the feature packets needed for changed surfaces
4. land the smallest owned implementation change required to restore contract truth
5. refresh feature-level verification artifacts on the same branch SHA
6. update Feature 4, 5, or 6 packet files with new evidence status and stop gates
7. return one director summary that states:
   - what changed
   - what stayed preserved
   - what remains blocked
   - whether Feature 6 is still allowed to advance

## Stopping Conditions

Stop and escalate to root when:
- compare changes require Director B to reinterpret what export should save
- capture or release smoke starts failing because of engine-layer work outside Director B ownership
- signing, TCC, or packaging constraints invalidate the private-release contract
- app or compare changes require Director B to redesign rather than preserve Feature 4 or Feature 5
- a subordinate agent cannot return a concrete artifact and is drifting into another director's ownership
- root ordering assumptions are broken and Feature 6 is being asked to ship before Features 4 and 5 are current

Operational stop gates for delegated work:
- stop a Feature 4 packet if the proposed fix touches non-Director-B engine architecture
- stop a Feature 5 packet if compare semantics must be redefined rather than preserved
- stop a Feature 6 packet if artifact truth depends on logs or manifests that do not exist on the current SHA
- stop the whole Director B pass if two or more feature packets are blocked by the same upstream contract ambiguity; escalate once with the shared blocker instead of continuing piecemeal

Director B can mark the branch state acceptable only when all of the following are true:
- Feature 4 still has a believable live-entry path for display, window, and overlay capture
- Feature 5 still exports the documented processed output with no silent compare drift
- Feature 6 still reports the truth about gates, signing, packaging, and private-distribution limits
- every accepted claim has a corresponding verification artifact or an explicit recorded gap

## Procedure Risks

- Export semantics can drift if compared view and processed-output view diverge and nobody pins the contract.
- Live smoke can give false confidence if picker filtering or permission states regress quietly.
- Release scripts can become dishonest if they assume green gates that are no longer green on the branch.
- Director B can accidentally absorb compare feature design work if export policy is not kept narrow.
- Historical green evidence can mask current-branch regressions if verification artifacts are not refreshed after app-side changes.
- Cross-director churn can leave evidence stale unless Director B rebinds artifacts to the exact branch state under review.

## Evaluation

Director B is operating correctly when:
- capture entry remains deterministic and user-trustworthy
- export remains render-thread-owned and clearly specified
- release artifacts and manifests continue to describe the real branch state without optimistic claims
- subordinate agents have bounded outputs, not open-ended ownership creep
- private release is blocked immediately when live-entry or export evidence stops being current
