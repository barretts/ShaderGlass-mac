# M1 ShaderGlass Playground - Simon Orchestration Plan

## Objective

Turn the verified macOS engine port into a usable, testable app with seven bounded feature tracks:
1. preset deck
2. live control surface
3. before/after compare
4. capture picker polish
5. export moment
6. private release build
7. shader inheritance M2

This document is the milestone execution plan. The root control plane lives in `plans/00-simon-root-orchestration.md`; feature-specific plans carry local implementation detail; this file owns milestone sequencing, promotion rules, and cross-director coupling.

Verified context:
- AppKit UI lives primarily in `app/SGAppDelegate.mm`.
- Rendering flows through `app/LivePipeline.*` and `app/EngineBridge.*`.
- Capture flows through `capture/SCKCapture.*`.
- Current regression surfaces are `core/build_core.sh`, `backend/build_test.sh`, `capture/build_test.sh`, and `app/build.sh selftest`.
- The private GitHub mac repo is `barretts/ShaderGlass-mac`.

Execution constraints:
- Multiple agents may edit the repo concurrently.
- Preserve the single render-thread invariant unless a phase explicitly re-approves a change.
- Do not let M2 inheritance work destabilize M1 usability work before the private release path is viable.

## Director Tree

Root orchestrator: `expert-orchestrator-simon`

Directors:
- `director-a-preset-and-interaction`: owns Features 1-3
- `director-b-capture-and-shipping`: owns Features 4-6
- `director-c-engine-inheritance`: owns Feature 7

Execution agents available to directors:
- `preset-inventory-agent`
- `pipeline-preset-agent`
- `deck-ui-agent`
- `thumbnail-agent`
- `parameter-contract-agent`
- `enginebridge-param-agent`
- `control-surface-ui-agent`
- `param-persistence-agent`
- `compare-interaction-agent`
- `engine-target-seam-agent`
- `composite-shader-agent`
- `frame-lifetime-agent`
- `capture-enumeration-agent`
- `picker-ui-agent`
- `permission-ux-agent`
- `overlay-target-agent`
- `capture-qa-agent`
- `export-threading-agent`
- `backend-snapshot-agent`
- `export-ui-agent`
- `export-qa-agent`
- `release-script-agent`
- `signing-policy-agent`
- `regression-gate-agent`
- `distribution-qa-agent`
- `m2-preset-agent`
- `m2-codegen-agent`
- `m2-engine-agent`
- `m2-backend-agent`
- `m2-verification-agent`

Ownership rules:
- Directors own sequencing, scope control, and cross-agent conflict resolution.
- Agents own a bounded artifact or behavior surface and must stop at their declared boundary.
- Root orchestrator alone can reorder phases, widen scope, or promote a phase from experimental to baseline.

Delegation rule for this milestone:
- root releases directors
- directors release feature agents
- feature agents return artifacts to directors
- directors return phase readiness to root
- no feature agent may promote a phase directly

Current planning round:
- Director A refreshes Features 1-3 into preservation-oriented execution packets
- Director B refreshes Features 4-6 into evidence-oriented execution packets
- Director C refreshes Feature 7 into phase-gated M2 execution packets
- root integration accepts only durable markdown artifacts saved under `plans/`

## Procedure

### Phase 0 - Planning Artifact Gate

Deliverable set:
- `plans/00-init.md`
- `plans/01-router.md`
- `plans/00-simon-root-orchestration.md`
- `plans/director-a-preset-and-interaction.md`
- `plans/director-b-capture-and-shipping.md`
- `plans/director-c-engine-inheritance.md`
- `plans/M1-SHADERGLASS-PLAYGROUND-ORCHESTRATION.md`
- `plans/08-seven-feature-director-agent-register.md`
- `plans/01-preset-deck.md`
- `plans/02-live-control-surface.md`
- `plans/03-before-after-magic.md`
- `plans/04-capture-picker-polish.md`
- `plans/05-export-moment.md`
- `plans/06-private-release-build.md`
- `plans/07-shader-inheritance-m2.md`

Entry criteria:
- The root plan and all feature plans exist in the repo.

