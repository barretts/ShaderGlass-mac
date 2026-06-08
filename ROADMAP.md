# ShaderGlass macOS Port — Roadmap (what's left)

This is the forward-looking companion to `STATUS.md`. It records what remains, what is known about
the hard parts, and the recommended order. The full original plan (all milestones, parity risks,
the D3D11→Metal mapping table) lives at
`/Users/bsonntag/.claude/plans/translate-this-to-support-moonlit-lampson.md`.

## Where we are vs the milestone roadmap

The original plan defined M-1…M5 (full port) and a "Live GUI Stage" L1…L6 (thin path). Done:

- **M-1** Metal-mapping spike ✅
- **M0 (deps)** arm64 glslang + SPIRV-Cross with MSL ✅
- **M0 (backend)** `IRenderBackend` + `MetalBackend` (incl. windowed present path) ✅
- **L1–L5** thin live path: live capture + shader + GUI ✅ (confirmed on screen)

Not done — these are the meaningful next steps, in dependency order.

---

## 1. M0b — Decouple the engine from Windows (THE blocker for everything rich)

**Why it matters:** the thin path renders ONE shader pass. The actual value of ShaderGlass — the
1200+ RetroArch shaders, CRT-Royale, Mega Bezel, feedback/afterglow, multi-pass scale chains — all
live in the C++ engine (`ShaderGlass.cpp`/`ShaderPass.cpp`/`Shader.cpp`), which still
`#include`s `windows.h`/`winrt`/`d3d11.h` transitively via `pch.h`. Until that compiles
backend-free against `IRenderBackend`, none of the multi-pass machinery runs on mac.

**The map already exists:** `mac/M0b-migration-map.md` — exhaustive, file:line, dependency-ordered:
- ~204 touchpoints across 12 files.
- A recurring-substitution table (`com_ptr<ID3D11X>` → `Backend*`, `DXGI_FORMAT` → `PixFmt`,
  `GetTickCount64` → `SG_TICKS`, `RECT`/`POINT` → `sg::Rect`/`sg::Point`, etc.).
- Dependency-ordered edit sequence (portable types + pch + clock shim FIRST, then leaf resource
  headers, then engine class header, then the `.cpp` bodies, `ShaderGlass.cpp` last).

**Hard parts flagged in the map (NOT mechanical — need real design):**
- **H1 — Texture upload (was a blocker, now unblocked):** `Texture.cpp`'s WIC decode+upload. The
  decode helper now exists (`sg_image::DecodeImageFileBGRA`) and `CreateTexture(initialData)` (G1)
  exists. Wire them.
- **H2 — `D3DCompile` runtime fallback:** dead on mac (shaders arrive precompiled). Guard behind
  `#ifdef SG_WINDOWS`; `assert(VertexLength != 0)` on mac.
- **H3 — Swap-chain vs CAMetalLayer drawable lifetime:** D3D holds one persistent backbuffer; Metal's
  `nextDrawable` is per-frame/transient. The engine must call `BeginFrame()` each frame for the final
  pass instead of caching a display RTV. `MetalBackend` already models this; the engine loop in
  `ShaderGlass.cpp` must be adapted (any `m_displayTexture->GetDesc()` sizing must use a cached size).
- **H4 — `SetColorSpace1`/HDR re-assert on resize:** delete `SetSwapchainColorSpace`; backend
  re-asserts colorspace in `ResizeSwapChain` (already does).
- **H5 — CopyResource ordering + GrabOutput fractional clamp:** feedback/history copies must not be
  reordered across the draws that produce/consume them (the `CopyTexture` ordering contract is
  documented in `IRenderBackend.h`). The GrabOutput box-clamp math (`ShaderGlass.cpp:1117-1129`) must
  be replicated when building `CopyOrigin`/`CopyExtent`.
- **H7 — Injected window-geometry / cursor providers:** `GetMonitorInfo`/`GetClientRect`/
  `GetCursorInfo`/`DwmGetWindowAttribute` are not GPU calls and have no `IRenderBackend` mapping —
  they need a small injected `IWindowGeometry` provider returning `sg::Rect`/`sg::Point` (macOS impl
  via SCK + Quartz). The crop/box arithmetic itself ports once `RECT`/`POINT` are structs.

**Critical clock-epoch constraint (from capture review):** on macOS, route ALL of
`ShaderGlass.cpp`'s `GetTickCount64` sites through `SG_TICKS()` (= `sg::MonotonicMillis`). The capture
path stamps `frameTicks` with `MonotonicMillis`; `Process()` compares `now - frameTicks` against a
<20ms staleness guard. Two clocks/epochs → the guard silently breaks (and risks unsigned underflow).

