# Feature 7.2 - M2 Codegen Prerequisites

## Objective

Record the executable prerequisite proof for macOS MSL generation before shared `ShaderGC` surfaces are edited.

This is a Director C support artifact for Phase 7.2. It does not replace the later `GenerateMSL(...)` changes in `../ShaderGC/SPIRV.*`; it proves the writable mac workspace already contains the MSL compiler dependency path those edits will need.

## Intake Packet

This artifact is the release packet for any agent starting Phase 7.2 codegen work.

- owner:
  - `m2-codegen-agent`
- packet purpose:
  - separate "dependency path is real" from "generator integration is complete"
- immutable current truth:
  - prerequisite proof exists and is executable
  - `GenerateMSL(...)` proof exists
  - ShaderGen compile proof exists
  - ShaderGen fixture proof exists
  - real manifest-selected upstream presets are still not fully wired through the mac generator path
- consumed alongside:
  - `plans/07-m2-manifest-ledger.md`
  - `plans/07-shader-inheritance-m2.md`

## Verified Inputs

- vendored SPIRV-Cross source is present under `deps/SPIRV-Cross/`
- MSL frontend header exists:
  - `deps/SPIRV-Cross/spirv_msl.hpp`
- built MSL static library exists:
  - `deps/SPIRV-Cross/build/libspirv-cross-msl.a`
- proof binary exists:
  - `deps/check_msl`
- proof fixture exists:
  - `deps/SPIRV-Cross/tests-other/msl_resource_binding.spv`

## Executable Gate

Run:

```sh
core/check_m2_codegen_deps.sh
```

Expected result:
- `spirv_cross::CompilerMSL` links
- a real SPIR-V module parses
- MSL options can be installed
- non-empty MSL source emits successfully

Latest evidence log:
- `.logs/check-m2-codegen-deps.log`

Durable output expected from this gate:
- a log proving the local mac workspace can parse SPIR-V and emit non-empty MSL
- confirmation that missing dependencies are not the reason later integration could fail

## Implication For Phase 7.2

This proves the immediate Phase 7.2 blocker is not missing MSL compiler code in the mac repo. The remaining gap is integration:

- `../ShaderGC/SPIRV.h`
- `../ShaderGC/SPIRV.cpp`
- `../ShaderGen/*`

Those shared surfaces still need to:
- include the MSL compiler frontend
- thread MSL output alongside existing HLSL output
- expose stable entry points and binding metadata
- consume the mac vendored SPIRV-Cross path or an equivalent shared include/library path

## Implementation Stages

Future Phase 7.2 execution should proceed in this order:

1. Re-validate prerequisites
   - rerun `core/check_m2_codegen_deps.sh` if the dependency surface changed
   - confirm later proof logs still match the current branch state
2. Materialize shared `GenerateMSL(...)`
   - keep entry points deterministic
   - keep binding metadata observable
3. Materialize mac ShaderGen integration
   - carry MSL payloads through the generator path without breaking Windows payload handling
4. Promote from fixture proof to manifest proof
   - replace the local fixture-only success condition with real manifest-selected preset output
5. Freeze handoff artifacts
   - generated-output manifest
   - per-pass binding notes
   - first runtime-consumable generated preset identifier

## Current Limitation

The writable workspace for this session is `mac/`. Shared generator files under `../ShaderGC` and `../ShaderGen` remain outside the current writable root, so direct integration work must either:
- happen in a session with shared-root write access, or
- be preceded by a repo-structure or permission change

That is an environment constraint, not a missing dependency constraint.

Stop gate:
- halt instead of approximating if the required shared-root write access is not available for the integration step

## Follow-On Gate

After the shared `SPIRV.*` surface grows `GenerateMSL(...)`, run:

```sh
core/check_m2_generate_msl.sh
```

That gate compiles the shared `../ShaderGC/SPIRV.cpp` translation unit on macOS and proves the new entry point emits real MSL from a known SPIR-V fixture.

Latest evidence log:
- `.logs/check-m2-generate-msl.log`

Verified current result:
- `OK: GenerateMSL emitted 708 bytes, metadata=2146, warn=0`

Release implication:
- this proves the shared `ShaderGC` surface can emit real MSL from a known fixture
- it does not yet prove that manifest-selected presets generate correctly through ShaderGen

After the shared `ShaderGen` surface grows the mac payload path, run:

```sh
core/check_m2_shadergen_compile.sh
```

That gate compiles `../ShaderGen/ShaderGen.cpp` on macOS and proves the generator host path now parses with:
- portable source-definition includes
- portable `popen` usage
- the Apple `GenerateMSL(...)` payload branch
- portable timestamp formatting for the host tool

Latest evidence logs:
- `.logs/check-m2-shadergen-compile.log`
- `.logs/check-m2-shadergen-compile-wrapper.log`

Verified current result:
- `OK: ShaderGen.cpp compiled to .../check_m2_shadergen.o`

Release implication:
- this proves the host compile path is viable on mac
- it does not yet prove generated preset artifacts are stable enough for runtime consumption

After the shared `ShaderGen` and `ShaderGC` surfaces are linked far enough to run on mac, run:

```sh
core/check_m2_shadergen_fixture.sh
```

That gate:
- links a real mac `ShaderGen` binary against the local glslang and SPIRV-Cross builds
- runs it on the tracked local fixture preset `slang-shaders/fixture/m2-local.slangp`
- verifies generated `PresetDef` and `ShaderDef` headers land in `../ShaderGlass/Shaders/RetroArch/fixture/`
- verifies the emitted shader payload bytes are MSL-shaped, not DXBC-shaped

Latest evidence logs:
- `.logs/check-m2-shadergen-fixture-build.log`
- `.logs/check-m2-shadergen-fixture.log`
- `.logs/check-m2-shadergen-fixture-wrapper.log`

Verified current result:
- `OK: ShaderGen fixture produced ../ShaderGlass/Shaders/RetroArch/fixture/FixtureM2LocalShaderDef.h and ../ShaderGlass/Shaders/RetroArch/fixture/FixtureM2LocalPresetDef.h with MSL-shaped payload bytes`

Release implication:
- this is the current partial proof boundary for generator integration
- the next implementation pass must replace fixture-only confidence with the real mandatory manifest preset set

Shared files touched for this slice:
- `../ShaderGC/pch.h`
- `../ShaderGC/SPIRV.h`
- `../ShaderGC/SPIRV.cpp`
- `../ShaderGC/SourceDefs.h`
- `../ShaderGC/ShaderGC.cpp`
- `../ShaderGen/ShaderGen.h`
- `../ShaderGen/ShaderGen.cpp`

## Handoff Packet To Later Phases

### What `m2-engine-agent` may assume

- shared MSL emission is no longer theoretical
- the mac generator path can produce MSL-shaped payload bytes for at least a controlled fixture

### What `m2-engine-agent` may not assume

- real manifest-selected presets already generate correctly
- binding metadata is stable until the generated-output manifest says so
- runtime `PresetDef` materialization is solved for the mandatory preset set

### Required next artifact before handoff is complete

- a generated-output manifest for the mandatory preset set with explicit pass ordering, binding metadata, and failure classification
