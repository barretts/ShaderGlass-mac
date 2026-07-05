# Feature 7 - Shader Inheritance M2

## Objective

After M1 is stable, land a bounded M2 that proves real upstream inheritance on macOS: a small manifest of upstream-shaped RetroArch presets must compile to Metal-ready payloads, instantiate as real `PresetDef`s, and render through the shared ShaderGlass engine on `MetalBackend`.

This phase is intentionally narrow. It does not attempt full corpus support, full UI parity, or a Windows-preserving dual-runtime cleanup. The output is a verified inheritance path that can be expanded later without rewriting the mac app again.

Verified starting point:
- The mac app already renders through the shared engine via `app/EngineBridge.*`.
- `core/SGCoreEngine` and current bridge code can drive curated MSL presets.
- The mac engine path is functional but still simpler than the Windows resource loop.
- Existing generated upstream assets in the parent tree are DXBC-oriented and not directly usable on Metal.

## Intake Packet

This file is the durable implementation packet for Feature 7. A future implementation pass should start here, not from chat history.

- feature owner:
  - Director C under root orchestration
- working objective:
  - prove one bounded M2 inheritance path from upstream-shaped preset selection through generator output, shared-engine execution, backend capability, and verification evidence
- immutable current truth:
  - Phase 7.1 manifest work exists and remains authoritative for scope
  - Phase 7.2 prerequisite proof exists
  - generator integration is now proven for the mandatory manifest presets through executable gates and host-backed core evidence
  - the portable shared-engine path now rotates `OriginalHistoryN` on macOS for manifest-selected history presets
  - the current mac build stack is green across core, backend, capture, and app selftest
  - live display, window, and overlay smoke have been run against the generated shared-engine path
  - adoption is explicit for the pinned manifest; broader corpus support remains follow-on scope
- non-goals for this packet:
  - broad preset corpus support
  - UI parity work
  - release policy decisions outside the M2 adoption gate
- required consumed artifacts:
  - `plans/07-m2-manifest-ledger.md`
  - `plans/07-m2-codegen-prereqs.md`
  - `plans/07-m2-generated-output-manifest.md`
  - `plans/07-m2-engine-parity-checklist.md`
  - `plans/07-m2-backend-capability-matrix.md`
  - `plans/07-m2-verification-bundle.md`
  - `plans/07-m2-adoption-decision.md`
  - latest `.logs/check-m2-*.log` evidence named in those support artifacts

## Agent Tree

Director: `director-c-engine-inheritance`

Execution agents:
- `m2-preset-agent`: select the bounded preset corpus, pin source inputs, record unsupported keys, and maintain the manifest.
- `m2-codegen-agent`: add MSL payload generation, dual payload storage, and the mac ShaderGen build path.
- `m2-engine-agent`: close shared-engine behavior gaps needed by the chosen manifest.
- `m2-backend-agent`: verify Metal backend support for required formats, copies, static textures, and sampler behavior.
- `m2-verification-agent`: own fixtures, goldens, manifests, smoke scripts, and the final evidence package.

Ownership boundaries:
- `m2-preset-agent` owns what M2 must support.
- `m2-codegen-agent` owns how upstream shaders become mac-consumable artifacts.
- `m2-engine-agent` owns engine semantics required to render them correctly.
- `m2-backend-agent` owns backend capability proof and backend-only fixes.
- `m2-verification-agent` owns pass/fail evidence and can block promotion between phases.

Current phase ledger:
- Phase 7.1 manifest selection: complete as a planning artifact
- Phase 7.2 prerequisite proof: complete as a planning artifact
- Phase 7.2 generator integration: complete for the mandatory manifest set
- Phase 7.3 engine semantics parity: complete for the mandatory manifest set
- Phase 7.4 backend capability closure: complete for the mandatory manifest set
- Phase 7.5 verification and promotion: complete for the mandatory manifest set
- Phase 7.6 adoption gate: complete; pinned manifest adopted, broader corpus deferred to follow-on packets

Current verified runtime note:
- `pal-singlepass` remains the stable generated-preset proof for cold-run repeatability
- `ntsc-adaptive-4x` is phase-sensitive by design because its passes consume `FrameCount`; the correct runtime proof is non-identity render plus frame-to-frame phase activity, not byte-identical cold-run stability

## Implementation Stages

