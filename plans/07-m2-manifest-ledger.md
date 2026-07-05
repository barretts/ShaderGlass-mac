# Feature 7.1 - M2 Manifest Ledger

## Objective

Pin the first bounded upstream-shaped preset set for macOS M2 inheritance so later codegen, engine, backend, and verification work all target the same small surface.

This artifact is the Director C Phase 7.1 deliverable referenced by `plans/07-shader-inheritance-m2.md`.

## Intake Packet

This ledger is the intake packet for any agent deciding what Feature 7 must support.

- owner:
  - `m2-preset-agent`
- consumed by:
  - `m2-codegen-agent`
  - `m2-engine-agent`
  - `m2-backend-agent`
  - `m2-verification-agent`
- packet purpose:
  - define the only mandatory preset surface for the first M2 implementation pass
- immutable rule:
  - do not add presets, semantics, or exclusions elsewhere first; update this ledger if scope changes
- release output:
  - a bounded manifest another agent can execute without re-inspecting the broader upstream corpus

## Pinned Source Corpus

- upstream repo: `libretro/slang-shaders`
- pinned commit: `a4f3aeec04fcb2624ec6df5dd17e38f9b575eab9`
- evidence source: the generated preset headers under `../ShaderGlass/Shaders/RetroArch/...` embed that exact commit in their source URL comments

## Selected Preset Set

### 1. Mandatory - Stock Single-Pass

- preset: `pal/pal-singlepass`
- preset header: `../ShaderGlass/Shaders/RetroArch/pal/PalPalSinglepassPresetDef.h`
- class: `RetroArch::PalPalSinglepassPresetDef`
- role in manifest:
  - minimal single-pass source-sampled baseline
  - confirms MSL generation, `PresetDef` instantiation, and end-to-end render with no alias, history, or static texture pressure
- required semantics:
  - one `Source` sampler
  - `scale_type = source`
  - standard BGRA8 output path
- downstream behaviors forced:
  - baseline shader payload generation
  - baseline `SourceSize` / `OriginalSize` / `OutputSize` push handling
  - no special intermediate resources

### 2. Mandatory - Multi-Pass Alias And Float Target

- preset: `ntsc/ntsc-adaptive-4x`
- preset header: `../ShaderGlass/Shaders/RetroArch/ntsc/NtscNtscAdaptive4xPresetDef.h`
- class: `RetroArch::NtscNtscAdaptive4xPresetDef`
- role in manifest:
  - first real multi-pass alias and scale stress case
  - deliberately forces the smallest alias-heavy preset found during inspection that still fits M2 scope
- required semantics:
  - aliases: `PrePass0`, `NPass1`
  - four passes
  - per-pass scale rules using `scale_type_x`, `scale_type_y`, `scale_x`, `scale_y`
  - `float_framebuffer = true` on middle passes
  - `wrap_mode = clamp_to_border`
- downstream behaviors forced:
  - alias resource registration and lookup
  - pass-to-pass handoff with mixed scale rules
  - RGBA16 float intermediate allocation
  - multi-pass stability checks
- current classification:
  - `mandatory`
  - reason: this is the smallest inspected preset that actually forces alias semantics instead of only plain multi-pass sequencing

### 3. Mandatory - Static Texture Binding

- preset: `film/technicolor`
- preset header: `../ShaderGlass/Shaders/RetroArch/film/FilmTechnicolorPresetDef.h`
- class: `RetroArch::FilmTechnicolorPresetDef`
- role in manifest:
  - first static-texture preset
  - proves named texture-def upload, static sampler binding, and texture lifetime across preset build/use
- required semantics:
  - two passes
  - static textures:
    - `SamplerLUT` from `ReshadeShadersLUTCmyk16TextureDef`
    - `noise1` from `FilmResourcesFilm_noise1TextureDef`
  - linear sampler override on both static textures
  - second pass scales to `viewport`
- downstream behaviors forced:
  - preset texture decode and upload
  - named texture binding
  - texture/sampler reflection agreement in generated MSL

### 4. Mandatory - History-Driven Frame Dependency

- preset: `motionblur/mix_frames`
- preset header: `../ShaderGlass/Shaders/RetroArch/motionblur/MotionblurMix_framesPresetDef.h`
- shader evidence: `../ShaderGlass/Shaders/RetroArch/motionblur/shaders/MotionblurShadersMix_framesShaderDef.h`
- class: `RetroArch::MotionblurMix_framesPresetDef`
- role in manifest:
  - smallest inspected preset that directly forces original-frame history without expanding immediately to many history planes
