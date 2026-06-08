# ShaderGlass macOS Port — Status

_Native macOS / Apple Silicon port of [mausimus/ShaderGlass](https://github.com/mausimus/ShaderGlass),
a Windows DirectX 11 + Win32 RetroArch shader overlay. All port work lives under `mac/`; the
upstream Windows tree is untouched._

**Current headline: a native macOS app captures a live window/display and renders it through a
Metal shader (passthrough or a hand-ported CRT) in a resizable GUI. Visually confirmed on an
Apple M3 Max.**

---

## What works today (verified on hardware)

| Layer | State | Evidence |
|---|---|---|
| Metal pass mapping (D3D11→Metal) | ✅ verified | `spike/` — 5 discriminating cases incl. asymmetric+flip MVP, sRGB encode; 0-LSB diffs |
| arm64 glslang + SPIRV-Cross (MSL) | ✅ built | `deps/check_msl.cpp` links `CompilerMSL`, emits MSL |
| `IRenderBackend` + `MetalBackend` | ✅ verified | `backend/backend_test.mm` — passthrough through the interface, format-agnostic PSO cache, G1/G3 verbs, all 0-LSB |
| Capture core (`CVToMetal`) | ✅ verified | `capture/capture_test.mm` — CVPixelBuffer→zero-copy MTLTexture, 6-frame ring stress |
| Windowed present path | ✅ verified | app runs 4s under `MTL_DEBUG_LAYER` with zero validation errors |
| **Live GUI (capture → shader → screen)** | ✅ **confirmed live** | user screenshot: iTerm2 window captured live with CRT applied, correct aspect/orientation |
| Offscreen golden render | ✅ byte-identical | `app/build.sh selftest` output == `demo/out/passthrough.png` |

### The "thin live path" (what the GUI actually is)

The live app (`mac/app/`) drives `MetalBackend` **directly** — it does NOT use the full ShaderGlass
engine. It is a single-shader-pass pipeline:

```
SCKCapture (ScreenCaptureKit)
  → CVToMetal (CVPixelBuffer → zero-copy MTLTexture, depth-4 ref ring)
  → MetalBackend.WrapNativeFrame
  → ONE shader pass (passthrough or crt_demo) into the CAMetalLayer drawable
  → present
```

This deliberately bypasses the engine's multi-pass / feedback / history / preprocess machinery so we
could reach a live window now. Those features require the full engine, which is still
Windows-coupled (see `ROADMAP.md` → M0b).

---

## Component map (`mac/`)

```
mac/
  backend/
    IRenderBackend.h     backend-neutral GPU interface (no windows.h/d3d11/winrt)
    MetalBackend.h/.mm    Metal implementation; windowed present path + offscreen path
    sg_geometry.h         portable Rect/Point (Win32 RECT/POINT replacements)
    sg_clock.h            SG_TICKS() monotonic-ms shim (GetTickCount64 on Win / MonotonicMillis on mac)
    sg_image.h/.mm        ImageIO PNG decode/encode (the WIC replacement, BGRA8)
    backend_test.mm       conformance test (offscreen, pixel-diff)
    build_test.sh         build+run backend_test
  capture/
    SCKCapture.h/.mm      ScreenCaptureKit wrapper + CVToMetal converter + frame seam
    capture_test.mm       headless capture-core test (no TCC needed)
    build_test.sh
  spike/
    passthrough.metal     hand-ported MSL (UBO{MVP}@0, Push@1, Source@2 layout)
    crt_demo.metal        hand-ported CRT (curvature + scanlines + mask + vignette)
    main.mm, build.sh     M-1 standalone Metal-mapping proof
  demo/
    demo.mm, build.sh     PNG → pipeline → PNG (offscreen visible proof; writes demo/out/*.png)
  app/                    ← THE LIVE GUI
    main.mm               NSApplication bootstrap; --selftest offscreen golden path
    SGAppDelegate.h/.mm    window + control bar (Target/Shader/Start/Rescan) + capture control
    SGMetalView.h/.mm      NSView whose backing layer is a CAMetalLayer (HiDPI-correct resize)
    LivePipeline.h/.mm     the single renderer: owns MetalBackend + SCKCapture; the only Begin/Draw/Present site
    Info.plist            bundle id net.shaderglass.mac, NSScreenCaptureUsageDescription
    build.sh              compile + assemble + sign ShaderGlass.app
    make-signing-cert.sh  one-time: create the persistent ShaderGlassDev signing cert
  deps/                   arm64 glslang + SPIRV-Cross checkouts + build (gitignored; check_msl.cpp tracked)
  M0b-migration-map.md    exhaustive plan to decouple the engine from Windows (the big next step)
  STATUS.md / ROADMAP.md / RUNNING.md  (this set)
```

---

## Key invariants & decisions (do not silently break these)

- **Binding contract (verified):** UBO=`buffer(0)`, Push=`buffer(1)` (both VS+FS stages), geometry
  vertex buffer=`buffer(30)` (must not alias 0/1), `Source` tex+sampler=slot 2, vertex stride 24B
  (float4 pos@0 + float2 uv@16), triangle-strip start-vertex 4.
- **MVP: no transpose.** The engine's row-major `float[4][4]` bytes load straight into an MSL
  column-major `float4x4`; `MVP * Position` == HLSL `mul(Position, row_major MVP)`. Proven for
  asymmetric matrices, not just identity.
- **Color: BGRA8Unorm (NON-sRGB) end-to-end**, with `CAMetalLayer.colorspace = sRGB`. The engine's
  `sFormats` maps the SPIR-V name `R8G8B8A8_UNORM` to a **BGRA** layout — map by layout, not name.
- **`EndRenderPass` split:** drawable target → defer commit to `Present()` (no `waitUntilCompleted`);
  offscreen target → commit+wait (unchanged, so the 3 test suites stay green). Gated by
  `curTargetIsDrawable`, set in `BeginRenderPass` by pointer-identity vs the `BeginFrame` target.
- **Threading:** the SCStream sample queue IS the render thread; the FrameSink renders+presents
  synchronously on it, wrapped in `@autoreleasepool`. Layer creation + `drawableSize` mutation stay
  on the main thread.
- **CVToMetal ref ring depth (4) ≥ in-flight frames.** The no-wait present path relies on the ring +
  command-buffer resource retention to keep the captured IOSurface alive while the GPU samples it.

## Environment gotchas

- **GPU/Metal + clang + git-clone require the command sandbox disabled** on this machine
  (`MTLCreateSystemDefaultDevice` returns nil; clang `xcrun_db` cache write denied). See memory note
  `shaderglass-sandbox-metal`.
- **TCC Screen Recording grant keys to the binary's cdhash.** Ad-hoc signing churns the cdhash every
  rebuild → grant silently breaks. Fixed by the persistent `ShaderGlassDev` cert. See `RUNNING.md`
  and memory note `shaderglass-macos-tcc-signing`.
- SDK path (xcrun is flaky in-sandbox): `-isysroot /Applications/Xcode.app/.../MacOSX.sdk`.
