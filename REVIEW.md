# ShaderGlass macOS Port — Comprehensive Code Review

_Date: 2026-06-07. Scope: the entire `mac/` port tree. Method: five independent deep reviews
(backend, capture+threading, Windows-fidelity, build/security, and architecture/verification),
each read-only against the source, cross-checked and reconciled. Two critical findings were
re-verified directly against the code by the synthesizer._

---

## Executive summary

**Verdict: strong engineering with a sound, well-documented architecture and a genuinely working
live result — but the live capture path has two CRITICAL concurrency defects that must be fixed
before it can be trusted beyond a demo.**

The port's design is its best feature: a thin, backend-neutral `IRenderBackend` seam with an
exceptionally well-documented contract, a Metal implementation whose binding conventions were
adversarially verified pixel-perfect, and a clean separation that let a live GUI ship without the
full engine decouple. The offscreen/test paths are correct and the four regression suites are real.

The defects cluster entirely in the **newest, least-exercised code — the windowed present path and
its wiring to ScreenCaptureKit**. The single most important finding: the SCStream capture serial
queue and the AppKit main thread both call into one shared, lock-free `MetalBackend` state, and the
teardown path frees capture resources without draining in-flight frames. These are real races, not
theoretical — verified by inspection. They don't show up in the demo because the timing window is
small and the happy path dominates, but they will surface under resize-during-capture, stop/start
churn, and quit-while-capturing.

Nothing here undermines the milestone: **the port proved its thesis** (the Windows engine's rendering
semantics map faithfully to Metal, and a native macOS app can capture + shade live). The fixes below
are the difference between "verified demo" and "robust foundation."

### Severity tally

| Severity | Count | Where |
|---|---|---|
| Critical | 3 | capture/app threading (race, ring-safety premise, teardown UAF) |
| Major | 8 | backend present-path (const-buffer race, abandoned-frame leak, null deref, HDR gap), capture (blocking Start, device mismatch, resize), signing (trusted-root, key ACL, verify-masking) |
| Medium | ~6 | fidelity divergences (sampler filter, FrameCount clock, FIT-MVP), build (SDK path, cert-detection mismatch, reproducibility) |
| Minor / nit | ~15 | docs, fallbacks, cosmetics |

---

## 1. CRITICAL — must fix before trusting live capture

### C1. Data race: capture queue and main thread mutate the same `MetalBackend::Impl` concurrently
**Files:** `app/LivePipeline.mm:172-176` (`resizeToWidth:`), `:203-210` (`onCaptureFrameTex:`); shared
state at `backend/MetalBackend.mm:71-87`.

While capturing, the SCStream **serial queue** runs `onCaptureFrameTex` → `BeginFrame`/`drawSrc`/`Present`,
mutating `p->cb`, `p->enc`, `p->curDrawable`, `p->curFrameTarget`, `p->curTargetIsDrawable`,
`p->boundShader`, `p->curBlend`. Concurrently the **main thread** can enter the same backend:
- `resizeToWidth:` (from `SGMetalView` on live window resize / backing-scale change) calls
  `ResizeSwapChain` (mutates `CAMetalLayer.drawableSize` — not safe to reconfigure while `nextDrawable`
  runs on another thread) then `renderFrame`. **It has no `_capturing` guard at all** (verified:
  `LivePipeline.mm:172-176`).
- `setShaderKind:` calls `renderFrame`.
- `_capturing` is a **plain `bool`** read/written across threads with no atomic/lock/barrier.

The `renderFrame` `if (_capturing) return;` gate is itself an unsynchronized read, and `resizeToWidth`
bypasses it entirely. Two threads can be inside `BeginFrame`/`Present`/`ResizeSwapChain` at once —
`delete p->curFrameTarget` on one while the other dereferences it, concurrent `nextDrawable`, torn
`_dstW/_dstH` reads feeding the MVP/viewport. The backend's own interface promises a single render
thread (`IRenderBackend.h:243-246`); that promise is violated here.

