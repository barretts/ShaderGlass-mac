# ShaderGlass macOS Port — Roadmap Implementation Plan

_Granular, phase-by-phase sequence to implement `ROADMAP.md`: take the port from the
working "thin live path" (one hand-ported shader pass) to **full feature parity** — the
real engine driving the 3,342-shader RetroArch library with multi-pass, feedback, and
history, behind a native macOS UI._

**How to read this:** stages A–H, each split into small phases. Every phase has a crisp
**exit** and **verify** so it can land and be checked independently. Phases are sized to
"one sitting, one verifiable result." Build/GPU steps need the command sandbox disabled
(see `RUNNING.md`). The four regression suites + the offscreen golden are the standing
regression gate after every phase that touches shared engine code.

**Already done (do NOT redo — verified in tree):** `sg_geometry.h`, `sg_clock.h`,
`sg_image.{h,mm}` (ImageIO decode), `IRenderBackend` gaps G1 (`CreateTexture` initialData),
G3 (`ReadbackTexture` + `TextureDesc.cpuReadable`), G5 (CopyTexture ordering contract),
and the arm64 SPIRV-Cross + glslang with MSL (`mac/deps/`). The migration backbone is
`M0b-migration-map.md` (file:line substitution tables + hard-parts H1–H8); this plan
sequences it and adds the post-decouple stages.

**One upfront decision (Stage A0):** the decouple rewrites *shared* engine `.cpp` bodies
to call `IRenderBackend` instead of `ID3D11DeviceContext`. To keep the **Windows `.sln`
building**, a `D3D11Backend` implementing `IRenderBackend` must exist (Stage H, optional).
Until then the Windows build is broken. Default stance: **mac-first** — defer `D3D11Backend`
to Stage H; the mac engine (libsgcore + MetalBackend) is the verification target throughout.

---

## Stage A — Engine decouple: foundations & headers (zero behavior change)

_Goal: sever the Windows include chain and retype the leaf headers so the engine `.cpp`
bodies (Stage B+) have portable types to compile against. Each phase is pure type/include
work — nothing executes differently. On mac these compile into a not-yet-linked TU; on
Windows they'd need Stage H. Verify by `-fsyntax-only` on mac where possible._

- **A0 — Decide & record the Windows-build stance.** Confirm mac-first (D3D11Backend
  deferred to Stage H). Add a one-line note to `STATUS.md`. *Exit:* decision written.
  *Verify:* n/a (decision).
- **A1 — Portable pch.** Create `ShaderGlass/sg_pch_portable.h` (STL + `IRenderBackend.h`
  + `sg_geometry.h` + `sg_clock.h`, no windows/d3d11/winrt). Gate `pch.h`:
  `#ifdef SG_WINDOWS #include "framework.h" #else #include "sg_pch_portable.h" #endif`.
  *Exit:* `pch.h` compiles to a portable prelude when `SG_WINDOWS` is unset. *Verify:*
  `clang++ -std=c++20 -fsyntax-only -DSG... ShaderGlass/pch.h` (with mac include paths) is clean.
- **A2 — `sg_clock.h` wired to the engine.** Confirm `sg_clock.h` exposes `sg::MonotonicMillis()`
  + `SG_TICKS()` and is included by the portable pch (it already exists; just ensure the
  engine path sees it without capture headers). *Exit:* `SG_TICKS()` resolvable in an engine TU.
  *Verify:* compile a 1-line probe TU that calls `SG_TICKS()`.
- **A3 — `Shader.h` retype.** Drop `pch.h` direct include reliance; `m_vertexShader`+`m_pixelShader`
  → `sg::BackendShader* m_backendShader`; `DXGI_FORMAT m_format` → `sg::PixFmt m_format`; delete
  `m_vertexBlob`/`m_pixelBlob`; `Create(com_ptr<ID3D11Device>)` → `Create(sg::IRenderBackend&)`.
  Keep `float4`/`float4x4` POD as-is. *Exit:* header parses portably. *Verify:* `-fsyntax-only`.
- **A4 — `Texture.h` retype.** `m_textureResource`+`m_textureView` → `sg::BackendTexture* m_texture`;
  `Create(...)` → `Create(sg::IRenderBackend&)`. *Exit/Verify:* `-fsyntax-only` clean.
- **A5 — `ShaderPass.h` retype.** device/context → `sg::IRenderBackend*`; views → `sg::BackendTexture*`;
  buffers → `sg::BackendBuffer*`; sampler map → `sg::BackendSampler*`; drop input-layout/blend-state
  members; `UINT` → `uint32_t`. *Exit/Verify:* `-fsyntax-only` clean.
