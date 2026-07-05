# Feature 7.4 - M2 Backend Capability Matrix

## Objective

Record the Metal backend support status for every backend-facing capability required by the mandatory M2 manifest.

This is the `m2-backend-agent` handoff artifact consumed by verification and adoption.

## Capability Matrix

| Capability | Required by | Backend path | Proof | Status |
| --- | --- | --- | --- | --- |
| BGRA8 render target | all presets | `backend/MetalBackend.mm::CreateTexture`, `BeginRenderPass` | `backend/build_test.sh`, `core/build_core.sh`, app selftest | supported |
| shader-read texture upload with initial data | `film/technicolor` static textures | `IRenderBackend::CreateTexture(initialData)` and `Texture.cpp` | `core/build_core.sh` static texture render path | supported |
| shader-read plus render-target intermediates | `ntsc-adaptive-4x`, `film/technicolor` | `TextureDesc.renderTarget=true` -> `MTLTextureUsageRenderTarget` | `core/build_core.sh` multi-pass checks | supported |
| copy semantics | history, readback, retained output | `MetalBackend::CopyTexture` | backend conformance and `motionblur/mix_frames` core test | supported |
| readback | selftest/export/core verification | `MetalBackend::ReadbackTexture` | backend conformance, app selftest, core readbacks | supported |
| sampler nearest/linear | generated preset samplers and static textures | `ShaderPass` sampler creation and `MetalBackend::BindSampler` | `film/technicolor` and `pal-singlepass` core checks | supported |
| border/clamp semantics | `ntsc-adaptive-4x` `wrap_mode=clamp_to_border` | `SamplerDesc::Wrap` mapping in backend | `core/build_core.sh` renders preset successfully | supported for manifest |
| RGBA16 float intermediate | `ntsc-adaptive-4x` `float_framebuffer=true` | `PixFmt::RGBA16_SFLOAT` mapping in `MetalBackend` | `core/build_core.sh` phase-active render path | supported for manifest |
| per-frame offscreen target | core and app selftest | `ShaderGlass::Process(... outputTarget)` with backend render target | `core/build_core.sh`, `app/build.sh selftest` | supported |
| live drawable target | display/window/overlay smoke | `BeginFrame`, borrowed drawable target, `Present` | live smoke logs | supported |

## Deferred Or Out Of Scope

| Capability | Classification |
| --- | --- |
| mipmap generation | deferred out of manifest |
| storage images | out of scope |
| compute-only shader workflows | out of scope |
| broad non-BGRA/packed-format corpus coverage | follow-up corpus expansion |

## Evidence Logs

- backend conformance: `.logs/build-backend-current-after-m2.log`
- capture seam: `.logs/build-capture-current-after-m2.log`
- core manifest coverage: `.logs/build-core-m2-manifest-host.log`
- app selftest: `.logs/build-app-selftest-current-after-m2.log`
- live display smoke: `.logs/live-smoke-display-after-m2.log`
- live window smoke: `.logs/live-smoke-window-after-m2.log`
- live overlay smoke: `.logs/live-smoke-overlay-after-m2.log`

## Handoff

Verification may treat mandatory manifest backend capabilities as supported. Future corpus expansion must add rows here before promoting additional preset requirements.
