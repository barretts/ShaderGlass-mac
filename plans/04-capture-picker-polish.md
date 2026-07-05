# Feature 4 - Capture Picker Polish

## Objective

Preserve the implemented capture-picker baseline under ongoing app and compare churn: grouped displays and windows, explicit permission states, durable last-target restore, and safe stale-target recovery without surprising the user.

This is now a regression-preservation feature, not a greenfield picker build. Any change must keep the current `SGAppDelegate` ownership model intact and avoid widening scope into engine redesign.

Root placement:
- owner: `director-b-capture-and-shipping`
- root sequence position: Feature 4 runs before Feature 5 and Feature 6
- private-release claims are blocked if this feature's evidence is stale after relevant branch changes

## Procedure

### Stage 0 - Preserved Baseline Contract

The baseline to preserve is already implemented:
- grouped display/window capture choices exist
- last-target restore exists
- stale-target recovery exists
- explicit permission and relaunch-needed states exist
- overlay exclusion is already wired for display capture

The feature contract remains:
- `SGAppDelegate` owns picker presentation and start/stop affordances
- `SCKCapture` owns asynchronous enumeration and start failures
- Screen Recording state must be shown honestly, including signature-change or relaunch implications
- display overlay must keep excluding both overlay and control windows
- no parallel capture model is introduced to support branch churn

### Stage 1 - File Touchpoints

Primary files:
- `app/SGAppDelegate.h`
- `app/SGAppDelegate.mm`
- `capture/SCKCapture.h`
- `capture/SCKCapture.mm`

Secondary files that can force reevaluation without changing ownership:
- `app/Info.plist`
- `app/build.sh`
- `release/private-build.sh`
- `RUNNING.md`

### Stage 2 - Ownership Boundaries And Agent Roster

Director: `director-b-capture-and-shipping`

Director B owns:
- capture-target state integrity at the app/capture boundary
- picker trustworthiness after top-bar, compare, or status-label changes
- regression evidence for restore, stale-target, and permission flows

Director B does not own:
- compare control design
- preset or parameter UX outside capture-entry consequences
- engine-level capture model redesign

Subordinate agents:
- `capture-regression-agent`: inspect app-side diffs that can break selection state or start availability.
- `permission-state-agent`: verify denied, revoked, and relaunch-required behavior stays explicit.
- `overlay-safety-agent`: verify overlay/control-window exclusion and click-through behavior after UI changes.
- `capture-qa-agent`: produce smoke evidence for display, window, stale-target, and restore paths.

Deliverables from subordinate agents:
- one regression note per touched behavior
- one evidence reference per validated flow
- one blocked-state note when confidence drops and root review is needed

### Stage 2A - Intake Packet For Future Work

Before a future implementation or verification pass, assemble a Feature 4 intake packet with:
- branch SHA
- touched files within Feature 4 surface
- whether the branch changed:
  - picker presentation
  - target persistence
  - stale-target recovery
  - permission messaging
  - overlay/control-window behavior
- last known good evidence references
- machine constraints:
  - Screen Recording already granted
  - permission reset required
  - missing display/window scenario needed for a stale-target repro

Decision from the intake packet:
- `preserve-only`: no owned surface moved; carry evidence forward
- `verify-only`: owned surface moved but no code change is expected
- `bounded-fix`: owned surface moved and current contract truth is broken

### Stage 3 - Implementation Stages

1. preserve current picker contract:
   - keep grouped display/window identity intact
   - keep `Start` enablement tied to real readiness
2. preserve restore and stale-target behavior:
   - keep valid-target restore unchanged
   - keep stale-target recovery bounded to one conservative retry path
3. preserve permission truth:
   - keep denied, revoked, and relaunch-needed states explicit
   - keep signing-sensitive permission notes aligned with actual app identity behavior
4. preserve overlay safety:
   - keep overlay and control windows excluded from display capture
   - keep click-through behavior intact during display capture
5. refresh evidence only when branch touchpoints moved:
   - reuse prior evidence only when no owned surface changed
   - rerun bounded smoke when picker, permission, or window lifecycle code changed

### Stage 3A - Agent Release Packets

`capture-regression-agent`
- files: `app/SGAppDelegate.*`, `capture/SCKCapture.*`
- task: map code changes to user-visible picker state transitions
- must return:
  - start-enablement truth table
  - restore/stale-target impact note
  - explicit "no change" note if behavior is preserved

`permission-state-agent`
- files: `app/SGAppDelegate.*`, `app/Info.plist`, release-signing notes when relevant
- task: verify the exact visible state for denied, revoked, and relaunch-needed flows
- must return:
  - user-visible status mapping
  - any identity/signing caveat that affects trust in the result

`overlay-safety-agent`
- files: `app/SGAppDelegate.*`, `capture/SCKCapture.*`
- task: verify overlay/control-window exclusion still matches display-capture policy
- must return:
  - exclusion result
  - click-through result
  - blocker if validation requires ownership outside Director B