Use these stages to keep delegated work bounded.

1. Intake and freeze scope
   - confirm the manifest ledger still matches the intended preset set
   - confirm all previously cited proof gates still pass or are explicitly stale
   - produce a short release note naming which phase packet is being executed
2. Materialize generator output
   - turn mandatory manifest presets into reproducible mac-consumable generated output
   - capture binding metadata and pass ordering as durable artifacts
3. Close engine semantics
   - implement only the shared-engine behavior forced by the generated mandatory presets
   - record exact file-touch ownership for every new behavior
4. Close backend capability
   - prove formats, sampler behavior, copies, static textures, and any float targets the manifest requires
5. Freeze verification evidence
   - leave behind logs, manifests, matrices, and goldens sufficient for promotion review

Current verified evidence on this branch:
- host-backed `core/build_core.sh` now passes with:
  - passthrough byte-identical
  - generated fixture preset renders
  - `pal-singlepass` stable across cold runs
  - `film/technicolor` generated from pinned upstream inputs and stable once time-varying overrides are neutralized for test isolation
  - `ntsc-adaptive-4x` phase-active across sequential frames
  - `motionblur/mix_frames` generated from pinned upstream inputs and proven to consume `OriginalHistory1`
  - multi-pass stable
  - feedback accumulates
- latest evidence log:
  - `.logs/build-core-m2-manifest-host.log`

Current mac gate evidence:
- `core/build_core.sh`
  - latest host log: `.logs/build-core-m2-manifest-host.log`
- `backend/build_test.sh`
  - latest host log: `.logs/build-backend-current-after-m2.log`
- `capture/build_test.sh`
  - latest host log: `.logs/build-capture-current-after-m2.log`
- `app/build.sh selftest`
  - latest host log: `.logs/build-app-selftest-current-after-m2.log`

Additional verified generator evidence:
- `core/check_m2_shadergen_film_technicolor.sh`
  - latest host log: `.logs/recheck-film-gate-host.log`
- `core/check_m2_shadergen_motionblur_mix_frames.sh`
  - latest host log: `.logs/recheck-motionblur-gate-host.log`

Concrete implementation note:
- `../ShaderGen/ShaderGen.cpp` now sanitizes nested preset log paths on mac and throws on shader-output open/write failure instead of reporting a false `OK`
- `../ShaderGlass/ShaderGlass.cpp` portable path now recomputes manifest-forced history requirements after resize/reset and rotates `OriginalHistoryN` textures between frames

Current durable M2 artifacts:
- generated output: `plans/07-m2-generated-output-manifest.md`
- engine parity: `plans/07-m2-engine-parity-checklist.md`
- backend capability: `plans/07-m2-backend-capability-matrix.md`
- verification bundle: `plans/07-m2-verification-bundle.md`
- adoption decision: `plans/07-m2-adoption-decision.md`

## Procedure

### Phase 7.0 - Entry Gate

Entry criteria:
- M1 interactive work is stable enough that engine work will not be masked by unrelated UI breakage.
- `core/build_core.sh`, `backend/build_test.sh`, `capture/build_test.sh`, and `app/build.sh selftest` pass on the current branch.
- A Metal-capable unsandboxed machine is available for live smoke.

Deliverables:
- A branch-local M2 checklist embedded in the implementation issue or working notes.
- Clear assignment of the five M2 execution agents above.

Exit gate:
- Everyone agrees the work is bounded to the manifest-first scope below.

Handoff:
- Root orchestrator releases `m2-preset-agent` and `m2-codegen-agent` first.

Release packet:
- consumed artifacts:
  - this Feature 7 packet
  - current M1 green-build evidence
- produced artifacts:
  - named assignee for each M2 execution agent
  - implementation note stating which phase begins first
- stop gate:
  - halt if M1 instability makes M2 correctness unreadable

### Phase 7.1 - Target Manifest And Exclusion Ledger

Owner: `m2-preset-agent`

Work:
- Pick exactly 3-4 representative upstream-shaped presets:
  - one stock single-pass preset
  - one multi-pass preset with scale and alias behavior
  - one preset that requires static textures
  - one feedback or history-driven preset
- Pin the source corpus revision used for generation.
- Record every unsupported key encountered while selecting the manifest.
- Reject presets that would force M2 to absorb compute, storage images, or full mipmap support unless the director explicitly expands scope.