**Fix:** pick one render thread and keep it. Simplest correct option: when capturing, marshal
`resizeToWidth`/`renderFrame`/shader-repaint onto the capture serial queue (`dispatch_async(p->queue, …)`),
and drive the static (non-capture) timer on that same queue. Make `_capturing` `std::atomic<bool>`
regardless. Only `_dstW/_dstH` mutation must move to the render thread.

### C2. The CVToMetal ring-depth safety argument rests on a `waitUntilCompleted` that does not happen on the live path
**Files:** ring rationale `capture/SCKCapture.mm:28-38, 88-95`; contradicting backend
`backend/MetalBackend.mm:159-172, 330-343`.

`CVToMetal`'s correctness comment is explicit: the depth-4 ref ring is safe because it is "combined
with the per-pass `waitUntilCompleted` in MetalBackend" (SCKCapture.mm:33-34, 89). **That wait does not
exist on the present path** — `EndRenderPass` returns early without committing when
`curTargetIsDrawable` (`MetalBackend.mm:335-338`), and `Present` commits with an explicit "NO
`waitUntilCompleted`" (`MetalBackend.mm:167`). The wait only runs on the offscreen branch the capture
path never takes.

So the true guarantee is only "a `CVMetalTextureRef` is released after 4 newer frames are *produced*,"
not "after the GPU finished sampling it." With `queueDepth=5` and `maximumDrawableCount=3`, depth-4 is
probably *empirically* adequate, but it is not *guaranteed* by the stated mechanism, and the comment
makes a false invariant look proven. Raise `queueDepth`, lower `RING_DEPTH`, or deepen the pipeline and
this silently becomes a read of a released IOSurface (tearing/corruption, not a clean crash).

**Fix:** tie the ref lifetime to actual GPU completion instead of a frame-count heuristic: `CFRetain`
the `cvtex` and release it in `[commandBuffer addCompletedHandler:^{ CFRelease(cvtex); }]`. That removes
the ring entirely. If the ring is kept, correct the comments to the real invariant and
`assert(RING_DEPTH > maximumDrawableCount)`.

### C3. Async-teardown use-after-free on Stop / shutdown / quit
**Files:** `app/LivePipeline.mm:212-215` (`stopCapture`), `:229-241` (`shutdown`); `capture/SCKCapture.mm:304-313`
(`Stop`).

`SCKCapture::Stop` calls `stopCaptureWithCompletionHandler:` (asynchronous — **returns immediately**,
the stream keeps delivering until it actually stops), then synchronously nils the delegate and runs
`conv.Flush()` — **with no barrier on the serial queue** (verified: there is no `dispatch_sync(p->queue,…)`).
A `didOutputSampleBuffer:` already dispatched (or mid-execution) can still be running `_sink` →
`onCaptureFrameTex` → `_backend.BeginFrame()` and holding a ring `id<MTLTexture>` while `Flush()`
`CFRelease`s the ring from the calling thread. `shutdown`/`dealloc` then `delete _capture`, and
`~SCKCapture` runs `Stop` again + `delete p`, destroying `p->conv`/`p->queue` while a frame may still
be in flight. The `__weak LivePipeline` guard protects the *Obj-C* call but **not** the C++
`CVToMetal`/`MetalBackend` raw-pointer access in the FrameSink (`SCKCapture.mm:138,146`). Classic
async-teardown UAF; also fires on quit (`applicationWillTerminate:` → `shutdown`).

**Fix:** make `Stop` synchronous w.r.t. the queue before freeing anything: after requesting stop,
`dispatch_sync(p->queue, ^{});` to flush any in-flight handler, **then** nil the delegate and `Flush`.
Do the same drain in `shutdown` before `delete _capture`. Do not rely on `__weak` alone.

> **Root cause of all three:** the capture serial queue and the main thread share lock-free backend
> state, and the documented serializing wait does not exist on the live path. Fixing the threading
> model (one owning render queue + synchronous teardown drain) resolves C1–C3 together.

