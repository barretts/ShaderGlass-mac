# M0b Engine Port Plan For Upstream Inheritance

## Summary

Move the macOS port from the thin one-pass `LivePipeline` toward the real ShaderGlass
engine running on `sg::IRenderBackend`.

This milestone is not full UI parity and not the 3,342-shader generator. The goal is to
compile and run the shared engine on Metal so upstream engine and shader work can be
inherited directly instead of manually recreated in the mac app.

The detailed decouple map remains `M0b-migration-map.md`. This plan is the milestone
scope and execution order for turning that map into a macOS engine path.

## Stance

Use a mac-first implementation stance.

- Preserve macOS correctness as the target for this milestone.
- Do not block on Windows `.sln` compatibility.
- Defer `D3D11Backend` unless Windows parity becomes an explicit requirement.
- Keep existing overlay mode, capture hardening, and curated shader changes in place.

## Non-Goals

- Full native UI parity.
- Batch generation of the full RetroArch shader library.
- Complete Windows backend parity.
- Replacing already-working capture or overlay code except where required to feed the
  shared engine.

## Public Interfaces And Types

Use the existing portable render contracts before adding new backend API.

- `sg::IRenderBackend`
- `sg::BackendTexture`
- `sg::BackendShader`
- `sg::BackendBuffer`
- `sg::BackendSampler`
- `sg::PixFmt`
- `sg::Rect`
- `sg::Point`
- `SG_TICKS()`

Only add backend API if the M0b work exposes a concrete missing render verb. The current
map already identifies texture upload, readback, and copy ordering as the relevant gaps,
and the repository roadmap notes those gaps are already present in-tree.

Add these minimum engine seams:

- `sg::IGeometryProvider`: returns source, client, display, monitor, and cursor geometry
  using `sg::Rect` and `sg::Point`. The first mac implementation may be full-frame only.
- Engine notification callbacks: injected `std::function` callbacks replacing Win32
  `PostMessage` and resource-update notifications.
- `EngineBridge`: Objective-C++ app-facing wrapper for preset selection, parameter
  updates, resize, frame processing, and shutdown.

## Stage 1 - Portable Engine Headers

Finish the header side of the M0b decouple sequence from `M0b-migration-map.md`.

1. Gate the shared `pch.h` so mac engine translation units use a portable prelude instead
   of `framework.h`.
2. Ensure the portable prelude includes only STL, `IRenderBackend.h`, `sg_geometry.h`,
   and `sg_clock.h`.
3. Retype `Shader.h`, `Texture.h`, `ShaderPass.h`, and `Preset.h` from D3D/WinRT handles
   to backend handles.
4. Retype `ShaderGlass.h` from Win32 geometry, D3D resources, and `ULONGLONG` to portable
   geometry, backend textures, and `uint64_t`.

Exit: shared engine headers parse on macOS without Windows, D3D, DXGI, or WinRT types.

Verification after this stage:

```bash
mac/backend/build_test.sh
mac/capture/build_test.sh
mac/app/build.sh selftest
```

## Stage 2 - Resource Bodies

Port the smaller resource implementation files before touching the engine loop.

1. `Shader.cpp`: map formats to `sg::PixFmt`; create shaders through
   `IRenderBackend::CreateShader`; keep runtime `D3DCompile` behind `SG_WINDOWS`.
2. `Texture.cpp`: decode with the portable image helper and upload through the backend
   texture creation path.
3. `ShaderPass.cpp`: replace D3D context calls with backend draw verbs:
   `SetViewport`, `BeginRenderPass`, `EndRenderPass`, `SetVertexBuffer`,
   `BindShader`, `BindTexture`, `BindSampler`, `BindConstantBuffer`,
   `UpdateConstantBuffer`, `SetBlend`, and `Draw`.
4. `Preset.cpp`: thread `sg::IRenderBackend&` into shader, texture, and pass creation.

Exit: resource bodies compile against `IRenderBackend` on macOS.

Verification after this stage:

```bash
mac/backend/build_test.sh
mac/capture/build_test.sh
mac/app/build.sh selftest
```

## Stage 3 - Engine Loop Body