- required semantics:
  - one pass
  - `OriginalHistory1` sampler
  - `scale_type = source`
- downstream behaviors forced:
  - original-history rotation and lookup
  - frame `N+1` dependence on prior input frames
  - offscreen history verification

## Exclusion Ledger

### Support Now

These behaviors are required by the selected manifest and should be treated as in-scope for M2:

- single-pass source sampling
- multi-pass sequencing
- alias resources
- per-pass scale rules
- static texture upload and named sampler binding
- `OriginalHistory1`
- float intermediates via `float_framebuffer = true`
- border wrap via `wrap_mode = clamp_to_border`

### Defer With Replacement

These behaviors were encountered during corpus inspection but are not required by the first mandatory set:

- `PassFeedbackN`
  - deferred out of preset manifest
  - replacement coverage exists today in `core/core_test.mm` via the synthetic `feedbackMSL()` chain
- `OriginalHistory2` through `OriginalHistory7`
  - deferred until `OriginalHistory1` is proven end to end
- larger alias graphs and many-pass CRT/bezel presets
  - deferred because they expand verification cost before the generator path is stable
- `feedback_pass` preset overrides
  - deferred because the current manifest avoids presets that require explicit feedback-pass override policy

### Blocker Or Out Of Scope

These are not approved for the first M2 manifest:

- compute-only presets
- storage-image workflows
- presets that require full mipmap generation or mip-select behavior not already exposed through the current backend contract
- broad corpus support beyond the four pinned presets above

## Implementation Packet For Subordinate Agents

### For `m2-codegen-agent`

- intake assumptions:
  - only the four mandatory presets need real output in the first pass
  - `PassFeedbackN` is not required for this manifest
  - `OriginalHistory1` is required and cannot be silently downgraded
- concrete tasks:
  - generate each mandatory preset on mac
  - emit a durable binding map for every generated pass
  - record any preset that fails generation with the exact unsupported semantic
- stop gates:
  - stop if a mandatory preset requires a semantic not recorded in this ledger
  - stop if a preset only works after manual output editing

### For `m2-engine-agent`

- intake assumptions:
  - implement only the semantics forced by the mandatory preset set
  - deferred semantics stay deferred unless the ledger changes
- concrete tasks:
  - map every "downstream behavior forced" bullet above to one engine behavior check
  - record where alias, history, and static texture behavior are closed
- stop gates:
  - stop if a required engine behavior expands into out-of-scope corpus support

### For `m2-backend-agent`

- intake assumptions:
  - backend proof is limited to manifest-required formats and sampler modes
- concrete tasks:
  - prove RGBA16 float intermediates, border wrap, static texture upload, and history-related copies as required by the mandatory set
- stop gates:
  - stop if support for a mandatory manifest feature is unknown after direct inspection

### For `m2-verification-agent`

- intake assumptions:
  - every mandatory preset in this ledger must end with an executable verification result
- concrete tasks:
  - create at least one verification line item per mandatory preset
  - add focused history and static-texture checks that map back to the relevant manifest items
- stop gates:
  - stop if any mandatory preset lacks a direct proof path from generation to render

## File-Touch Expectations For Later Phases

Expected later M2 implementation surfaces, driven by this ledger:

- codegen:
  - `../ShaderGC/SPIRV.h`
  - `../ShaderGC/SPIRV.cpp`
  - `../ShaderGen/*`
- shared engine:
  - `../ShaderGlass/ShaderPass.cpp`
  - `../ShaderGlass/ShaderGlass.cpp`
  - `../ShaderGlass/Shader.cpp`
- mac verification and bridge:
  - `core/core_test.mm`
  - `core/SGCoreEngine.*`
  - `backend/backend_test.mm`
  - `app/EngineBridge.*`

## Verification Hook

Use `core/check_m2_manifest.sh` to verify that the selected preset files still exist and still advertise the pinned upstream commit and the expected key semantics this ledger depends on.

Expected durable artifacts from this hook:
- a pass or fail log for the pinned preset paths
- confirmation that the source corpus commit still matches
- confirmation that required key semantics for each mandatory preset are unchanged