- **A6 — `Preset.h` retype.** `#include "IRenderBackend.h"`; `Create(...)` → `Create(sg::IRenderBackend&)`.
  *Exit/Verify:* `-fsyntax-only` clean.
- **A7 — `ShaderGlass.h` retype.** Replace the COM/Win32 member block with `sg::IRenderBackend* m_backend`
  + `sg::BackendTexture*` collections; drop `m_swapChain*`/`m_rasterizerState`/RTV members; `HWND`/`HMONITOR`
  → `void*`; `POINT` → `sg::Point`; `RECT` → `sg::Rect`; `ULONGLONG` → `uint64_t`; retype `Initialize`/
  `Process`/setters. *Exit:* the engine class header is Windows-type-free. *Verify:* `-fsyntax-only`.

## Stage B — Engine decouple: resource `.cpp` bodies

_Goal: rewrite the small resource files against `IRenderBackend`. These are mostly the
1:1 verb swaps the interface was designed for (migration map §2 tables M1–M17)._

- **B1 — `Shader.cpp` format table.** `sFormats` → `unordered_map<string, sg::PixFmt>`. *Exit:*
  table compiles. *Verify:* `-fsyntax-only`.
- **B2 — `Shader.cpp` Create + D3DCompile gate (H2).** `Create()` → one `backend.CreateShader(...)`;
  wrap `Compile()`/`D3DCompile` in `#ifdef SG_WINDOWS`; on mac `assert(VertexLength != 0)` (shaders
  arrive precompiled). Replace `OutputDebugStringA` with a neutral log. *Exit:* `Shader.cpp` compiles
  on mac. *Verify:* compiles into libsgcore-candidate TU; no d3dcompiler symbols.
- **B3 — `Texture.cpp` decode+upload (H1).** Replace `CreateWICTextureFromMemoryEx` with
  `sg::DecodeImageFileBGRA` (already exists) → `backend.CreateTexture(desc, bytes, rowPitch)` (G1,
  already exists). *Exit:* `Texture.cpp` compiles + loads a PNG to a `BackendTexture*`. *Verify:* a
  tiny harness loads a preset image, asserts non-null + correct dims.
- **B4 — `ShaderPass.cpp` per-pass verbs.** The dense 1:1 swap (map M13/M14/M16, ~25 substitutions
  in `:290–400`): `RSSetViewports`→`SetViewport`, `OMSetRenderTargets`→`BeginRenderPass`/`EndRenderPass`,
  `IASet*`/`VS/PSSetShader`→`BindShader`/`SetVertexBuffer`, `PSSetShaderResources`→`BindTexture`,
  `PSSetSamplers`→`BindSampler`, `VS/PSSetConstantBuffers`→`BindConstantBuffer`, `Map/Unmap`→
  `UpdateConstantBuffer`, `Draw`→`Draw`, blend→`SetBlend`. *Exit:* `ShaderPass.cpp` compiles. *Verify:*
  `-fsyntax-only` + reads cleanly against the verified backend_test verb usage.
- **B5 — `ShaderPass.cpp` cursor pass (H8).** `RenderCursor` → `BeginRenderPass(target, clear=false)`
  + `SetBlend(AlphaOver)` + draw + `SetBlend(Disabled)`. *Exit:* compiles; matches the load-not-clear
  contract. *Verify:* `-fsyntax-only`; confirm against `IRenderBackend.h` BeginRenderPass(load) doc.
- **B6 — `Preset.cpp` thread the backend.** Pass `backend` into the two callee `Create` calls. *Exit/Verify:* compiles.

## Stage C — Engine decouple: the loop body (`ShaderGlass.cpp`, 1235 lines — split fine)

_Goal: the highest-risk file, broken into the smallest independently-compilable slices.
Do the swap-chain/present first (drawable lifetime, H3), then resource creation, then the
copy paths (H5), then the geometry seam (H7)._

- **C1 — Clock sites.** Replace all `GetTickCount64()` with `SG_TICKS()`; `ULONGLONG`→`uint64_t`
  (map §5 exact list: `:83,84,424,652,1165` + the `ShaderGlass.h` fields + `CaptureSession.{h,cpp}`).
  *Exit:* timing compiles portably. *Verify:* `-fsyntax-only`; arithmetic unchanged.
- **C2 — Swap-chain init → `Initialize`.** Replace `CreateSwapChainForHwnd`/`GetBuffer`/RTV block
  (`:88–166`) with `m_backend->Initialize(nativeLayer, w, h, hdr)`; drop `m_swapChain*`/rasterizer
  state. *Exit:* init compiles. *Verify:* `-fsyntax-only`.