Port `ShaderGlass.cpp` last, in slices that keep the failure surface small.

1. Replace clock sites with `SG_TICKS()` and `uint64_t`.
2. Replace swap-chain initialization with `IRenderBackend::Initialize`.
3. Acquire the Metal drawable target per frame through `BeginFrame`; do not cache the
   display render target as a persistent texture.
4. Replace present and resize with `Present` and `ResizeSwapChain`.
5. Create pass, preprocessing, feedback, and history textures through the backend.
6. Replace feedback/history copies with `CopyTexture`, preserving the existing copy box
   and fractional-pixel clamp behavior.
7. Replace grab-output texture creation/readback with backend texture/readback support.
8. Inject `sg::IGeometryProvider` and notification callbacks so engine code no longer
   depends on Win32 geometry APIs, `resource.h`, or `PostMessage`.

Exit: `ShaderGlass.cpp` compiles fully for macOS against the Metal backend.

Verification after this stage:

```bash
mac/backend/build_test.sh
mac/capture/build_test.sh
mac/app/build.sh selftest
```

## Stage 4 - libsgcore

Create the shared-engine build target under `mac/core/`.

1. Add a `libsgcore` or equivalent static core target compiling:
   `ShaderGlass.cpp`, `ShaderPass.cpp`, `Shader.cpp`, `Texture.cpp`, `Preset.cpp`, and
   the required shader-definition sources.
2. Keep the target arm64/macOS first, without `SG_WINDOWS`.
3. Verify the linked archive has no D3D, DXGI, WinRT, or Windows unresolved symbols.
4. Add `mac/core/core_test.mm`.

Initial core test:

- Instantiate the real engine with `MetalBackend`.
- Load a passthrough preset.
- Feed the same image used by the current golden path.
- Verify output is byte-identical to the current passthrough golden.

Additional Stage 4 tests:

- Multi-pass preset test: render a small hand-ported or generated multi-pass preset and
  verify stable output.
- Feedback/history test: feed changing frames and verify frame N+1 depends on frame N.

Verification after this stage:

```bash
mac/backend/build_test.sh
mac/capture/build_test.sh
mac/core/build_core.sh
mac/app/build.sh selftest
```

## Stage 5 - EngineBridge And Live App Wiring

Add an Objective-C++ app-facing bridge so the live app can call the real engine instead
of the inline one-pass draw path.

`EngineBridge` responsibilities:

- Engine lifetime and shutdown.
- Backend ownership or attachment.
- Preset selection.
- Parameter updates.
- Resize propagation.
- Frame processing.
- Grab/readback handoff where needed by screenshot or selftest flows.

Wire the live capture path so captured frames flow through the real engine. Keep the
first geometry provider implementation simple and full-frame if needed; crop, pan, and
advanced window geometry can follow after the engine path is proven.

Exit: live display/window capture renders through the shared engine on Metal.

Verification after this stage:

```bash
mac/backend/build_test.sh
mac/capture/build_test.sh
mac/core/build_core.sh
mac/app/build.sh selftest
```

Live smoke:

- Display capture through the real engine.
- Window capture through the real engine.
- Overlay remains click-through.
- Shader output is visually correct.
- Stop, start, resize, and quit do not hang.

## Risks

- Metal drawable lifetime differs from D3D back-buffer lifetime. The engine must acquire
  a frame target per frame.
- Feedback and history depend on copy ordering. `CopyTexture` must observe prior draws
  and be observed by later draws.
- Cursor rendering must load the existing target contents rather than clearing.
- Geometry is not a render-backend concern. Keep it injected into the engine instead of
  expanding `IRenderBackend`.
- Runtime D3D shader compilation is Windows-only. macOS should require offline-compiled
  shader bytes for engine presets.

## Definition Of Done

- Shared engine code compiles for macOS without Windows/D3D types.
- `libsgcore` or equivalent core target builds.
- The app can render live frames through the real engine on Metal.
- Passthrough through the real engine is byte-identical to the current golden.
- A multi-pass preset renders stable output.
- A feedback/history preset proves frame-to-frame dependency.
- Live smoke passes for display capture, window capture, overlay click-through, and
  stop/start/quit behavior.