Exit gate:
- Every feature plan has objective, file touchpoints, execution stages, implementation agents, dependencies, verification, stop gates, and risks.
- Every feature plan includes an intake packet that states the current truth, owned surfaces, next bounded action, and required artifact before code changes begin.

Current planning-pass objective:
- normalize all seven feature plans so a new implementer can start from markdown alone
- keep implemented features framed as preserved baselines
- keep Feature 7 framed as bounded M2 inheritance, with completed prerequisite proofs separated from pending engine closure

Handoff:
- Root orchestrator releases Feature 1 and Feature 2 work first because later UI and compare work depend on stable preset identity and parameter contracts.
- Root holds Feature 7 at the entry gate until the M1 baseline is stable enough that M2 failures are not masked by unrelated app churn.

Planning-round artifact rule:
- the milestone plan is not complete until each feature can be delegated from markdown alone
- the milestone plan is not complete until root can see all seven features, their directors, first-release agents, artifacts, and stop gates in one saved register
- if a feature still requires chat reconstruction, the feature plan remains incomplete

### Phase 1 - Preset Foundation

Owner: Preset/UI Director

Current state:
- implemented baseline
- active work is preservation, regression coverage, and bounded polish only

Primary files:
- `app/LivePipeline.h`
- `app/LivePipeline.mm`
- `app/SGAppDelegate.mm`
- `app/build.sh`
- `spike/*.metal`

Preservation streams:
1. `preset-inventory-agent` defines stable preset descriptors and metadata.
2. `pipeline-preset-agent` moves `LivePipeline` to descriptor-driven preset selection.
3. `deck-ui-agent` updates the app UI to consume descriptors.
4. `thumbnail-agent` adds nonblank preset-preview coverage if needed by the chosen UI.

Acceptance gate on the current branch:
- All curated presets are descriptor-driven.
- Presets can be switched while static and while capturing.
- Legacy preset selection paths either map cleanly to descriptors or are removed.
- A render-all-presets smoke exists and passes.

Handoff:
- Feature 2 and Feature 3 can only consume preset identifiers and metadata from this phase, not invent their own.

### Phase 2 - Live Parameter Contract

Owner: Preset/UI Director

Current state:
- implemented baseline
- active work is preservation, regression coverage, and bounded ergonomic follow-up only

Primary files:
- `app/EngineBridge.h`
- `app/EngineBridge.mm`
- `app/LivePipeline.h`
- `app/LivePipeline.mm`
- `app/SGAppDelegate.mm`
- `../ShaderGlass/ShaderGlass.h`
- `../ShaderGC/ShaderDef.h`

Preservation streams:
1. `parameter-contract-agent` defines the parameter metadata contract and persistence expectations.
2. `enginebridge-param-agent` implements the render-thread-safe bridge behavior.
3. `control-surface-ui-agent` wires the AppKit controls.
4. `param-persistence-agent` persists and restores values per preset.

Acceptance gate on the current branch:
- Parameter updates are render-thread-safe.
- Live changes become visible within one frame or the next deterministic redraw point.
- Parameters can be reset per control and per preset.
- Parameter values persist per preset without cross-preset leakage.

Handoff:
- Feature 3 compare work may assume stable preset and parameter restoration.
- Feature 5 export may assume current parameter state is observable at export time.

### Phase 3 - Capture Picker Polish

Owner: Capture/Shipping Director

Current state:
- implemented baseline
- active work is preservation, regression coverage, and live-smoke truthfulness only

Primary files:
- `app/SGAppDelegate.mm`
- `capture/SCKCapture.h`
- `capture/SCKCapture.mm`
- `app/Info.plist`
- `RUNNING.md`

Preservation streams:
1. `capture-enumeration-agent` hardens target enumeration and stale-target handling.
2. `picker-ui-agent` improves target selection and retained state behavior.
3. `permission-ux-agent` makes denied, missing, and retry states explicit.
4. `overlay-target-agent` verifies overlay-specific selection behavior.
5. `capture-qa-agent` closes smoke gaps.

Acceptance gate on the current branch:
- Permission denied, empty target list, stale window, display overlay, and window clone flows all have explicit UI states.
- Start/stop enablement is always consistent with the selected target state.
- The last-selected target behavior is deterministic and recoverable.