---

## 2. MAJOR

### Backend present path
- **J1. Constant buffers are not ring-buffered; present path has no wait → CPU/GPU data race.**
  `UpdateConstantBuffer` memcpys into one shared `MTLBuffer` (`MetalBackend.mm:303-311`); the final
  (drawable) pass commits without waiting (`:167`). Frame N+1's UBO/Push write can race frame N's
  final-pass GPU read (same `ShaderPass` reused each frame). Invisible to the offscreen tests (masked
  by their wait). The interface even anticipated this (`IRenderBackend.h:416` "optionally
  ring-buffered"). **Fix:** ring the constant buffers (3 sub-regions, advance per frame, bind at
  offset — the `offset:` arg already exists), or gate frames-in-flight with a `dispatch_semaphore`
  signaled from a completion handler.
- **J2. Abandoned frame between `BeginFrame` and `Present` leaks `curFrameTarget` + starves the drawable
  pool.** `BeginFrame` does `p->curFrameTarget = new MTexture{…}` unconditionally without freeing a
  prior one (`MetalBackend.mm:155`); cleanup lives only in `Present`. If a frame is abandoned (early
  return, or loop back to `BeginFrame`), the next `BeginFrame` leaks the previous wrapper and the
  uncommitted `cb` keeps the drawable, so after ~3 the pool starves and `nextDrawable` blocks ~1s then
  nil. **Fix:** make `BeginFrame` self-clean (tear down any live target/drawable/cb at entry), or
  guarantee `Present` is always paired and `assert(curFrameTarget == nullptr)`.
- **J3. `BeginRenderPass` dereferences the target with no null check.** `t->tex` at
  `MetalBackend.mm:317` with no guard, but `BeginFrame` legitimately returns `nullptr` on a
  starved/timed-out drawable (`:152`). One missed caller guard → null deref crash; J2 can *cause* the
  nil. **Fix:** `if (!t) { p->enc=nil; p->cb=nil; return; }` and no-op the pass.
- **J4. `hdr=true` is silently ignored → SDR swap-chain contrary to the interface contract.**
  `(void)hdr` then unconditional `BGRA8Unorm` (`MetalBackend.mm:133-134`), but `IRenderBackend.h:263-268`
  requires `RGBA16_SFLOAT` + extended-range. A caller honoring the contract gets a silently-wrong
  result. **Fix:** implement the HDR branch, or make the gap loud (`fprintf` + documented) — don't
  silently drop a documented capability.
- **J5. `Draw` issues `drawPrimitives` even when PSO resolution failed** (`MetalBackend.mm:376-381`);
  also `psoFor` dereferences a null `boundShader` if `BindShader` was skipped. **Fix:** `if (!pso) return;`
  and guard `psoFor` against a null shader handle.

### Capture / app
- **J6. `SCKCapture::Start` blocks the calling thread up to 5s on a semaphore; called on the main
  thread.** `toggleCapture:` (button action, main) → `Start` → `getShareableContentWithCompletionHandler:`
  + `dispatch_semaphore_wait(…, 5s)` (`SCKCapture.mm:256-299`). Slow TCC = up to 5s beachball. The
  completion block also writes `p->stream` from the SCK queue, racing `Stop`/`SetCursorCapture` on main.
  **Fix:** make `Start` fully async (resolve filter + start stream in the completion handler, no
  semaphore), call back to main for UI state.
- **J7. Device mismatch: `CVToMetal` creates its own `MTLCreateSystemDefaultDevice`.**
  `SCKCapture.mm:240` makes a second device; the captured texture is then sampled on the backend's
  *different* device. Undefined on multi-GPU Macs (latent on single-GPU Apple Silicon). `NativeDevice()`
  exists precisely to share it but is never called. **Fix:** pass `MetalBackend::NativeDevice()` into
  `SCKCapture`/`CVToMetal`.