**Verifiability caveat:** "the engine compiles backend-free" is only fully checkable with a Windows
compiler (to confirm the host build still works) + the wired mac engine. Neither exists in this
environment. Do M0b incrementally, paired with extending the D3D11 backend so Windows keeps building.

**Interface gaps already closed for it:** G1 (`CreateTexture` initialData), G3 (`ReadbackTexture` +
`TextureDesc.cpuReadable`), G5 (`CopyTexture` ordering contract). Still needs: none blocking — but a
`D3D11Backend` (the Windows side of `IRenderBackend`) must be written so the host build survives.

## 2. M4 — RetroArch shader codegen (after M0b)

- Extend `ShaderGC`/`ShaderGen` (currently Windows-only, emits DXBC) into a CMake **host tool** that
  links the arm64 glslang + SPIRV-Cross built in `deps/`, and emits **MSL text** into `ShaderDef`
  (add `VertexSourceMSL`/`FragmentSourceMSL` fields).
- Implement `SPIRV::GenerateMSL` wrapping `spirv_cross::CompilerMSL::compile()`. Required
  `CompilerMSL::Options`: `platform=macOS`; honor binding decorations (so texture+sampler land at
  `Samplers[].binding`, supporting arbitrary per-pass indices); deterministic entry-point name used
  in `newFunctionWithName`; matrix major-ness reconciled with the row-major HLSL MVP; NDC orientation
  checked against the drawable.
- Regenerate all ~3,300 defs; drop the hand-ported MSL. Budget a per-shader fixup tail for complex
  shaders (Mega Bezel etc.).
- Verification: diff emitted MSL texture/sampler indices vs the D3D `Samplers[].binding` (every index
  must round-trip through `m_samplers.at(...)`); diff param byte offsets; spot-check ~20 shaders
  render identically to Windows via the offscreen golden path.

## 3. UI parity (M5) + L6 polish

- **L6 (small, do anytime):** nil-drawable skip is in; add an explicit encoder/cb leak guard, document
  RING_DEPTH coupling, About menu, persist last target/shader to `NSUserDefaults`.
- **Shader browser:** the engine exposes ~3,300 presets in a tree; build an `NSOutlineView` /
  SwiftUI `OutlineGroup` browser (replaces `BrowserWindow.cpp`).
- **Param sliders:** `ShaderParam` min/max/step → SwiftUI `Slider`s bound live (replaces `ParamsWindow.cpp`).
- **Menu bar / dialogs / global hotkeys:** `NSMenu`; crop/hotkey/input dialogs as sheets; Carbon
  `RegisterEventHotKey` for global hotkeys (no extra TCC).
- **Config:** replace the registry I/O (in `ShaderWindow.cpp`/`BrowserWindow.cpp`/`CursorEmulator.cpp`)
  with `NSUserDefaults`; user presets under `~/Library/Application Support/ShaderGlass/`.
- **Glass overlay mode (HIGH RISK — validate early):** a transparent click-through `NSWindow`
  applying shaders to the live desktop behind it. `SCContentFilter(display:excludingWindows:)` is the
  self-exclusion API, but SCK's async multi-frame latency may produce a visible feedback loop, unlike
  Windows' synchronous `WDA_EXCLUDEFROMCAPTURE`. Prove latency is acceptable before committing;
  fallback is window-clone (already working) or separate-display.
- **Webcam capture (M5):** `AVCaptureSession` (replaces Media Foundation `DeviceCapture`); needs
  `NSCameraUsageDescription` + `com.apple.security.device.camera` entitlement.

## 4. Known divergences from Windows (document, don't chase parity)

- **HDR/EDR:** `SetColorSpace1(RGB_FULL_G10_NONE_P709)` has no 1:1 macOS equivalent
  (EDR = `wantsExtendedDynamicRangeContent` + headroom). Best-effort, not pixel-parity. Deferred.
- **Live-desktop cursor over glass:** stays visible (no `SetSystemCursor` analog). The cursor overlay
  is a from-scratch macOS feature, not a port (synthesize shape from a bundled asset, position from
  `NSEvent.mouseLocation`).
- No virtual-camera/OBS-output or audio in the source — correctly out of scope.

## Recommended next move

**M0b is the unlock.** Everything rich (real shaders, multi-pass, feedback) depends on it, and the
migration map makes it executable rather than exploratory. Start with the dependency-ordered Phase 0–2
(portable types + pch + clock shim + leaf headers) — those are pure type substitutions with no
behavior change — and stand up a `D3D11Backend` in parallel so the Windows build keeps compiling. The
thin app stays as a fast visual smoke-test throughout.

A good intermediate win before the full engine: hand-port one **multi-pass** preset (e.g.
crt-easymode-halation, 5 passes) through the thin path's render loop extended to N passes + a feedback
texture — proves the multi-pass plumbing on Metal without the whole engine decouple.