Handoff:
- Feature 5 export and Feature 6 release smoke depend on this phase being stable because they require reliable live states.

### Phase 4 - Before/After Magic

Owner: Preset/UI Director

Current state:
- implemented baseline
- split compare is already strongly verified
- active work is preservation and explicit next-cut triage only

Primary files:
- `app/LivePipeline.*`
- `app/EngineBridge.*`
- `backend/IRenderBackend.h`
- `backend/MetalBackend.*`
- `spike/passthrough.metal`
- compare shader resource under `spike/`

Preservation streams:
1. `compare-interaction-agent` preserves hold-to-bypass and mode-state behavior.
2. `engine-target-seam-agent` preserves the explicit render-target path needed for compare composition.
3. `composite-shader-agent` preserves split compare correctness and only widens scope by explicit approval.
4. `frame-lifetime-agent` keeps texture lifetime and resize safety covered as the branch changes.

Acceptance gate for the preserved baseline:
- Hold-to-bypass swaps to passthrough without a compile hitch.
- Releasing bypass restores the exact prior preset and parameter state.

Acceptance gate for split compare:
- Split-position pixel checks pass at 0, 50, and 100 percent.
- Compare mode survives resize and capture restart without stale resources.
- App selftest covers split compare as a normal branch gate.

Handoff:
- Feature 5 export may export the compared view only if the director explicitly approves that scope. Default export target remains the processed frame.

### Phase 4.1 - Current Promotion State

Promotion state by feature:

| Feature | Director | Branch truth | Promotion status |
| --- | --- | --- | --- |
| 1 Preset Deck | Director A | implemented baseline | preserve and regression-check |
| 2 Live Control Surface | Director A | implemented baseline | preserve and regression-check |
| 3 Before/After Magic | Director A | implemented baseline, split compare verified | preserve and triage next cuts |
| 4 Capture Picker Polish | Director B | implemented baseline | preserve and refresh smoke evidence |
| 5 Export Moment | Director B | implemented baseline | preserve contract and refresh evidence |
| 6 Private Release Build | Director B | implemented baseline | keep truthful shipping gate |
| 7 Shader Inheritance M2 | Director C | active bounded M2 work | blocked on generator-to-runtime closure |

### Phase 5 - Export Moment

Owner: Export/Release Director

Current state:
- implemented baseline
- active work is preservation of export semantics against compare and app churn

Primary files:
- `app/LivePipeline.*`
- `app/EngineBridge.*`
- `backend/MetalBackend.*`
- `backend/sg_image.*`
- `app/SGAppDelegate.mm`
- `app/main.mm`

Preservation streams:
1. `export-threading-agent` makes the export path safe under live capture and resize.
2. `backend-snapshot-agent` verifies readback correctness and image dimensions.
3. `export-ui-agent` adds the user-facing command path and disabled states.
4. `export-qa-agent` closes deadlock and nonblank-image coverage.

Acceptance gate on the current branch:
- Static export and live export both produce nonblank correctly-sized PNGs.
- Resize, stop, or shutdown during export cannot deadlock.
- Export errors are surfaced honestly in the UI.

Handoff:
- Feature 6 private release must package an app that has already passed export smoke.

### Phase 6 - Private Release Build

Owner: Export/Release Director

Current state:
- implemented baseline
- active work is preservation of truthful branch gates, signing policy, and artifact provenance

Primary files:
- `app/build.sh`
- `app/make-signing-cert.sh`
- `release/private-build.sh`
- `RUNNING.md`

Preservation streams:
1. `signing-policy-agent` defines strict signing and dirty-tree policy.
2. `release-script-agent` implements the packaging pipeline.
3. `regression-gate-agent` wires regression runs into the release script.
4. `distribution-qa-agent` verifies manifest, checksums, codesign, and `spctl` reporting.

Acceptance gate on the current branch:
- The release script refuses dirty worktrees.
- Regression gates run before packaging.
- Release signing cannot silently fall back to ad-hoc.
- The output includes a zip, manifest, checksums, and honest signing assessment.

Handoff:
- Root orchestrator can declare M1 shippable only after this gate and the live smoke gate are both green.

