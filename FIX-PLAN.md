# ShaderGlass macOS Port — Fix Plan

_Remediation plan for the findings in `REVIEW.md`. Ordered by risk: the three critical
concurrency defects first (they share one root cause and one fix pass), then majors, then
fidelity/build hygiene. Each phase lists concrete edits, code sketches, and how to verify._

**Guiding constraint:** the offscreen path (used by `backend_test`, `capture_test`, `demo`,
`--selftest`) is correct and must stay byte-identical. Every change is gated so the offscreen
path is untouched; the three regression suites + the golden selftest are the regression gate
after each phase. GPU/clang builds run with the command sandbox disabled (see `RUNNING.md`).

Tracked as tasks #8 (Phase 1), #9 (Phase 2), #10 (Phases 3-4).

---

## Phase 1 — Threading model (CRITICAL: C1, C3, J8) — task #8

**Root cause:** the SCStream capture serial queue and the AppKit main thread both call into one
lock-free `MetalBackend::Impl`, and teardown frees capture resources without draining in-flight
frames. **Fix:** establish ONE owning render thread (the capture serial queue while capturing;
the main thread otherwise) and make teardown synchronous.

### 1a. Make `_capturing` atomic and route all backend access onto one queue

`app/LivePipeline.mm`:
- Change `bool _capturing;` → `std::atomic<bool> _capturing;` (already `#include <atomic>`).
- Add an ivar for the capture queue handle so the pipeline can dispatch onto it:
  expose `SCKCapture`'s serial queue (add `dispatch_queue_t SCKCapture::Queue()` returning
  `p->queue`), or have `LivePipeline` own the queue and pass it into `SCKCapture`. Prefer the
  latter — `LivePipeline` is the render owner.
- Wrap the three main-thread entry points so that **while capturing** they marshal onto the
  render queue, and while not capturing they run inline (main thread is the render thread then):

```objc
// helper
- (void)runOnRenderThread:(dispatch_block_t)block {
    if (_capturing.load() && _renderQueue) dispatch_async(_renderQueue, block);
    else block();  // not capturing: main thread owns the backend
}

- (void)resizeToWidth:(uint32_t)w height:(uint32_t)h {
    [self runOnRenderThread:^{
        _dstW = w; _dstH = h;          // now only mutated on the render thread
        _backend.ResizeSwapChain(w, h);
        if (!_capturing.load()) [self renderFrameLocked];  // capture path repaints on next frame
    }];
}
- (void)setShaderKind:(SGShaderKind)kind {
    _activeShader.store(kind == SGShaderCRT ? _shaderCRT : _shaderPassthrough); // already atomic, fine from any thread
    [self runOnRenderThread:^{ if (!_capturing.load()) [self renderFrameLocked]; }];
}
```

- The 30fps static `tick`/`renderFrame` already runs on the main thread; that's correct *when not
  capturing*. Guard it: `if (_capturing.load()) return;` with the atomic. When capturing, the
  capture queue is the sole driver, so the timer must not also render — the atomic gate makes that
  race-free.
- `_dstW/_dstH` become render-thread-only. `onCaptureFrameTex` already runs on the capture queue,
  so its `_dstW/_dstH` reads are now safe.

**Note on `CAMetalLayer` thread-safety:** `nextDrawable` and `drawableSize` are documented safe
off the main thread *as long as one thread owns them*. Routing both onto the capture queue while
capturing satisfies that. Layer *creation* stays on the main thread (`SGMetalView`), unchanged.

### 1b. Synchronous teardown drain (C3)

`capture/SCKCapture.mm` `Stop()` — drain the serial queue before freeing:
```objc
void SCKCapture::Stop() {
    if (@available(macOS 12.3, *)) {
        if (p->stream) {
            dispatch_semaphore_t stopped = dispatch_semaphore_create(0);
            [p->stream stopCaptureWithCompletionHandler:^(NSError*) { dispatch_semaphore_signal(stopped); }];
            dispatch_semaphore_wait(stopped, dispatch_time(DISPATCH_TIME_NOW, 2*NSEC_PER_SEC));
            p->stream = nil;
        }
        if (p->queue) dispatch_sync(p->queue, ^{});  // flush any in-flight didOutputSampleBuffer
        p->delegate = nil;
        p->conv.Flush();      // now safe: no frame can be mid-flight
    }
}
```
- `LivePipeline shutdown` already calls `stopCapture` before `delete _capture` — once `Stop` drains
  synchronously, the `delete` is safe. Keep that order.