- **C3 — Present + drawable-per-frame (H3).** `Present()`→`m_backend->Present()`; the final pass
  calls `BeginFrame()` **every frame** for its target (not a cached RTV). Replace any
  `m_displayTexture->GetDesc()` sizing with a cached width/height. *Exit:* present path compiles.
  *Verify:* `-fsyntax-only` + reason-through against MetalBackend's BeginFrame/Present.
- **C4 — Resize → `ResizeSwapChain`.** `:344–379` → `m_backend->ResizeSwapChain(w,h)`; delete
  `SetSwapchainColorSpace` (H4 — backend re-asserts colorspace). *Exit/Verify:* compiles.
- **C5 — Per-pass resource creation.** `:698–925` `CreateTexture2D`/RTV/SRV → `m_backend->CreateTexture(desc)`
  (renderTarget flag per pass). *Exit/Verify:* compiles; texture descs map to `TextureDesc`.
- **C6 — Feedback/history copies (H5).** `:1093–1160` `CopyResource`/`CopySubresourceRegion` →
  `m_backend->CopyTexture(...)` with `CopyOrigin`/`CopyExtent`; replicate the box logic. *Exit/Verify:*
  compiles; ordering relies on the G5 contract (already documented).
- **C7 — GrabOutput (H6).** `:1176–1230` → `CreateTexture(cpuReadable=true)` + `ReadbackTexture`.
  *Exit/Verify:* compiles.
- **C8 — Window-geometry provider seam (H7), trivial impl.** Introduce `sg::IGeometryProvider`
  (returns `sg::Rect`/`sg::Point` for client/window/monitor) injected into the engine; replace
  `GetMonitorInfo`/`GetClientRect`/`ClientToScreen`/`GetWindowRect`/`DwmGetWindowAttribute` calls.
  Ship a **trivial** provider (full-source, no crop/pan/offset) so the engine compiles + runs the
  simple "show whole frame" case. Replace `PostMessage` notifications with injected `std::function`
  callbacks; drop `resource.h`. *Exit:* `ShaderGlass.cpp` compiles fully on mac. *Verify:* `-fsyntax-only`
  + the trivial provider returns sane rects.

## Stage D — Build `libsgcore` and wire it into the app

_Goal: the payoff — the real engine running on Metal, replacing the thin LivePipeline path.
This is where multi-pass/feedback/history start working for free._

- **D1 — `libsgcore` build script.** New `mac/core/build_core.sh` (mirrors the hand-rolled pattern)
  compiling `ShaderGlass.cpp/ShaderPass.cpp/Shader.cpp/Texture.cpp/Preset.cpp` + `ShaderGC/ShaderDef`
  into `libsgcore.a`, arm64, `-isysroot $(xcrun ...)`, NO `SG_WINDOWS`. *Exit:* `libsgcore.a` links.
  *Verify:* `lipo -archs` = arm64; `nm` shows the engine symbols, no D3D/winrt undefineds.