### Phase 7 - Shader Inheritance M2

Owner: Engine Inheritance Director

Primary files:
- `core/SGCoreEngine.*`
- `core/core_test.mm`
- `app/EngineBridge.*`
- `app/LivePipeline.*`
- `backend/IRenderBackend.h`
- `backend/MetalBackend.*`
- `../ShaderGlass/ShaderGlass.cpp`
- `../ShaderGlass/ShaderPass.cpp`
- `../ShaderGC/SPIRV.cpp`
- `../ShaderGen/*`

Entry criteria:
- Phases 1-6 are stable enough that engine results are not confounded by unrelated app churn.
- The M2 manifest-first plan in `plans/07-shader-inheritance-m2.md` is accepted.

Exit gate:
- A small manifest of upstream-shaped presets compiles to MSL, instantiates as real `PresetDef`s, renders on Metal, and proves single-pass, multi-pass, static texture, alias, feedback, and history behavior.

Handoff:
- After M1 private release is viable, root orchestrator may increase parallelism on M2.

Current M2 planning truth:
- manifest selection is already pinned in `plans/07-m2-manifest-ledger.md`
- codegen prerequisite proof already exists in `plans/07-m2-codegen-prereqs.md`
- the remaining work is generator plumbing, engine semantics closure, backend capability proof, and end-to-end verification

### Phase 8 - Final Promotion Gate

Owner: Root orchestrator

Work:
- Re-run the full regression set on the intended release branch state.
- Run live smoke on a TCC-granted Mac.
- Confirm release artifacts exist and M2 has not regressed M1 if both are present on the same branch.
- Publish a concise release and follow-on ledger.

Exit gate:
- M1 is usable from clean clone to signed private release.
- Any M2 work merged into the same branch is proven non-regressive or held behind an explicit switch.

## Stopping Conditions

The M1 milestone is complete when:
- A clean clone builds the app.
- The app launches with the custom icon.
- A user can pick a target, start capture, switch presets, tune parameters, compare before/after, export a PNG, and quit cleanly.
- All headless tests pass.
- Display, window, and overlay smoke paths pass on a Screen Recording-granted machine.
- A private release zip can be generated with manifest and checksums.

Stop and replan when:
- Any feature requires breaking the single render-thread invariant.
- Export requires main-thread backend access during capture.
- Release signing silently falls back to ad-hoc.
- M2 requires hand-porting generated presets after codegen instead of improving the shared generator or engine.
- Concurrent agent edits create ownership collisions that cannot be resolved by narrowing file boundaries.

## Procedure Risks

- UI scope creep can bury the engine milestone. M1 should stay compact and operator-focused.
- Capture permission failures can make the app appear broken even when rendering is correct.
- Parameter plumbing can corrupt push-buffer layout if metadata and shader structs drift.
- Compare and export depend on careful texture lifetime management because capture frames are borrowed and drawable targets are transient.
- Release automation can look green while shipping an ad-hoc-signed app unless signing checks are strict.
- M2 can become unbounded if it starts from the full RetroArch corpus instead of a pinned manifest.
- Concurrent agent work raises merge risk; each phase must keep file ownership tight and re-read before patching shared files.

## Evaluation

Regression order after implementation phases unless a phase only changes docs:

```sh
core/build_core.sh
backend/build_test.sh
capture/build_test.sh
app/build.sh selftest
```

Required live verification on a TCC-granted Mac:

```sh
app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-display app/build/smoke-display.png
app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-window app/build/smoke-window.png
app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-overlay
```

Feature-specific acceptance:
- Preset Deck: every descriptor compiles and renders a nonblank thumbnail or preview frame.
- Live Control Surface: slider changes produce measurable pixel deltas and reset to defaults.
- Capture Picker Polish: no-permission, no-target, stale-target, display overlay, and window clone states are covered.
- Before/After Magic: bypass restores exact prior state; split compare boundary matches requested position.
- Export Moment: static and live PNGs are nonblank, correctly sized, and safe across resize and stop.
- Private Release Build: the release artifact has manifest, checksums, codesign verification, and honest `spctl` status.
- Shader Inheritance M2: generated upstream-shaped presets pass offscreen goldens and one live smoke.