- Guard against `Stop` being called from the capture queue itself (a `didStopWithError` path) — a
  `dispatch_sync` onto the current serial queue would deadlock. Check
  `dispatch_get_specific`/a "on-queue" flag, or only ever call `Stop` from the main thread (it is,
  today: `toggleCapture:` / `applicationWillTerminate:`). Document the precondition.

### 1c. `renderFrame` refactor

Split `renderFrame` into a thread-naive `renderFrameLocked` (does the actual Begin/Draw/Present,
assumes it's on the render thread) and the public `renderFrame` that gates on `_capturing` + routes.
`onCaptureFrameTex` calls the locked form directly (already on the render queue).

### Phase 1 verification
- Build the app (`app/build.sh`), run under `MTL_DEBUG_LAYER=1` — no validation errors.
- **ThreadSanitizer build:** add a `-fsanitize=thread` variant of `app/build.sh`; launch, start
  capture, resize the window repeatedly, toggle shader, Stop/Start several times, quit while
  capturing. TSan must report zero races on the backend `Impl` fields. This is the definitive check
  for C1/C3 — the race is real by inspection but only TSan/load proves the fix.
- Regression: `backend/build_test.sh`, `capture/build_test.sh`, `demo/build.sh` still PASS
  (offscreen path untouched).

---

## Phase 2 — No-wait-present resource lifetime (CRITICAL C2 + MAJOR J1/J2/J3) — task #9

**Root cause:** `Present` commits without `waitUntilCompleted`, so resources the GPU still reads
(captured IOSurface, constant buffers) must stay alive via completion tracking, not frame-count
heuristics — and the drawable/target wrappers must survive abandoned frames.

### 2a. Tie CVMetalTextureRef lifetime to GPU completion (C2)

`capture/SCKCapture.mm` — replace the depth-4 frame-count ring with completion-handler release:
- `CFRetain(cvtex)` when wrapping; release it in the command buffer's completion handler. But
  `CVToMetal` doesn't see the command buffer. Two options:
  1. **Preferred:** keep the ring but make the depth contractually correct:
     `static_assert/assert(RING_DEPTH > maxInFlight)` where `maxInFlight == maximumDrawableCount`
     (3), so depth-4 is provably > in-flight, and **correct the comment** to state the real
     invariant (release trails production by RING_DEPTH > frames-in-flight, bounded by drawable
     pool — NOT "after the GPU wait", which doesn't happen). Low-risk, keeps the current structure.
  2. **Cleaner:** have `MetalBackend::Present` accept an optional "on GPU complete" hook, and have
     the FrameSink release the frame's CVMetalTextureRef there. More plumbing; defer unless option 1
     proves insufficient under load.
- Decision: ship option 1 (assert + corrected comment) now; revisit option 2 only if the TSan/load
  test in Phase 1 or a deep-pipeline stress shows tearing.

### 2b. Ring the constant buffers (J1)

`backend/MetalBackend.mm` — the UBO/Push `MTLBuffer`s are written every frame with no wait on the
present path. Give each a small ring:
- In `CreateConstantBuffer`, allocate `N * roundedSize` (N = `maximumDrawableCount` = 3) in one
  `MTLBuffer` (respect 256-byte constant-buffer offset alignment on Apple GPUs — round each slot up
  to 256).
- Track a per-frame ring index advanced in `BeginFrame` (e.g. `p->frameRing = (p->frameRing+1)%N`).
- `UpdateConstantBuffer` writes at `slot = frameRing * stride`; `BindConstantBuffer` binds at that
  `offset:` (the `offset:` arg already exists in the Metal calls).
- This is only needed for the present (in-flight) path; the offscreen path waits, so a single slot
  is fine — but ringing unconditionally is simpler and harmless. Keep the `size <= buf.length`
  guard relative to the *slot* stride.
- Pair with 2a: both are "present has no wait" hazards; land together.

### 2c. `BeginFrame` self-clean + null-guard (J2, J3)

`backend/MetalBackend.mm`:
```objc
BackendTexture* MetalBackend::BeginFrame() {
    if (!p->layer) return nullptr;
    // self-clean: an abandoned prior frame (BeginFrame without Present) must not leak.
    if (p->curFrameTarget) { delete p->curFrameTarget; p->curFrameTarget = nullptr; }
    if (p->cb) { p->cb = nil; }          // drop any uncommitted drawable cb
    p->curDrawable = nil;
    p->curDrawable = [p->layer nextDrawable];
    if (!p->curDrawable) return nullptr;
    p->curFrameTarget = new MTexture{ p->curDrawable.texture, false };
    return reinterpret_cast<BackendTexture*>(p->curFrameTarget);
}
```
`BeginRenderPass` — guard the null target (J3):
```objc
void MetalBackend::BeginRenderPass(BackendTexture* target, bool clear, const float c[4]) {
    auto* t = reinterpret_cast<MTexture*>(target);
    if (!t) { p->enc = nil; p->cb = nil; p->curTargetIsDrawable = false; return; }
    ...
}
```
Make `Draw`/`SetViewport`/etc. tolerate a nil `enc` (already safe via ObjC nil-messaging; confirm
no C++ deref). Add an assert in `BeginRenderPass` that a live drawable `cb` doesn't already exist
(catches the order-fragility noted in REVIEW finding 7).

### 2d. `Draw` PSO-failure guard (J5)

`backend/MetalBackend.mm` `Draw`:
```objc
void* pso = psoFor(p->boundShader, (uint32_t)p->curTargetFmt, p->curBlend);
if (!pso) return;   // logged in psoFor; do not draw with stale/no pipeline
[p->enc setRenderPipelineState:(__bridge id<MTLRenderPipelineState>)pso];
[p->enc drawPrimitives:...];
```
Also null-guard `psoFor` against a null `boundShader`.

### Phase 2 verification
- Same TSan + resize/stop-start/quit stress as Phase 1, now with a **frame-pacing stress**: capture
  a fast-changing source (e.g. a video) at small `maximumDrawableCount`, watch for tearing/garbage
  (the C2/J1 symptom) under Metal API validation.
- Confirm `BeginFrame` abandonment doesn't starve the pool: artificially force `Present` to be
  skipped for a few frames in a debug build, confirm no 1s `nextDrawable` stall and no leak (Instruments Allocations).
- Regression suites green.

---

## Phase 3 — Correctness & fidelity (MAJOR/MEDIUM: D1, J7, J6, J4) — task #10

### 3a. Default sampler Nearest, not Linear (D1 — visible bug)
`app/LivePipeline.mm:91` — change `CreateSampler(SamplerDesc{Filter::Linear, Wrap::Border})` to
`Filter::Nearest` to match the Windows engine default (`ShaderPass.cpp:64`) and the port's own
`IRenderBackend.h` annotation. This makes passthrough show crisp pixels like Windows instead of
bilinear blur. (When the real engine lands, the per-preset `filter_linear` flag drives this; for the
thin path, Nearest is the correct default. CRT shader can keep its own linear sampling if desired —
but it currently uses the same shared sampler, so consider a second linear sampler only if the CRT
visibly needs it.)

### 3b. Share the one MTLDevice with CVToMetal (J7)
`capture/SCKCapture.mm:240` — instead of `MTLCreateSystemDefaultDevice()`, take the device from the
backend. Add a device param to `SCKCapture` ctor (or `Start`), source it from
`MetalBackend::NativeDevice()` (already exists), `__bridge`-cast at the call site. Latent on
single-GPU Apple Silicon but incorrect; cheap to fix.

### 3c. Make SCKCapture::Start async (J6 — 5s main-thread stall)
`capture/SCKCapture.mm:256-299` — remove the `dispatch_semaphore_wait`; resolve the
`SCContentFilter` and start the stream inside the `getShareableContentWithCompletionHandler:`
block, then call back to the caller (a completion block) for UI state. `SGAppDelegate toggleCapture:`
updates the Start/Stop button title in that callback on the main thread. Removes the beachball and
the `p->stream` cross-thread write race.

### 3d. HDR gap: make it loud (J4)
`backend/MetalBackend.mm:133` — `if (hdr) fprintf(stderr, "MetalBackend: HDR requested but not
implemented; using SDR BGRA8\n");` so a contract-honoring caller isn't silently wrong. (Full EDR
implementation is deferred with the engine.)

### Phase 3 verification
- Visual: passthrough now matches Windows nearest-neighbor look (compare against a Windows
  screenshot or the demo at a scaled size).
- Start no longer blocks: time `toggleCapture:` — returns immediately, button updates async.
- Regression suites green (note: changing the thin-path default sampler does NOT affect
  `backend_test`/`demo`, which construct their own samplers).

---

## Phase 4 — Build / signing / security hygiene (S1, S2, S3, B1, B2, B3) — task #10

### 4a. Signing security (S1, S2)
`app/make-signing-cert.sh`:
- **Delete the `add-trusted-cert -r trustAsRoot` step** (S1) — it installs a 10-year self-signed
  root, is over-broad, and buys nothing for TCC (which keys on cdhash, not chain trust).
- **Drop `-A` from `security import`** (S2) — rely on `-T /usr/bin/codesign`. If codesign then
  prompts, use `security set-key-partition-list -S apple-tool:,apple: -s -k <pw> "$LOGIN_KC"`
  scoped to the tool, not all apps.
- Change the cert-existence check (line 12, 38) to the non-`-v` form to match `build.sh` (B2) so a
  re-run is a true no-op and never duplicate-imports.

### 4b. build.sh verify masking (S3)
`app/build.sh:48` — replace `codesign --verify ... | tail -2 || echo` with a status-checked form
that persists full output to `.logs/` and fails the build on a bad signature:
```zsh
if ! codesign --verify --verbose=2 "$APP" 2>.logs/codesign-verify.log; then
    echo "ERROR: codesign --verify failed:" >&2; cat .logs/codesign-verify.log >&2; exit 1
fi
```

### 4c. SDK path via xcrun (B1)
All six build scripts — replace the hardcoded
`SDK="/Applications/Xcode.app/.../MacOSX.sdk"` with `SDK="$(xcrun --sdk macosx --show-sdk-path)"`,
or compile via `xcrun clang++` and drop `-isysroot`. Best: a shared `mac/common.sh` sourced by all
scripts (single source of `SDK`/`CXX`/flags), eliminating six-way drift. Add `-Wall -Wextra` there.

### 4d. Reproducibility (B3)
- Add `mac/README.md` (or fold into `RUNNING.md`) listing prerequisites: Xcode + CLT, the `deps/`
  glslang+SPIRV-Cross build procedure, `make-signing-cert.sh` as the optional grant-persistence step,
  and the sandbox-disabled requirement on this machine.
- Add `deps/build_deps.sh` that clones + builds glslang + SPIRV-Cross at pinned revisions (the
  invocations are recorded in `deps/.logs/`), so `deps/` is reproducible rather than tribal knowledge.
- Add `*.p12 *.pem *.cer *.keychain*` to `.gitignore` as defense against accidental key commits.

### Phase 4 verification
- `make-signing-cert.sh` run twice is a clean no-op the second time; `codesign --sign ShaderGlassDev`
  still succeeds; a deliberately-corrupted bundle now fails `build.sh` loudly.
- `build.sh` works on a machine where Xcode is at a non-default path (or simulate by overriding
  `DEVELOPER_DIR`).
- Fresh-clone dry run of the README steps reaches a launchable app.

---

## Phase 5 — Test coverage for the live path (prevents regressions of C1-C3/J1)

The criticals survived because **no automated test exercises the live present path or threading**.
Add:
- A `-fsanitize=thread` build variant of `app/build.sh` and a scripted stress (`app/stress.sh`):
  launch with an env flag that auto-starts capture on the main display, programmatically resize the
  window N times, toggle shader, Stop/Start, quit — under TSan + `MTL_DEBUG_LAYER`. CI-runnable on a
  machine with a granted TCC permission (document it can't run in the sandbox/headless).
- A backend unit test for the present path that does NOT need a window: feed a stub layer or assert
  the `BeginFrame`/`Present` self-clean + ring-index advance invariants directly.
- Keep the `--selftest` golden as the offscreen regression anchor.

---

## Execution order & checkpoints

1. **Phase 1** (threading) + **Phase 2** (lifetime) — land together; they're the same root cause and
   share the TSan/stress verification. This is the must-do block before trusting live capture.
   Commit: "Fix live-capture threading and present-path resource lifetime (REVIEW C1-C3, J1-J3, J5)".
2. **Phase 3** (fidelity/correctness) — independent, smaller. Commit separately.
3. **Phase 4** (build/security) — independent, no GPU. Commit separately.
4. **Phase 5** (test coverage) — fold the TSan/stress harness in with Phase 1-2; the rest can trail.

After all phases: re-run the four regression suites + the new stress harness, update `STATUS.md`
(move the criticals to "fixed + how verified"), and mark tasks #8/#9/#10 complete.

**Out of scope here (tracked elsewhere):** the fidelity SILENT-GAPS (multi-pass, feedback, history,
cursor, scale_type, sRGB/float intermediates, HDR, flip/rotate, FrameCount 60Hz clock) and real
RetroArch-shader parity — those require the M0b engine decouple (task #5) and M4 codegen, per
`ROADMAP.md`. They are deliberate thin-path scope cuts, not bugs.
