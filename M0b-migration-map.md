I now have everything I need. The cursor `RenderCursor` does NOT issue a `BeginRenderPass`-style pass alone — it re-uses the existing display target and explicitly does NOT clear, which matters for the `EndRenderPass` mapping (the cursor draws into the same already-open target as the final pass). I have confirmed all the load-bearing details. Producing the consolidated migration map.

---

# M0b Migration Map: Decoupling libsgcore from Windows

Consolidated from the 12 per-file scans, cross-checked against `IRenderBackend.h` and the live source. All line numbers verified against the current tree.

## 1. Dependency-Ordered Edit Sequence

Edit in this order; each phase compiles (or type-checks) before the next depends on it. Phases 0-2 introduce types with zero behavior change; the risky `.cpp` body rewrites come last.

**Phase 0 — Portable foundation types (no engine logic touched).**
1. **`mac/backend/sg_geometry.h` (NEW).** Define `sg::Rect { int32_t left, top, right, bottom; }` (Win32 RECT field order/semantics) and `sg::Point { int32_t x, y; }` (POINT is LONG x,y). These back every `RECT`/`POINT` in `ShaderGlass.h`/`.cpp`.
2. **Clock shim — already exists.** `sg::MonotonicMillis()` is declared `mac/capture/SCKCapture.h:45`, defined `SCKCapture.mm:16`. Do NOT redefine it. For M0b, promote the declaration into a tiny standalone `mac/backend/sg_clock.h` (or have the portable pch include `SCKCapture.h`'s decl) so engine TUs that must not pull capture headers still see `uint64_t sg::MonotonicMillis()`. Define `#define SG_TICKS() sg::MonotonicMillis()` (or call directly). Windows build wraps `GetTickCount64()`.
3. **`float4`/`float4x4` stay put.** They are already plain POD in `Shader.h:17-33` (not DirectXMath). The only constraint: nothing about them may require a D3D header. They are fine as-is once `Shader.h` drops `pch.h`. Do not move them to the backend header.

**Phase 1 — pch/framework neutralization (severs the transitive include chain).**
4. **`framework.h` (NEW portable sibling) + `pch.h` gate.** `framework.h:7-33` is 100% Windows. `pch.h:11` is the only coupling line. Gate it:
   ```
   #ifdef SG_WINDOWS
   #include "framework.h"
   #else
   #include "sg_pch_portable.h"
   #endif
   ```
   `sg_pch_portable.h` carries ONLY the portable lines from `framework.h:16-20` (`<fstream> <iomanip> <iostream> <sstream> <mutex>`) plus `<cstdint> <cstddef> <string> <vector> <map>`, `mac/backend/IRenderBackend.h`, `sg_geometry.h`, and the clock decl. Everything in `framework.h:3-15,22-33` (windows.h, shellapi, commdlg, dwmapi, malloc/memory/tchar, Unknwn, inspectable, all winrt, d3d11, d3dcompiler, dxgi1_6) is Windows-host-only and is NOT emitted for libsgcore.

**Phase 2 — leaf resource headers (retype members; no bodies yet).** These have no inbound engine dependencies except each other and must precede the `.cpp` bodies and `ShaderGlass.h`.
5. **`Shader.h`** — drop `pch.h:8` include; collapse `m_vertexShader`+`m_pixelShader` (`:39-40`) -> `sg::BackendShader* m_backendShader{nullptr}`; `DXGI_FORMAT m_format` (`:48`) -> `sg::PixFmt m_format{sg::PixFmt::BGRA8_UNORM}`; delete `m_vertexBlob`/`m_pixelBlob` (`:70-71`); `Create(com_ptr<ID3D11Device>)` (`:59`) -> `Create(sg::IRenderBackend&)`.
6. **`Texture.h`** — drop `pch.h:8`; collapse `m_textureResource`+`m_textureView` (`:24-25`) -> `sg::BackendTexture* m_texture{nullptr}`; `Create(com_ptr<ID3D11Device>)` (`:28`) -> `Create(sg::IRenderBackend&)`.
7. **`ShaderPass.h`** — drop `pch.h:8`; ctor/`Initialize` device+context pair (`:19,22`) -> `sg::IRenderBackend* backend`; `Render` resource-map value type (`:23,24`) -> `sg::BackendTexture*`; `m_sourceView`/`m_targetView` (`:34-35`) -> `sg::BackendTexture*`; remove `m_device`/`m_context`/`m_inputLayout`/`m_blendState` (`:41,42,43,55`); buffers (`:44-46`) -> `sg::BackendBuffer*`; samplers map (`:47`) -> `sg::BackendSampler*`; `UINT s_vertex*` (`:49-51`) -> `uint32_t`; `RenderCursor` cursorView (`:25`) -> `sg::BackendTexture*`.
8. **`Preset.h`** — add `#include "IRenderBackend.h"`; `Create(com_ptr<ID3D11Device>)` (`:18`) -> `Create(sg::IRenderBackend&)`. (Pure pass-through to Shader/Texture/ShaderPass — no body logic.)

**Phase 3 — engine class header.**
9. **`ShaderGlass.h`** — replace the whole COM/Win32 member block (`:67-87`) with `sg::IRenderBackend* m_backend`; fold display/preprocess/pass textures to `sg::BackendTexture*` and `std::vector<sg::BackendTexture*>` / `std::map<std::string, sg::BackendTexture*>`; drop the parallel RTV vector `m_passTargets` (`:79`) and `m_swapChain3`/`m_rasterizerState`/`m_displayRenderTarget`/`m_preprocessedRenderTarget`; `HWND`/`HMONITOR` (`:22-24,86-87`) -> `void*`; `POINT` (`:63-66,85`) -> `sg::Point`; `volatile RECT` (`:131,134`) -> `volatile sg::Rect`; `ULONGLONG` (`:95,98-100`) -> `uint64_t`; `Initialize`/`Process`/setter signatures retyped. `float4`/`m_textureSizes` (`:82`) unchanged.

**Phase 4 — resource `.cpp` bodies (now everything they reference is portable).**
10. **`Shader.cpp`** — retype `sFormats` table (`:14-43`) to `unordered_map<string, sg::PixFmt>`; rewrite `Create` (`:129-139`) to one `backend.CreateShader(...)`; gate or delete `Compile()`+`D3DCompile` (`:141-190`) behind `SG_WINDOWS` (see Hard Parts); drop file-scope `hr` (`:12`).
11. **`Texture.cpp`** — see Hard Parts (needs the new decode shim + an upload verb that does not yet exist).
12. **`ShaderPass.cpp`** — surgical 1:1 verb swap (the file the interface was literally designed against).
13. **`Preset.cpp`** — thread `backend` into the two callee `Create` calls (`:31,35`).

**Phase 5 — engine loop body (highest risk, do last).**
14. **`ShaderGlass.cpp`** — swap-chain block (`:88-166`), resize (`:344-379`), present (`:402-418`), per-pass resource creation (`:698-925`), copies (`:1093-1155`), GrabOutput (`:1176-1230`), all clock sites, geometry providers. Hard parts flagged in §3.

**Phase 6 — `Options.h`** is UI/capture-only; libsgcore needs none of it. Defer; do NOT block the engine refactor on it. (Split into `Options_core.h` later if any numeric/string table is genuinely read by core — none is on the render path.)

---

## 2. Recurring Mechanical Substitutions

| # | From (Windows) | To (portable) | Hotspots (file:line) | Approx count |
|---|---|---|---|---|
| M1 | `winrt::com_ptr<ID3D11Texture2D>` / `...RenderTargetView` / `...ShaderResourceView` | `sg::BackendTexture*` (RTV+SRV folded in) | ShaderGlass.h:69,73-81; ShaderGlass.cpp:136,698-925,1093-1155,1176-1230; ShaderPass.h:34-35; Texture.h:24-25 | ~30 members + ~25 call sites |
| M2 | `winrt::com_ptr<ID3D11Buffer>` | `sg::BackendBuffer*` | ShaderPass.h:44-46; ShaderPass.cpp:49-56,131-161 | 3 members, 3 creates |
| M3 | `com_ptr<ID3D11VertexShader>`+`com_ptr<ID3D11PixelShader>`+InputLayout | one `sg::BackendShader*` | Shader.h:39-40; ShaderPass.h:43; Shader.cpp:129-139; ShaderPass.cpp:43-47 | 2->1 collapse |
| M4 | `com_ptr<ID3D11SamplerState>` | `sg::BackendSampler*` | ShaderPass.h:47; ShaderPass.cpp:61,127-128 | 1 map |
| M5 | `com_ptr<ID3D11Device>` / `com_ptr<ID3D11DeviceContext>` (members + Create params) | `sg::IRenderBackend*` (one handle) | ShaderGlass.h:67-68; ShaderPass.h:19,22,41-42; Shader.h:59; Texture.h:28; Preset.h:18 | 6 signatures, 4 members |
| M6 | `DXGI_FORMAT` / `DXGI_FORMAT_*` literals | `sg::PixFmt` / `sg::PixFmt::*` | Shader.h:48; Shader.cpp:14-43,56-69; ShaderGlass.cpp:106,823 | 1 member, ~40-row table |
| M7 | `GetTickCount64()` / `ULONGLONG` | `sg::MonotonicMillis()` / `uint64_t` | **ShaderGlass.cpp:83,84,424,652,1165**; ShaderGlass.h:95,98-100; **CaptureSession.cpp:99,144; CaptureSession.h:58,61** | 7 call sites, 6 fields (see §5) |
| M8 | `RECT` | `sg::Rect{left,top,right,bottom}` | ShaderGlass.h:131,134; ShaderGlass.cpp:78,344,422,467,479,492-549; setters 224-243 | ~10 |
| M9 | `POINT` | `sg::Point{x,y}` | ShaderGlass.h:63-66,85; ShaderGlass.cpp:79-81,467,492 | ~8 |
| M10 | `HWND`/`HMONITOR` | `void*` (opaque native surface / capture-source id) | ShaderGlass.h:22-24,86-87; ShaderGlass.cpp:22-43; Options.h:77,84 | ~6 |
| M11 | `UINT`/`WORD` | `uint32_t`/`uint16_t` | ShaderPass.h:49-51; ShaderPass.cpp:225,246-253; Options.h passim | ~10 |
| M12 | `static HRESULT hr; assert(SUCCEEDED(hr))` | null-handle check `assert(h != nullptr)` | ShaderGlass.cpp:14 + ~20 asserts; Shader.cpp:12,135,138; ShaderPass.cpp:13,47,56,140,156,202 | ~30 |
| M13 | `m_context->Create*` / device `Create*` | `m_backend->Create{Texture,Shader,VertexBuffer,ConstantBuffer,Sampler}` | ShaderGlass.cpp + ShaderPass.cpp + Shader.cpp | ~15 |
| M14 | `m_context->{RSSetViewports,OMSet*,IASet*,VS/PSSet*,Draw,Map/Unmap,Copy*}` | `m_backend->{SetViewport,BeginRenderPass/EndRenderPass,SetBlend,SetVertexBuffer,BindShader,BindTexture,BindSampler,BindConstantBuffer,Draw,UpdateConstantBuffer,CopyTexture}` | ShaderPass.cpp:291-400 (dense); ShaderGlass.cpp copies | ~25 |
| M15 | `#include "pch.h"` (-> windows/d3d11/dxgi/winrt) | neutral prelude (`IRenderBackend.h` + `sg_geometry.h` + clock + STL) | Shader.h:8, Shader.cpp:8, ShaderPass.h:8, ShaderPass.cpp:8, Texture.h:8, Texture.cpp:8 | 6 TUs |
| M16 | `OMSetBlendState(m_blendState/NULL)` / `D3D11_BLEND_DESC` | `SetBlend(BlendMode::AlphaOver/Disabled)` (no object) | ShaderPass.cpp:190-202,393,399 | 1 desc, 3 sites |
| M17 | `D3D11_BOX` | `sg::CopyOrigin` + `sg::CopyExtent` | ShaderGlass.cpp:1110-1130,1199-1219 | 2 |

**Densest single hotspot:** `ShaderPass.cpp:290-400` (M13/M14/M16 all collapse here, ~25 substitutions in 110 lines) — but it is the cleanest 1:1 mapping. **Most-scattered:** M1 (`BackendTexture*`) and M12 (`hr` asserts).

---

## 3. HARD parts (NOT mechanical — need real design)

These do not map 1:1 to `IRenderBackend` and need decisions before/while editing.

**H1 — Texture upload: NO backend verb exists (BLOCKER). `Texture.cpp:38-49`.**
`CreateWICTextureFromMemoryEx` does decode + GPU upload in one call. `IRenderBackend::CreateTexture(const TextureDesc&)` (`:311`) takes **no `initialData`** — unlike `CreateVertexBuffer(initialData,size)` (`:379`). There is **no `UpdateTexture`/upload entry point** anywhere in the interface. This is the single hardest gap. Two sub-problems:
  - *Decode:* WIC has no portable analog. Need a new `sg::DecodeImageRGBA(const uint8_t* data, size_t len, uint32_t& w, uint32_t& h, std::vector<uint8_t>& rgba)` — macOS via ImageIO/`CGImageSource`, Windows keeps WIC. `WIC_LOADER_FORCE_RGBA32` => 4ch/8bpp -> `PixFmt::BGRA8_UNORM`; `WIC_LOADER_IGNORE_SRGB` => decode as raw UNORM (use `BGRA8_UNORM`, not `_SRGB`); swizzle R<->B in the CPU pack to land BGRA.
  - *Upload:* needs interface extension (see §4 G1).

**H2 — `D3DCompile` runtime fallback path. `Shader.cpp:131-132` guard, `141-190` body.**
`Create` calls `Compile()` when `VertexLength==0` (no precompiled bytecode). `D3DCompile`/`ID3DBlob`/`D3D_COMPILE_STANDARD_FILE_INCLUDE` are d3dcompiler-only. On macOS shaders are cross-compiled **offline** to MSL (SPIRV-Cross) and delivered as bytes, so `VertexLength` is always non-zero and the branch is dead. **Decision:** keep `Compile()` behind `#ifdef SG_WINDOWS` for the Win runtime path; in libsgcore the branch must be statically absent (and `assert(VertexLength != 0)` to catch a missing offline blob). `OutputDebugStringA` (`:161,181`) -> neutral log/`assert`. This is a build-config split, not a pure type swap.

**H3 — Swap-chain Present vs CAMetalLayer drawable lifetime. `ShaderGlass.cpp:136-141, 402-418`; `IRenderBackend.h:285-297`.**
D3D holds one persistent backbuffer (`GetBuffer(0)` once at init) reused every frame. Metal's `nextDrawable` is **per-frame and transient** — valid only until `Present`. The interface already models this (`BeginFrame()` returns a *borrowed* target valid only until Present). The engine change: `m_displayTexture`/`m_displayRenderTarget` stop being persistent members; the final pass must call `BeginFrame()` **every frame** and assign that into `m_shaderPasses[last].m_targetView` (`ShaderGlass.cpp:803`) per-frame, not once at setup. Risk: any code path that reads `m_displayTexture->GetDesc()` for sizing (`:910,1108`) must instead use a cached width/height or query the borrowed target — the drawable may not be acquirable at that point. Verify `BeginFrame` ordering relative to feedback/grab copies.

**H4 — `SetColorSpace1` / HDR colorspace re-assertion. `ShaderGlass.cpp:151-157, 333-342, 371-374`.**
The engine explicitly re-applies `DXGI_COLOR_SPACE_RGB_FULL_G10_NONE_P709` (scRGB-linear, NOT PQ/HDR10) after each `ResizeBuffers`. The interface folds this into `Initialize(hdr)` + a contract that `ResizeSwapChain` re-asserts it (`:274-278`). **Decision:** delete `SetSwapchainColorSpace()` and both members `m_swapChain3`/`m_swapChain` from the engine; the Metal backend must set `CAMetalLayer.wantsExtendedDynamicRangeContent=YES` + extended-linear colorspace AND re-apply it after `drawableSize` changes. This is correct but is a backend-implementation obligation, not engine code — flag it so the colorspace is not silently dropped on resize.

**H5 — CopyResource/CopySubresourceRegion ordering + the fractional-pixel clamp. `ShaderGlass.cpp:1093-1155` (feedback/history), `1108-1130` (boxed), `1199-1219` (GrabOutput).**
Two real subtleties beyond the `D3D11_BOX -> CopyOrigin/CopyExtent` swap:
  - **Self-referential ordering:** feedback copies read pass outputs written *this* frame and the history ring remaps `m_passResources` map entries (`:1144-1158`). On D3D the immediate context serializes these. On Metal a blit encoder must be sequenced **after** the render encoders that produced the sources — the backend must not reorder/coalesce across this boundary (the `:240` threading note says creation is observable to draws, but does not explicitly guarantee draw->blit->draw ordering across `CopyTexture`; confirm).
  - **GrabOutput fractional clamp (`:1117-1129`):** when `srcBox.right/bottom` exceeds the display extent it *shifts* `left/right` (and `top/bottom`) back by the overflow before copying. This logic must be replicated in the engine when building `CopyOrigin`/`CopyExtent` — it is NOT something `CopyTexture` does. Pure int math, but easy to drop.

**H6 — GrabOutput returns a GPU texture, not a readback. `ShaderGlass.cpp:1176-1230` (decl `ShaderGlass.h:46`).**
Confirmed: `GrabOutput` creates a `D3D11_USAGE_DEFAULT` texture (`:1196`) and copies into it — it is **not** CPU-readable staging; readback/PNG-encode happens downstream of the engine. So `GrabOutput` -> `sg::BackendTexture*` (caller owns, frees via `DestroyTexture`) is correct, but the **actual CPU readback is an unmodeled backend concern** (Metal: `[blit synchronizeResource]` + `getBytes:` off a `MTLStorageModeManaged`/shared texture). Decide whether GrabOutput's returned texture needs a CPU-visible storage flag — the current `TextureDesc` has no storage-mode field (see §4 G3).

**H7 — Injected window-geometry + cursor providers (capture/UI seam). `ShaderGlass.cpp:55-73, 467-549, 1026-1032`.**
`GetMonitorInfo`/`GetClientRect`/`ClientToScreen`/`GetWindowRect`/`DwmGetWindowAttribute(DWMWA_EXTENDED_FRAME_BOUNDS)`/`GetCursorInfo`/`HWND_BROADCAST` are not GPU calls and have no `IRenderBackend` mapping — they belong to a new injected `IWindowGeometry` provider (returns `sg::Rect`/`sg::Point`) and a cursor provider. The crop/box arithmetic itself is portable once `RECT`/`POINT` are structs. **Design needed:** the provider interface (methods, who owns it, macOS impl via ScreenCaptureKit + Quartz). Also `PostMessage(WM_PAINT/IDM_UPDATE_PARAMS)` (`:419` + resource.h notifications) -> injected `std::function` callbacks so the engine TU drops `resource.h`.

**H8 — `EndRenderPass` subsumes the unbind loop, but the cursor pass shares the target. `ShaderPass.cpp:362-369, 389-400`.**
Verified: `RenderCursor` (`:389-405`) does **not** open a fresh cleared pass — it reuses `m_targetView` (the display target, already written by the final pass) with blend on and `clear=false`, then restores blend off. Mapping to `BeginRenderPass(m_targetView,false,nullptr)` is only correct if the backend's `BeginRenderPass` with `loadAction=Load` preserves the prior pass's contents. On Metal, ending the final pass's encoder and starting a new `Load` encoder on the *same drawable texture* must preserve pixels — verify the Metal backend uses `loadAction=Load` (not Clear/DontCare) here. If the engine instead keeps the final pass open and draws the cursor into it, that changes the call structure. Decide: separate Load-pass (matches the interface) vs. same-encoder.

---

## 4. IRenderBackend.h GAPS to fix before the refactor

| Gap | Needed by | Proposed addition |
|---|---|---|
| **G1 — CPU->texture upload (CRITICAL).** No `initialData` on `CreateTexture` and no `UpdateTexture`. | `Texture.cpp:38-49` (preset LUT/image upload); the decoded-RGBA path | Add either `CreateTexture(const TextureDesc&, const void* initialData, size_t rowPitch)` (mirrors `CreateVertexBuffer`, cleanest) OR `void UpdateTexture(BackendTexture*, const void* data, size_t rowPitch)`. Metal: `[tex replaceRegion:mipmapLevel:withBytes:bytesPerRow:]`; D3D: `UpdateSubresource`. |
| **G2 — Image decode helper.** No decode anywhere (WIC was doing it). | `Texture.cpp`; preset images | Add free function `bool sg::DecodeImageRGBA(const uint8_t*, size_t, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra)` (ImageIO on mac, WIC on Win). Strictly *outside* `IRenderBackend` (it's a host helper, no GPU). Just declare it in the plan. |
| **G3 — Readback storage mode for GrabOutput.** `TextureDesc` has no CPU-visible/staging flag; `GrabOutput`'s texture and any PNG export need host-readable memory. | `ShaderGlass.cpp:1196` GrabOutput; screenshot/record feature | Either add `bool cpuReadable` to `TextureDesc`, or add an explicit `void ReadbackTexture(BackendTexture*, void* dst, size_t rowPitch)` verb. Without it, GrabOutput returns a GPU-only texture nobody can read on Metal. |
| **G4 — Clear-only pass vs. cull/rasterizer (NON-gap, document).** Engine does standalone `ClearRenderTargetView` (`:638,644,1018`) and one global `RSSetState` (no-cull/solid/no-depth, `:143-159`). | — | Already covered: `BeginRenderPass(target, clear=true, color)` + `EndRenderPass` = clear-only pass (`:427`); rasterizer invariant is baked into every PSO (`:348-354`). No interface change — but the Metal backend MUST honor `MTLCullModeNone` + no depth attachment. Flag as a backend test, not an interface gap. |
| **G5 — `CopyTexture` draw/blit ordering guarantee (clarify, maybe doc-only).** | H5 self-referential feedback/history copies | The threading note (`:240-243`) guarantees creation-before-draw but is silent on draw->`CopyTexture`->draw ordering. Add a one-line contract: "CopyTexture observes all prior draws into `source` and is observed by subsequent draws sampling `dest`." Prevents a Metal backend from reordering the blit. |

G1 and G3 are true API additions; G2 is a host helper to declare; G4/G5 are contract clarifications. **G1 blocks `Texture.cpp` (Phase 4) — extend the interface first.**

---

## 5. Clock-epoch shim (SG_TICKS) — exact coverage

**Shim:** `uint64_t sg::MonotonicMillis()` — ms since arbitrary epoch. macOS: `clock_gettime(CLOCK_MONOTONIC)` / `mach_absolute_time` (already implemented, `SCKCapture.mm:16`). Windows: wraps `GetTickCount64()`. Value semantics identical to `GetTickCount64` (monotonic, ms, wrap-safe for deltas). Define `#define SG_TICKS() sg::MonotonicMillis()` or call directly. Expose via `sg_clock.h` so engine TUs see it without capture/Windows headers.

**Every site it replaces (VERIFIED — the scans missed the two CaptureSession sites):**

| File:line | Context | Field type change |
|---|---|---|
| `ShaderGlass.cpp:83` | `m_prevTicks = GetTickCount64()` (init) | — |
| `ShaderGlass.cpp:84` | `m_startTicks = GetTickCount64()` (init) | — |
| `ShaderGlass.cpp:424` | `nowTicks` hot-path; logical-frame (16.6666) + input-timeout math | — |
| `ShaderGlass.cpp:652` | `m_startTicks` reset on preset/vertical change | — |
| `ShaderGlass.cpp:1165` | `m_prevRenderTicks`; 1000ms FPS delta | — |
| `CaptureSession.cpp:99` | `m_prevTicks = GetTickCount64()` | — |
| `CaptureSession.cpp:144` | `m_frameTicks = GetTickCount64()` | — |
| `ShaderGlass.h:95,98,99,100` | `m_startTicks, m_prevRenderTicks, m_prevTicks, m_prevFrameTicks` | `ULONGLONG -> uint64_t` |
| `ShaderGlass.h:32` (Process param) / `ShaderGlass.cpp:422` | `frameTicks` param | `ULONGLONG -> uint64_t` |
| `CaptureSession.h:58,61` | `m_frameTicks, m_prevTicks` | `ULONGLONG -> uint64_t` |

All arithmetic (FPS `deltaFrames*1000.0f/deltaTicks`, the `16.6666` logical-frame divisor) is plain `uint64_t`/`float` and is unchanged once the source/type are swapped. Note `SCKCapture.mm:152` already sets `f.frameTicks = sg::MonotonicMillis()` on the capture side, so the capture->`Process` seam is already consistent once `Process`'s param type flips to `uint64_t`.

**Relevant files (all absolute):** `/Users/ephem/lcode/ShaderGlass/mac/backend/IRenderBackend.h`, `/Users/ephem/lcode/ShaderGlass/mac/capture/SCKCapture.h` (clock decl :45), `/Users/ephem/lcode/ShaderGlass/mac/capture/SCKCapture.mm` (clock def :16), and the engine TUs under `/Users/ephem/lcode/ShaderGlass/ShaderGlass/` (`pch.h`, `framework.h`, `Shader.{h,cpp}`, `Texture.{h,cpp}`, `ShaderPass.{h,cpp}`, `Preset.{h,cpp}`, `ShaderGlass.{h,cpp}`, `CaptureSession.{h,cpp}`, `Options.h`). New files to create: `mac/backend/sg_geometry.h`, `mac/backend/sg_clock.h`, `ShaderGlass/sg_pch_portable.h`.