Required artifact:
- A manifest containing:
  - source corpus commit
  - preset paths
  - required textures
  - required pass semantics
  - unsupported-key ledger
  - whether the preset is mandatory, deferred, or rejected
  - owning downstream engine behaviors that each preset will force

Current artifact path:
- `plans/07-m2-manifest-ledger.md`

Exit gate:
- The manifest is small enough that one engineer can reason through every pass and resource dependency.
- Every unsupported feature is explicitly classified as `support-now`, `defer-with-replacement`, or `blocker`.

Handoff:
- `m2-codegen-agent` may only generate shaders for presets that are `mandatory`.
- `m2-engine-agent` may only port semantics required by `mandatory` presets.

Phase release packet:
- intake:
  - consume `plans/07-m2-manifest-ledger.md`
  - validate pinned corpus commit and preset paths
- subordinate work:
  - inspect the selected preset headers and record any changed key semantics
  - update classification only if the source corpus materially changed
- verification artifact:
  - refreshed manifest ledger or explicit no-change note
- stop gate:
  - stop if a mandatory preset now requires out-of-scope compute, storage image, or mipmap behavior

### Phase 7.2 - MSL Payload Generation

Owner: `m2-codegen-agent`

Work:
- Extend `../ShaderGC/SPIRV.cpp` with `GenerateMSL` alongside the current HLSL path.
- Use SPIRV-Cross MSL with explicit macOS options.
- Preserve deterministic `vs_main` and `fs_main` entry point names.
- Preserve or deliberately remap resource binding decorations so `ShaderPass` can bind them reliably.
- Introduce dual payload support so Windows keeps DXBC-oriented payloads while mac consumes MSL text or equivalent Metal-ready artifacts.
- Add a mac ShaderGen build path using `mac/deps` glslang and SPIRV-Cross.
- Generate only the manifest-selected presets first.

Required artifact:
- A generated-output manifest containing:
  - source corpus commit
  - generator revision
  - generated preset list
  - generated pass list
  - unsupported keys per preset
  - binding map per pass
  - generation failures, if any

Current artifact:
- `plans/07-m2-generated-output-manifest.md`

Prerequisite artifact:
- `plans/07-m2-codegen-prereqs.md`
- executable gate: `core/check_m2_codegen_deps.sh`

Already-proven slice:
- shared `../ShaderGC/SPIRV.*` can now emit real MSL from a known SPIR-V fixture
- proof gate: `core/check_m2_generate_msl.sh`
- latest evidence: `.logs/check-m2-generate-msl.log`
- shared `../ShaderGen/ShaderGen.cpp` now compiles on mac with the Apple MSL payload branch present
- proof gate: `core/check_m2_shadergen_compile.sh`
- latest evidence: `.logs/check-m2-shadergen-compile-wrapper.log`
- a real mac `ShaderGen` binary now links and generates a local fixture preset/header pair with MSL-shaped payload bytes
- proof gate: `core/check_m2_shadergen_fixture.sh`
- latest evidence: `.logs/check-m2-shadergen-fixture-wrapper.log`

Current phase status:
- real manifest-selected upstream presets now generate through ShaderGen on mac
- generated `PresetDef`s for `pal-singlepass`, `film/technicolor`, `ntsc-adaptive-4x`, and `motionblur/mix_frames` are runtime-consumed by core coverage
- durable binding-map extraction remains a useful follow-up, but it no longer blocks the mandatory manifest proof

Exit gate:
- Each mandatory preset generates reproducibly on two consecutive runs.
- Output names and pass ordering are stable enough for engine integration.
- Binding metadata is proven indirectly by core rendering and sampler/history assertions; explicit binding-map artifacts remain follow-up evidence.

Stop gate:
- Stop here and record a blocker if SPIRV-Cross cannot emit stable bindings or the generated payload cannot expose the required entry points.

Handoff:
- `m2-engine-agent` starts only after at least one mandatory preset can be materialized into a real `PresetDef`.

Phase release packet:
- intake:
  - consume the manifest ledger and codegen prerequisite artifact
  - confirm the latest proof gates named below still describe the current branch
- subordinate work:
  - keep manifest-selected ShaderGen gates green on mac
  - capture explicit generated binding maps as a follow-up artifact
  - extend verification from core coverage into live smoke