- **D2 — Offscreen engine harness.** A `core_test.mm`: instantiate `ShaderGlass` with `MetalBackend`
  (headless), load the passthrough preset, feed `screen6.png`, run one `Process()`, `ReadbackTexture`,
  PNG. *Exit:* harness runs. *Verify:* output **byte-identical** to `demo/out/passthrough.png` (proves
  the real engine's single-pass path matches the verified thin path).
- **D3 — Multi-pass offscreen.** Same harness, load a 2-pass preset (e.g. a CRT with a blur pass).
  *Exit:* renders without error. *Verify:* output is stable across frames; visually sane PNG;
  intermediate pass textures created (assert pass count > 1).
- **D4 — Feedback/history offscreen.** Load an afterglow/persistence preset (uses `*Feedback` /
  `OriginalHistoryN`). *Exit:* renders. *Verify:* frame N+1 differs from frame N for a changing input
  (feedback is live), history textures allocated (assert).
- **D5 — Wire `libsgcore` into the app: `EngineBridge`.** New `mac/app/EngineBridge.{h,mm}` exposing
  the engine to `LivePipeline` (set preset, set param, process frame). *Exit:* app links libsgcore.
  *Verify:* app builds + `--selftest` golden still identical (engine path, not thin path).
- **D6 — Switch the live FrameSink to the engine.** `LivePipeline.onCaptureFrameTex` calls the engine's
  `Process(capturedTexture, ticks, frameNo)` instead of the inline single draw. Keep the trivial
  geometry provider (full-frame). *Exit:* app captures live through the real engine. *Verify (human):*
  live window capture + passthrough preset looks correct on screen; resize stable.
- **D7 — Retire / fence the thin path.** Keep the static-image thin path for `--selftest` only; the
  live path is engine-driven. *Exit:* one render owner. *Verify:* both selftest golden + live capture pass.

## Stage E — M4: RetroArch shader → MSL codegen (the 3,342-shader library)

_Goal: stop hand-porting; generate MSL for every `ShaderDef` via the arm64 `CompilerMSL`
(already built). Independent of Stages F–H._

- **E1 — `ShaderDef` MSL fields.** Add `VertexSourceMSL`/`FragmentSourceMSL` (and/or `*MetalLib`) to
  `ShaderGC/ShaderDef.h`; `#if` so a def can carry both HLSL (Windows) and MSL (mac). *Exit:* struct
  compiles both sides. *Verify:* `-fsyntax-only`.
- **E2 — `SPIRV::GenerateMSL`.** In `ShaderGC/SPIRV.cpp`, add a function wrapping
  `spirv_cross::CompilerMSL::compile()` with `msl_options`: `platform=macOS`, honor binding decorations
  (texture+sampler at `Samplers[].binding`), deterministic entry-point name, matrix major-ness matching
  the row-major MVP. *Exit:* links against `mac/deps` spirv-cross-msl. *Verify:* emits MSL for one
  known `.spv` (extend `check_msl` style); diff reflection vs the HLSL path.
- **E3 — Host-tool build for ShaderGen+ShaderGC on mac.** New build script compiling the generator
  for the build machine, linking arm64 glslang + spirv-cross. *Exit:* `ShaderGen` runs on mac. *Verify:*
  converts one `.slangp` end to end (GLSL→SPIRV→MSL) without error.
- **E4 — Codegen one shader, validate.** Regenerate `crt-geom` (single pass) to MSL; load it through
  `libsgcore` offscreen. *Exit:* renders. *Verify:* output matches the hand-ported `crt_demo` *family*
  visually; sampler/param byte offsets round-trip (assert `m_samplers.at(binding)` for every sampler).
- **E5 — Codegen a multi-pass shader.** Regenerate `crt-easymode-halation` (5 passes). *Exit:* renders.
  *Verify:* 5 passes created; feedback/history bindings resolve; visually sane.
- **E6 — Batch-regenerate all 3,342 + tail fixups.** Run the generator over the full library; build a
  golden sample (~20 diverse shaders) offscreen. *Exit:* library regenerated. *Verify:* the 20-shader
  sample renders identically (or within tolerance) to the Windows reference; log any shaders needing
  manual MSL fixups (e.g. Mega Bezel).
- **E7 — Drop the hand-ported MSL.** Remove `spike/crt_demo.metal` from the live path once codegen
  covers it. *Exit:* one shader source of truth. *Verify:* suites + golden green.

## Stage F — Native UI parity (replaces the thin control bar)

_Goal: the real ShaderGlass UX — shader browser, live param sliders, menus, hotkeys, config.
Each control is its own phase._

- **F1 — Shader browser (`NSOutlineView`).** Tree of the 3,342 presets by category (replaces
  `BrowserWindow.cpp`); selection sets the engine preset. *Exit:* browse + select works. *Verify (human):*
  pick a shader, it applies live.
- **F2 — Param sliders (SwiftUI/AppKit).** `ShaderParam` min/max/step/default → live sliders bound to
  the engine (replaces `ParamsWindow.cpp`). *Exit:* sliders move params live. *Verify (human):* tweak a
  CRT param, see it change.
- **F3 — Menu bar (`NSMenu`).** Full menu structure (replaces the `.rc` `HMENU`): Input/Output/Shader/
  Help. *Exit:* menus functional. *Verify (human):* menu items drive the engine.
- **F4 — Config persistence (`NSUserDefaults`).** Replace the registry I/O (`ShaderWindow.cpp`/
  `BrowserWindow.cpp`); persist last preset/target/params; presets under `~/Library/Application Support`.
  *Exit:* settings survive relaunch. *Verify (human):* relaunch restores last shader + params.
- **F5 — Global hotkeys (Carbon `RegisterEventHotKey`).** Pause/screenshot/next-shader/etc (replaces
  `RegisterHotKey`; no extra TCC). *Exit:* hotkeys fire. *Verify (human):* a global hotkey toggles a feature.
- **F6 — Crop/Hotkey/Input dialogs.** SwiftUI sheets / `NSAlert` (replaces the Win32 dialogs). *Exit:*
  dialogs work. *Verify (human):* set a crop, it applies.
- **F7 — Real window-geometry provider (upgrades C8 trivial).** Implement crop/pan/offset/locked-area
  via SCK window frames + Quartz, feeding the engine's preprocess MVP. *Exit:* crop/pan work live.
  *Verify (human):* crop a captured window; aspect + offset correct vs Windows behavior.
- **F8 — Save output (screenshot).** Wire `GrabOutput` → `ReadbackTexture` → `sg_image::EncodePNG`
  to a Save panel. *Exit:* screenshot saves. *Verify:* saved PNG matches the on-screen frame.

## Stage G — Advanced capture & display modes

- **G1 — Cursor overlay.** From-scratch macOS cursor (bundled `NSCursor` shape + `NSEvent.mouseLocation`
  position) feeding the engine's `RenderCursor` pass. *Exit:* cursor composited. *Verify (human):*
  cursor appears in clone output. (Document: real OS cursor can't be read; this is synthetic.)
- **G2 — Webcam capture (AVFoundation).** `AVCaptureSession` → `MTLTexture` (replaces Media Foundation
  `DeviceCapture`); add `NSCameraUsageDescription` + camera entitlement. *Exit:* a webcam feeds the
  engine. *Verify (human):* webcam frames shaded live.
- **G3 — Glass overlay mode (HIGH RISK — spike first).** Transparent click-through `NSWindow` applying
  shaders to the live desktop behind it, via `SCContentFilter(display:excludingWindows:)` self-exclusion.
  **Sub-phase G3a:** measure display→SCK→Metal→present latency for same-display capture-redisplay; decide
  go/no-go. **G3b:** if latency acceptable, implement the overlay window; else document the limitation
  (fallback: window-clone / separate-display). *Exit:* go/no-go recorded; overlay works or is documented
  out. *Verify (human):* shader visibly applies to desktop behind the window with no feedback loop.
- **G4 — HDR/EDR (best-effort).** `CAMetalLayer` `RGBA16Float` + `wantsExtendedDynamicRangeContent` for
  the `m_useHDR` path. *Exit:* HDR path runs. *Verify (human):* HDR content renders without clamping;
  document it's not pixel-parity with Windows scRGB.

## Stage H — Windows build maintenance (OPTIONAL, deferred)

_Only if keeping the Windows `.sln` green matters. Without this, the shared-engine decouple
(Stages A–C) leaves Windows non-building until done._

- **H1 — `D3D11Backend`.** Implement `IRenderBackend` over D3D11 (the verbs `ShaderPass.cpp` used to
  call directly), in `mac/backend/win/`. *Exit:* compiles in the VS project. *Verify:* Windows `.sln`
  builds + runs with the decoupled engine (needs a Windows box / CI).
- **H2 — Wire `D3D11Backend` into the Windows entry point.** Replace the direct-device path. *Exit:*
  Windows app runs through `IRenderBackend`. *Verify:* a Windows reference render matches pre-refactor.

---

## Verification spine (runs after every shared-engine phase)

1. `mac/backend/build_test.sh`, `mac/capture/build_test.sh`, `mac/spike/build.sh`, `mac/demo/build.sh` — all PASS.
2. The offscreen **golden**: `app/build.sh selftest` (or `core_test` from D2 on) → byte-identical to
   `demo/out/passthrough.png`.
3. From Stage D: an offscreen **engine** golden suite (passthrough + a multi-pass + a feedback preset)
   re-rendered and diffed each phase.
4. Live smoke: app runs under `MTL_DEBUG_LAYER=1` with zero validation errors.
5. **Deferred but required before "production":** the Phase-5 ThreadSanitizer + resize/stop-start/quit
   stress run from `REVIEW.md` (the one item that needs a TCC grant + on-device churn).

## Sequencing notes

- **Stages A→B→C→D are strictly ordered** (each compiles against the prior). E, F, G are largely
  independent once D lands (the engine runs): E (shaders), F (UI), G (modes) can interleave.
- **Smallest meaningful milestone:** A–D (the real engine drives live capture with multi-pass +
  feedback, even if only hand-ported/few shaders and a minimal UI). That alone unlocks the bulk of
  ShaderGlass's value.
- **Biggest risk concentration:** C3 (drawable-per-frame), C6 (copy ordering), C8/F7 (geometry seam),
  G3 (glass latency). The map's hard-parts H1–H8 are pre-resolved except H7 (C8/F7) and the inherent
  G3 latency question.
- **Highest effort, lowest risk:** E6 (regenerate 3,342 shaders — mechanical once E2–E5 prove the path).