`capture-qa-agent`
- files: none required beyond app binary and notes
- task: rerun the smallest smoke set needed for current branch churn
- must return:
  - evidence list tied to current SHA
  - blocked note for any scenario not reproducible locally

### Stage 4 - Dependency Gates

Incoming changes that require review:
- `SGAppDelegate` edits that touch the top bar, picker presentation, start/stop enablement, rescan behavior, or status text
- `SCKCapture` edits that touch enumeration order, identity, or start failure behavior
- app-signing or release changes that can alter Screen Recording permission truth
- compare/app changes that alter window lifecycle, focus, or control-window behavior

Gate rules:
1. if the branch does not touch Feature 4 surfaces, preserve the current plan and carry forward prior evidence
2. if the branch touches picker, permission, or live-state code, rerun the bounded Feature 4 regression checklist
3. if overlay exclusion confidence drops, stop before accepting any adjacent UI polish
4. if restore or stale-target behavior becomes ambiguous, require explicit user-visible fallback rather than silent reselection changes

Dependencies on other features:
- depends on Feature 2 only for stable app control state, not for redesign input
- must remain healthy before Feature 5 live-export evidence is trusted
- must remain current before Feature 6 shipping review can proceed

### Stage 5 - Deliverables

Required deliverables for this feature on an active branch:
- preserved behavior checklist:
  - displays and windows remain clearly distinguishable
  - Start stays disabled for missing-permission, no-selection, and stale-selection states
  - valid last target still restores
  - stale-target start still triggers one bounded recovery attempt
  - display overlay remains excluded and click-through
- verification artifact set:
  - smoke command references or manual verification notes
  - screenshots or notes for denied-permission and stale-target states
  - explicit note if a check could not be rerun on the current machine

Implementation packet output for future delegated work:
- issue statement:
  - what branch change threatened the preserved picker contract
- bounded change list:
  - exact file edits permitted inside Director B ownership
- verification bundle:
  - which checklist items were rerun
  - which prior artifacts were carried forward
- release implication:
  - whether Feature 6 must remain blocked until new picker evidence exists

### Stage 6 - Verification Artifacts

Primary artifacts:

```sh
capture/build_test.sh
app/build.sh selftest
```

Manual artifacts to refresh when branch changes touch this feature:
- permission denied launch result
- valid-target relaunch restore result
- closed-window stale-target recovery result
- display overlay exclusion result

Suggested smoke commands if the app binary is available:

```sh
app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-display app/build/smoke-display.png
app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-window app/build/smoke-window.png
app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-overlay
```

Artifact expectations:
- one current note or log for permission truth
- one current note or image for stale-target recovery
- one current note for overlay exclusion
- explicit statement when evidence is carried forward unchanged because no owned touchpoint moved

Preferred evidence bundle names for delegated work:
- `feature-4-intake.md`
- `feature-4-regression-checklist.md`
- `feature-4-permission-note.md`
- `feature-4-overlay-note.md`

If these are not created as files, the same packet structure must still be reflected in the returned notes or plan update.

## Stopping Conditions

This feature remains acceptable only when all of the following are still true:
- Displays and windows are clearly grouped.
- Start is disabled for missing-permission, no-selection, and stale-selection states.
- Last-used target restores when it is still valid.
- Stale start failure triggers one rescan and either a conservative recovery or a clear blocked state.
- Display overlay remains click-through and excluded from capture.
- Window capture still starts from the picker without feedback regression.

Stop and replan when any of the following becomes true:
- app-side changes make it unclear whether Start is reflecting real capture readiness
- safe stale-target matching can no longer be preserved without widening into unrelated capture redesign
- overlay exclusion confidence drops after compare or top-bar changes
- permission truth depends on release/signing behavior that has not been revalidated
- a fix would require parallel-capture architecture or engine ownership transfer

Delegation stop gates:
- stop `capture-regression-agent` if the required fix extends into compare workflow design
- stop `permission-state-agent` if the result depends on a signing identity that is not the branch target
- stop `overlay-safety-agent` if window-policy verification cannot be tied to current display-capture behavior
- stop the whole Feature 4 pass if no trustworthy permission or stale-target evidence can be produced for the current SHA

## Procedure Risks

- ScreenCaptureKit results are inherently stale; overconfident auto-reselection can pick the wrong window.
- Permission behavior can appear inconsistent when the code signature changes between builds.
- UI churn near compare/export controls can quietly destabilize picker enablement and status messaging.
- Window titles can be empty or volatile, so persistence keys must not rely on title alone.

## Evaluation

This plan is healthy when:
- the branch still has a trustworthy live-entry path without silent target switching
- adjacent compare/app work has not changed permission, restore, or exclusion truth
- current verification artifacts are fresh enough to support a private release recommendation
- blocked scenarios are recorded explicitly instead of silently downgraded

## Open Risks To Carry Forward

- Search UX may still need a richer custom view if grouped popup sections are not sufficient under large window counts.
- Multi-monitor restore policy may need a follow-on rule when the same app window migrates between displays.
