# Feature 7.3 - M2 Engine Parity Checklist

## Objective

Map each mandatory M2 manifest behavior to the concrete shared-engine or app bridge behavior that now satisfies it on macOS.

This is the `m2-engine-agent` handoff artifact consumed by backend and verification.

## Engine Parity Matrix

| Manifest behavior | Required by | Implementation path | Status |
| --- | --- | --- | --- |
| MSL shader payload creation | all presets | `../ShaderGC/SPIRV.*`, `../ShaderGC/ShaderGC.cpp`, `../ShaderGen/ShaderGen.cpp` | supported |
| generated preset registration | all presets | generated `../ShaderGlass/Shaders/RetroArch/...PresetDef.h`, `../ShaderGlass/Shaders/RetroArch.h`, `core/core_test.mm` includes | supported |
| single-pass source sampling | `pal/pal-singlepass` | `../ShaderGlass/ShaderPass.cpp` binds `Source`; `../ShaderGlass/ShaderGlass.cpp` passes captured source into first pass | supported |
| source, original, output size params | all generated passes | `../ShaderGlass/ShaderPass.cpp` fills size params during `Resize(...)` | supported |
| pass-to-pass handoff | `ntsc/ntsc-adaptive-4x`, `film/technicolor` | portable `../ShaderGlass/ShaderGlass.cpp` creates `m_passTextures` and writes `PassOutputN` resources | supported |
| alias resources | `ntsc/ntsc-adaptive-4x` | generated shader samplers bind `PrePass0` and `NPass1`; runtime output is verified by `core/core_test.mm` | supported for manifest |
| static texture upload | `film/technicolor` | `../ShaderGlass/Texture.cpp` decodes via `sg_image` and uploads through `IRenderBackend::CreateTexture(initialData)` | supported |
| named static texture binding | `film/technicolor` | `../ShaderGlass/Preset.cpp` stores texture defs by preset `name`; `ShaderPass` resolves non-Source samplers from resources | supported |
| `OriginalHistory1` rotation | `motionblur/mix_frames` | portable `../ShaderGlass/ShaderGlass.cpp` owns `m_historyTextures`, recomputes history needs after reset, and rotates `OriginalHistoryN` after rendering | supported |
| frame-to-frame dependency | `motionblur/mix_frames` | `core/core_test.mm` white/black sequence proves `OriginalHistory1` contributes to output | supported |
| readback for verification/export | core/app tests | `IRenderBackend::ReadbackTexture`, `ShaderGlass::GrabOutput`, `EngineBridge` readback paths | supported |
| final drawable versus offscreen target ownership | app/live tests | `ShaderGlass::Process(... outputTarget)` supports offscreen target and borrowed frame targets; app selftest and live smoke pass | supported |

## File-Touch Ledger

| Behavior | Files |
| --- | --- |
| ShaderGC mac portability and MSL payloads | `../ShaderGC/SPIRV.h`, `../ShaderGC/SPIRV.cpp`, `../ShaderGC/ShaderGC.h`, `../ShaderGC/ShaderGC.cpp`, `../ShaderGC/SourceDefs.h`, `../ShaderGC/pch.h` |
| ShaderGen mac compile/generation path | `../ShaderGen/ShaderGen.h`, `../ShaderGen/ShaderGen.cpp`, `core/check_m2_shadergen_*.sh` |
| portable `OriginalHistoryN` handling | `../ShaderGlass/ShaderGlass.h`, `../ShaderGlass/ShaderGlass.cpp`, `core/core_test.mm` |
| mac bridge/live path through shared engine | `app/EngineBridge.*`, `app/LivePipeline.*`, `app/SGAppDelegate.*`, `app/main.mm` |
| generated manifest headers | `../ShaderGlass/Shaders/RetroArch/...` and `slang-shaders/...` pinned inputs |

## Deferred Behaviors

| Behavior | Reason |
| --- | --- |
| `OriginalHistory2` through `OriginalHistory7` | not required by mandatory manifest; implementation path generalizes but only `OriginalHistory1` is verified |
| preset-driven `PassFeedbackN` | deferred out of manifest; synthetic feedback remains covered in `core/core_test.mm` |
| broad corpus alias graphs | out of scope for first M2 adoption slice |
| mipmap generation and mip-select behavior | out of scope unless a future manifest requires it |

## Evidence

- core evidence: `.logs/build-core-m2-manifest-host.log`
- app selftest evidence: `.logs/build-app-selftest-current-after-m2.log`
- live display smoke: `.logs/live-smoke-display-after-m2.log`
- live window smoke: `.logs/live-smoke-window-after-m2.log`
- live overlay smoke: `.logs/live-smoke-overlay-after-m2.log`

## Handoff

Backend and verification may assume the mandatory manifest behavior is implemented without manual generated-output patching after ShaderGen runs.
