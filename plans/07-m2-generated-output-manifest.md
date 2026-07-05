# Feature 7.2 - M2 Generated Output Manifest

## Objective

Record the generated mac-consumable output for the first bounded upstream inheritance manifest.

This is the `m2-codegen-agent` handoff artifact consumed by the engine, backend, and verification packets.

## Source And Generator Revision

- upstream source repo: `libretro/slang-shaders`
- upstream source commit: `a4f3aeec04fcb2624ec6df5dd17e38f9b575eab9`
- shared generator commit: `c8033481`
- mac integration commit: `9088afc`
- manifest ledger: `plans/07-m2-manifest-ledger.md`
- prerequisite artifact: `plans/07-m2-codegen-prereqs.md`

## Generated Presets

| Preset | Generated preset header | Runtime status |
| --- | --- | --- |
| `pal/pal-singlepass` | `../ShaderGlass/Shaders/RetroArch/pal/PalPalSinglepassPresetDef.h` | generated and rendered in `core/build_core.sh` |
| `ntsc/ntsc-adaptive-4x` | `../ShaderGlass/Shaders/RetroArch/ntsc/NtscNtscAdaptive4xPresetDef.h` | generated and rendered in `core/build_core.sh` |
| `film/technicolor` | `../ShaderGlass/Shaders/RetroArch/film/FilmTechnicolorPresetDef.h` | generated and rendered in `core/build_core.sh` |
| `motionblur/mix_frames` | `../ShaderGlass/Shaders/RetroArch/motionblur/MotionblurMix_framesPresetDef.h` | generated and rendered in `core/build_core.sh` |

## Generated Passes And Binding Map

| Preset | Pass | Shader header | Source bindings |
| --- | --- | --- | --- |
| `pal/pal-singlepass` | `pal-singlepass` | `../ShaderGlass/Shaders/RetroArch/pal/shaders/PalShadersPalSinglepassShaderDef.h` | `Source -> 2` |
| `ntsc/ntsc-adaptive-4x` | `ntsc-pass1` | `../ShaderGlass/Shaders/RetroArch/crt/shaders/guest/advanced/ntsc/CrtShadersGuestAdvancedNtscNtscPass1ShaderDef.h` | `Source -> 2` |
| `ntsc/ntsc-adaptive-4x` | `ntsc-pass2` | `../ShaderGlass/Shaders/RetroArch/crt/shaders/guest/advanced/ntsc/CrtShadersGuestAdvancedNtscNtscPass2ShaderDef.h` | `Source -> 2`, `PrePass0 -> 3` |
| `ntsc/ntsc-adaptive-4x` | `ntsc-pass3` | `../ShaderGlass/Shaders/RetroArch/crt/shaders/guest/advanced/ntsc/CrtShadersGuestAdvancedNtscNtscPass3ShaderDef.h` | `Source -> 2`, `NPass1 -> 3`, `PrePass0 -> 4` |
| `film/technicolor` | `LUT` | `../ShaderGlass/Shaders/RetroArch/reshade/shaders/LUT/ReshadeShadersLUTLUTShaderDef.h` | `Source -> 2`, `SamplerLUT -> 3` |
| `film/technicolor` | `film_noise` | `../ShaderGlass/Shaders/RetroArch/film/shaders/FilmShadersFilm_noiseShaderDef.h` | `Source -> 2`, `noise1 -> 3` |
| `motionblur/mix_frames` | `mix_frames` | `../ShaderGlass/Shaders/RetroArch/motionblur/shaders/MotionblurShadersMix_framesShaderDef.h` | `Source -> 2`, `OriginalHistory1 -> 3` |

## Static Textures

| Preset | Texture name | Generated texture header | Source input |
| --- | --- | --- | --- |
| `film/technicolor` | `SamplerLUT` | `../ShaderGlass/Shaders/RetroArch/reshade/shaders/LUT/ReshadeShadersLUTCmyk16TextureDef.h` | `slang-shaders/reshade/shaders/LUT/cmyk-16.png` |
| `film/technicolor` | `noise1` | `../ShaderGlass/Shaders/RetroArch/film/resources/FilmResourcesFilm_noise1TextureDef.h` | `slang-shaders/film/resources/film_noise1.png` |

## Generation Evidence

| Gate | Evidence log | Result |
| --- | --- | --- |
| manifest integrity | `.logs/build-core-m2-manifest-host.log` and `core/.logs/build-core-manifest.log` | passed |
| fixture generation | `.logs/check-m2-shadergen-fixture.log` | passed |
| `pal/pal-singlepass` | `.logs/check-m2-shadergen-pal.log` | passed |
| `ntsc/ntsc-adaptive-4x` | `.logs/check-m2-shadergen-ntsc.log` | passed |
| `film/technicolor` | `.logs/check-m2-shadergen-film.log` | passed |
| `motionblur/mix_frames` | `.logs/check-m2-shadergen-motionblur.log` | passed |

## Failure Classification

- generation failures: none for the mandatory manifest set
- unsupported manifest keys: none beyond the exclusions already recorded in `plans/07-m2-manifest-ledger.md`
- deferred semantics:
  - broad corpus generation
  - mipmap behavior beyond current backend contract
  - `OriginalHistory2` through `OriginalHistory7`
  - preset-driven `PassFeedbackN`

## Handoff

Engine and backend agents may assume the mandatory preset outputs are generated, checked in, and runtime-consumed by the current core test path.

Explicit binding-map extraction from generated metadata remains useful follow-up automation, but this manifest records the currently verified source bindings used by runtime tests.