- **J8. Live resize is a no-paint and unsafe.** During capture, `resizeToWidth:` writes `_dstW/_dstH`
  from main and `renderFrame` early-returns (`_capturing`), so the resize visibly does nothing while
  the dimensions tear under the capture queue's read (`LivePipeline.mm:172-176`). Subsumed by C1's fix
  (marshal onto the render queue; next captured frame repaints).

### Build / signing (security)
- **S1. `add-trusted-cert -r trustAsRoot` installs a 10-year self-signed root — over-broad and
  ineffective for the goal.** `make-signing-cert.sh:34`. TCC keys off cdhash, **not** chain trust
  (build.sh:37-39 says so itself), so trusting the cert as a root buys nothing for grant-persistence
  while expanding the user's trust store. **Fix:** delete the `add-trusted-cert` line entirely; sign
  with the untrusted self-signed identity (sufficient for a stable cdhash).
- **S2. `security import … -A` grants every application access to the signing private key.**
  `make-signing-cert.sh:31`. `-A` = "all apps, no warning," broader than the `-T /usr/bin/codesign`
  already present. **Fix:** drop `-A`, rely on `-T`; if codesign then prompts, use
  `set-key-partition-list` scoped to `apple-tool:,apple:` rather than re-adding `-A`.
- **S3. `set -e` + `codesign --verify … | tail -2 || echo` masks a failed verification.**
  `build.sh:48`. zsh has no `pipefail` by default, so `$?` is `tail`'s (always 0) — the `|| echo`
  warning is dead, and a broken signature silently yields "built" (reintroducing the grant-resets
  problem the cert exists to prevent). Also violates the repo's non-destructive-logging rule (pipes to
  `tail` instead of persisting). **Fix:** `if ! codesign --verify --verbose=2 "$APP" 2>.logs/verify.log; then … exit 1; fi`.

---

## 3. FIDELITY to the Windows original (deliberate divergences + subtle risks)

The live path is a **single-pass reimplementation** that drives `MetalBackend` directly; it does not
run the Windows engine. Verified faithful where it counts; the divergences below are mostly deliberate
scope cuts, with two that are subtle visual/behavioral bugs.

**Verified faithful:**
- **Passthrough MSL == HLSL** (UBO/Push/`Source@2`, the `MVP*Position` no-transpose claim, Push byte
  offsets 0/16/32/48). `passthrough.metal` vs `PassthroughShaderDef.h`. The spike proved the
  no-transpose equivalence on hardware including an asymmetric+flip matrix.

**Subtle divergences worth fixing/flagging:**
- **D1 (medium, visible). Default sampler is `Linear`, but the engine default is `Nearest` (point).**
  `LivePipeline.mm:91` hard-codes `Filter::Linear`; the Windows passthrough uses
  `D3D11_FILTER_MIN_MAG_MIP_POINT` (`ShaderPass.cpp:64`) and the port's own `IRenderBackend.h:160,175`
  documents Nearest as the engine default. For FIT-scaled live view the macOS passthrough is
  bilinearly blurred where Windows shows crisp nearest-neighbor pixels — a real, shippable mismatch in
  the flagship "no shader" mode. The spike couldn't catch it (it rendered 1:1, where Nearest==Linear).
  **Fix:** default to `Nearest`; upgrade to `Linear` only when a preset's `filter_linear` says so.