- required artifacts:
  - generated-output manifest
  - per-preset generation log references
  - first runtime-consumable generated preset identifier
- stop gate:
  - stop if generated outputs regress to fixture-only, runtime sampler binding fails, or explicit binding maps contradict runtime behavior

### Phase 7.3 - Engine Semantics Parity For The Manifest

Owner: `m2-engine-agent`

Work:
- Port only the resource-chain behavior required by the manifest:
  - per-pass format
  - source, viewport, and absolute scale handling
  - alias resources
  - `PassOutputN`
  - `PassFeedbackN`
  - alias feedback
  - `OriginalHistoryN` rotation
  - boxed copy for final feedback and readback
  - static preset textures
  - correct final drawable versus offscreen ownership
- Tighten `../ShaderGlass/ShaderPass.cpp` diagnostics for missing resources.
- Make `OriginalHistory0 -> Original` resolution explicit and testable.
- Keep binding by reflection unless the manifest proves it insufficient.

Required artifact:
- A parity checklist that maps each manifest preset requirement to the exact engine behavior that satisfies it.
- A file-touch ledger listing which shared-engine or bridge files changed for each required behavior.

Current artifact:
- `plans/07-m2-engine-parity-checklist.md`

Exit gate:
- All behaviors needed by mandatory presets are implemented or consciously deferred.
- No implementation step depends on “manual patching” generated presets by hand after codegen.

Stop gate:
- Stop and replan if rendering correctness depends on preset-specific hacks instead of portable generator or engine fixes.

Handoff:
- `m2-backend-agent` validates backend assumptions against the now-concrete engine needs.

Phase release packet:
- intake:
  - consume the generated-output manifest and first real generated preset
- subordinate work:
  - map each mandatory manifest behavior to one engine implementation step
  - close only the required semantics, not speculative future parity
  - record diagnostic improvements when missing resources would otherwise be opaque
- required artifacts:
  - parity checklist
  - file-touch ledger
  - note for each deferred behavior explaining why it is not needed for the current manifest
- stop gate:
  - stop if correctness depends on preset-specific patches after generation

### Phase 7.4 - Backend Capability Closure

Owner: `m2-backend-agent`

Work:
- Verify the Metal backend supports all formats used by the manifest.
- Verify copy semantics, readback path, sampler states, and static texture uploads for nontrivial passes.
- Decide whether mipmaps are supported now or whether affected presets are deferred out of the manifest.
- Add backend-only tests for non-BGRA targets and any pass formats introduced by M2.

Required artifact:
- Backend capability matrix listing each manifest feature and the exact Metal support proof.
- Any deferred preset requirement must name the exact backend limitation that forced deferral.

Current artifact:
- `plans/07-m2-backend-capability-matrix.md`

Exit gate:
- Every mandatory preset requirement is marked `supported`, `deferred out of manifest`, or `blocking`.
- No backend assumption remains implicit.

Stop gate:
- Stop and record a blocker if the manifest requires an unsupported format or sampler mode that cannot be emulated safely within M2.

Handoff:
- `m2-verification-agent` can freeze fixtures once backend capability is stable.

Phase release packet:
- intake:
  - consume the engine parity checklist
- subordinate work:
  - turn every manifest requirement into explicit Metal support proof
  - isolate backend-only gaps from engine or generator bugs
- required artifacts:
  - backend capability matrix
  - backend-only test references
  - explicit deferral record for any manifest item removed from scope
- stop gate:
  - stop if any mandatory preset still depends on an unknown or unproven backend behavior

### Phase 7.5 - Verification And Promotion

Owner: `m2-verification-agent`

Work:
- Add ShaderGC MSL fixture tests.
- Add backend tests for any new formats or copy paths.
- Add offscreen golden tests for each manifest preset.
- Add a static texture fixture.
- Add feedback and history fixtures proving frame-to-frame dependency.
- Add one live smoke that exercises a generated preset through the mac app.
- Capture a final evidence bundle with generated-output manifest, test logs, and smoke outputs.

Current artifact:
- `plans/07-m2-verification-bundle.md`

Exit gate:
- Mandatory presets compile, instantiate, and render offscreen through the shared engine.
- Single-pass output matches the expected golden.
- Multi-pass output is stable across runs.
- Static textures sample correctly.
- Alias resources resolve correctly.
- Feedback and history prove frame N+1 depends on prior frames.
- One live generated preset renders through the app on a TCC-granted Mac.