- **D2 (medium). `FrameCount = inputFrameNo`, not the Windows 60Hz logical frame.** Windows feeds
  `logicalFrameNo = (now - start)/16.667` (`ShaderGlass.cpp:426`); the thin path uses the capture frame
  counter (`LivePipeline.mm:141,191`) and ignores `frameTicks`. SCK only delivers on change, so any
  FrameCount-animated shader **freezes over static content** on macOS (it keeps animating on Windows).
  Inert for the two shipped shaders (`crt_demo` doesn't read FrameCount); matters for real animated
  presets. **Fix (later, with the engine):** drive FrameCount from a monotonic 60Hz clock.
- **D3 (medium, edge). FIT-MVP is a different transform from the engine's crop/pan MVP.**
  `LivePipeline.mm:111-122` fits-and-centers the full source; Windows' preprocess `sx/sy/tx/ty`
  (`ShaderGlass.cpp:936-1010`) is a crop/pan/offset/locked-area transform with letterboxing done
  separately in box math. Equivalent only for the "show whole source, centered" case the GUI demoed;
  cannot reproduce pan/crop/offset/clone-from-origin. Deliberate scope cut; the `LivePipeline.mm:109-110`
  comment overstates the correspondence (**D3b, minor:** note crop/pan/flip are dropped).

**Silent gaps (expected for the thin path, listed for honesty):** multi-pass chains, feedback,
history (`OriginalHistoryN`), preprocess crop/pan/locked-area, cursor overlay (the `AlphaOver` blend
PSO exists but is never invoked), per-pass `scale_type`, sRGB/float intermediate framebuffers, HDR,
flip/rotate, frame-skip, `framecount_mod`, preset static-texture samplers. All live in the Windows
engine that M0b will bring over.

**crt_demo.metal** is correctly labeled an original CRT approximation, NOT a port of crt-geom /
crt-easymode. Real RetroArch-shader parity is unverified by design (deferred to M4 codegen).

---

## 4. Architecture, verification & documentation (synthesizer assessment)

**Architecture — excellent.** The `IRenderBackend` seam is the right abstraction: backend-neutral
(no `windows.h`/`d3d11`/`winrt`), opaque handles, a documented binding contract, and a format-agnostic
lazy PSO cache. It let a live GUI ship while the 10k-line engine decouple (M0b) stays deferred —
exactly the staged de-risking the plan intended. The "thin path drives MetalBackend directly" decision
is sound and clearly bounded. No over-engineering observed; the code is appropriately minimal.

**Verification — unusually rigorous for the offscreen surface, honest about the live boundary.**
The M-1 spike's 5 discriminating cases (axis-swap, flip, anisotropic, half-texel, sRGB) and the
byte-identical `--selftest`-vs-demo-golden check are strong, CI-safe evidence for the binding
contract. The reviews confirm the offscreen/test paths are correct. The gap — acknowledged in the
docs — is that **no automated test exercises the live present path or the threading model**; the
concurrency defects (C1–C3, J1) live precisely in that untested region, which is why they survived to
this review. A ThreadSanitizer build and a resize-during-capture stress test would have caught them.

**Documentation — a genuine strength, with a few overclaims.** `IRenderBackend.h`'s contract,
`STATUS.md`/`ROADMAP.md`/`RUNNING.md`, `M0b-migration-map.md`, and the inline rationale (the
cdhash/TCC reasoning, the LibreSSL-vs-OpenSSL p12 gotcha) are well above average and capture the
non-obvious traps. Overclaims to correct: (a) `CVToMetal`'s "per-pass wait" comment is false on the
live path (C2); (b) the "verified pixel-perfect" framing is accurate but narrow — it covers the
binding contract, not whole-engine parity, sampler filter, or threading; (c) the FIT/FILL comment
(D3b). None are dishonest — the code generally scopes its claims — but a reader could mistake
binding-contract verification for live-path verification.

---

## 5. Build / reproducibility (remaining mediums + nits)

- **B1 (medium). Hardcoded Xcode SDK path** in all six build scripts (`/Applications/Xcode.app/.../MacOSX.sdk`)
  breaks on Xcode move/rename/CLT-only and drifts six ways. **Fix:** `SDK="$(xcrun --sdk macosx --show-sdk-path)"`
  or compile via `xcrun clang++` and drop `-isysroot`; ideally a shared `mac/common.sh`.
- **B2 (medium). `make-signing-cert.sh` detects the cert with `-v` but `build.sh` uses non-`-v`** — a
  cert build.sh considers usable makes the cert script print `WARN: not valid` and, on re-run, attempt
  a duplicate import. **Fix:** use the same non-`-v` detection in both.
- **B3 (medium). Not clone-and-build self-contained:** `deps/` (arm64 glslang + SPIRV-Cross) is
  gitignored and built by an out-of-tree procedure; the cert is a manual one-time step; GPU/clang/git
  need the sandbox disabled here. **Fix:** a `mac/README.md` listing prerequisites + a `deps/build_deps.sh`
  pinned to known revisions.
- **Nits:** add `-Wall -Wextra` (no warning flags today); add `*.p12 *.pem *.cer *.keychain*` to
  `.gitignore` as defense against accidental key commits; `--selftest` input paths are CWD-coupled
  (reuse the bundle-Resources resolution `SGAppDelegate` already has); `CFBundleIconFile` absent
  (cosmetic); redundant `= nil` before `delete` under ARC; `toMTL` default arm silently maps Unknown →
  BGRA8 (log it); `SetVertexBuffer` logs an unexpected stride but proceeds.

---

## 6. Prioritized fix list

**Before trusting live capture beyond a demo (do together — one root cause):**
1. **C1 + C3 + J8** — establish ONE render thread: marshal all `MetalBackend`-touching calls
   (resize, static render, shader repaint) onto the capture serial queue while capturing; make
   `_capturing` atomic; add a `dispatch_sync(p->queue, ^{})` teardown drain in `Stop`/`shutdown`
   before freeing.
2. **C2 + J1** — fix resource lifetime under the no-wait present: release CVMetalTextureRefs via a
   command-buffer completion handler (drop the frame-count ring), and ring the constant buffers (or
   gate frames-in-flight with a semaphore). Land these together since both stem from "no wait on
   present."
3. **J2 + J3** — make `BeginFrame`/`Present` robust to abandoned frames; null-guard `BeginRenderPass`.

**Correctness / fidelity (next):**
4. **D1** — default sampler `Nearest` (matches the engine; fixes the blurry passthrough).
5. **J7** — share the one `MTLDevice` with `CVToMetal`.
6. **J6** — make `SCKCapture::Start` async (kill the 5s main-thread stall).
7. **J5, J4** — guard PSO-failure draws; make the HDR gap loud or implemented.

**Security / build (cheap, high value):**
8. **S1, S2, S3** — drop `add-trusted-cert` and `-A`; fix the `codesign --verify` masking.
9. **B1, B2, B3** — SDK via `xcrun`; unify cert detection; add a prerequisites README + deps build script.

**Later (with the engine — M0b):** D2 (FrameCount clock), D3 (real preprocess crop/pan), and the
whole silent-gap list (multi-pass/feedback/history/cursor/scale_type/sRGB-float/HDR).

---

## 7. What this review could NOT assess

- **Live timing behavior:** the hit-rate of the C1/C3/J1 races and the empirical sufficiency of the
  depth-4 ring need a ThreadSanitizer build + Metal API validation + a resize-during-capture stress
  run on device. The defects are real **by inspection**; their frequency is not measurable here.
- **The `deps/` build** (glslang + SPIRV-Cross) was out of the read set — assessed only via
  `check_msl.cpp` + the migration notes.
- **Whether every `.mm` compiles clean under these exact flags** — verified framework/source
  correspondence by reading, did not re-run `clang++` for this review (the suites were last built green).
- **Notarization/distribution** — explicitly out of scope; the hardened-runtime notes are forward-looking.

---

## Bottom line

The macOS port is **architecturally sound, well-documented, and demonstrably works live** — a real
achievement from a Windows-only DirectX 11 codebase. The offscreen foundation is verified and trustworthy.
The live capture path, being the newest code, carries three critical concurrency defects (all from one
root cause: shared lock-free backend state across the capture queue and main thread, plus a no-wait
present that invalidates a documented safety assumption) and a handful of major present-path and signing
issues. **None block the milestone or the roadmap; all are fixable with a focused threading-model pass.**
Fix the threading (C1–C3, J1) and the sampler default (D1), and this moves from "verified demo" to
"robust base for the M0b engine decouple."