Handoff:
- Root orchestrator may promote M2 from experimental to baseline inheritance work only after this gate passes.

Phase release packet:
- intake:
  - consume generated-output manifest, engine parity checklist, and backend capability matrix
- subordinate work:
  - freeze tests, goldens, and live smoke evidence against the exact mandatory manifest set
  - reject promotion if evidence cannot be reproduced from the checked-in artifacts and named commands
- required artifacts:
  - final evidence bundle
  - per-preset verification summary
  - promotion recommendation or blocker record
- stop gate:
  - stop if any mandatory preset lacks an executable proof path from generation to render

### Phase 7.6 - Adoption Gate

Owner: Director plus root orchestrator

Work:
- Decide whether generated preset support stays opt-in, becomes the default path for the manifest presets, or remains behind a development switch.
- Record open follow-on work: broader corpus support, mipmaps, additional semantics, Windows cleanup, or UI exposure.

Exit gate:
- There is an explicit decision on runtime exposure.
- Remaining scope is captured as follow-on work, not left implicit inside M2.

Phase release packet:
- intake:
  - consume the final evidence bundle
- subordinate work:
  - make the runtime exposure decision explicit
  - separate follow-on work from the first M2 delivery slice
- required artifacts:
  - adoption decision note
  - follow-on ledger

Current artifact:
- `plans/07-m2-adoption-decision.md`

## File Touchpoints By Agent

- `m2-preset-agent`
  - `plans/07-m2-manifest-ledger.md`
- `m2-codegen-agent`
  - `../ShaderGC/SPIRV.*`
  - `../ShaderGen/*`
  - `core/check_m2_generate_msl.*`
- `m2-engine-agent`
  - `../ShaderGlass/Shader.cpp`
  - `../ShaderGlass/ShaderPass.cpp`
  - `../ShaderGlass/ShaderGlass.cpp`
  - `core/SGCoreEngine.*`
  - `app/EngineBridge.*`
- `m2-backend-agent`
  - `backend/IRenderBackend.h`
  - `backend/MetalBackend.*`
  - `backend/backend_test.mm`
- `m2-verification-agent`
  - `core/core_test.mm`
  - `core/build_core.sh`
  - `app/build.sh`
  - `.logs/*`

## Stopping Conditions

Complete M2 when:
- The manifest is pinned and bounded.
- Mandatory presets generate Metal-ready payloads reproducibly.
- At least one generated preset becomes a real `PresetDef` and renders through the shared engine.
- All mandatory presets pass the offscreen verification matrix.
- The live mac app can render at least one generated preset end to end.

Stop early and record a blocker when:
- The source corpus cannot be pinned or reproduced.
- SPIRV-Cross MSL output cannot provide stable bindings or entry points.
- Mandatory presets require unsupported compute, storage image, or mipmap behavior outside the approved scope.
- Correctness requires preset-specific hacks after generation instead of portable engine or generator fixes.

## Procedure Risks

- Generated upstream artifacts are currently DXBC-oriented, so codegen drift is the first major risk.
- The simplified mac engine loop may hide alias, feedback, or history bugs until real presets arrive.
- Static textures, sRGB handling, float targets, or non-BGRA formats may expose backend gaps late.
- Large generated artifacts can slow build and review loops if generation is not manifest-driven.
- Concurrent M1 work can create false negatives; M2 verification must run on a branch state where M1 gates are green.

## Evaluation

Verification order:
1. Generator fixtures for MSL emission and deterministic output
2. Backend capability tests for required formats and copies
3. Offscreen core tests for each manifest preset
4. App-level selftest
5. One live generated-preset smoke on a TCC-granted Mac

Required runs:

```sh
core/build_core.sh
backend/build_test.sh
capture/build_test.sh
app/build.sh selftest
```

Required evidence:
- generated-output manifest for the pinned preset set
- backend capability matrix
- per-preset offscreen golden results
- feedback/history fixture outputs
- live smoke output for one generated preset
- file-touch ledger linking each M2 behavior to the code path that implements it

Verification artifact bundle should be reviewable as a packet with:
- the exact manifest revision consumed
- the exact proof commands run
- the log paths produced
- the generated preset identifiers under test
- the final go or no-go recommendation
