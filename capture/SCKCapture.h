/*
ShaderGlass macOS port -- SCKCapture.h

ScreenCaptureKit-based capture, the macOS replacement for the WinRT
Windows.Graphics.Capture path in CaptureSession.cpp. Captures a window or display
into a zero-copy MTLTexture and feeds it through the engine's Process() seam:

  Win32 seam (CaptureSession.cpp:111-171):
    OnFrameArrived -> grab ID3D11Texture2D, track content-size change
    OnInputFrame   -> m_frameTicks = GetTickCount64(); m_numInputFrames++
    ProcessInput   -> m_shaderGlass.Process(texture, frameTicks, numInputFrames)

  macOS seam (this file):
    stream:didOutputSampleBuffer: -> CMSampleBuffer -> CVPixelBuffer (IOSurface)
      -> CVMetalTextureCache (zero-copy) -> id<MTLTexture>
      -> IRenderBackend::WrapNativeFrame
    -> FrameSink::OnFrame(backendTexture, frameTicks, inputFrameNo)

The frame-counter + tick clock are owned here (mirroring CaptureSession's
m_numInputFrames / m_frameTicks): inputFrameNo drives the engine's dedup, frameTicks
(ms, from a monotonic mach clock) drives the ~20ms staleness allowance and the
FrameCount uniform.

Requires macOS 12.3+. Screen Recording is TCC-gated (no entitlement; the app needs
NSScreenCaptureUsageDescription and the user grant). The CVPixelBuffer->MTLTexture
conversion (the bug-prone, testable core) lives in CVToMetal below and is unit-tested
headlessly without any capture permission.
*/

#pragma once

#include "../backend/IRenderBackend.h"
#include <cstdint>
#include <functional>

#ifdef __OBJC__
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#endif

namespace sg {

// Monotonic milliseconds since an arbitrary epoch (mach_absolute_time based).
// Replaces GetTickCount64 in the capture path; see CaptureSession::OnInputFrame.
uint64_t MonotonicMillis();

// Converts an IOSurface-backed CVPixelBuffer (BGRA) to a zero-copy MTLTexture via a
// CVMetalTextureCache. This is the load-bearing capture-path step and is testable
// without screen-recording permission (synthesize a CVPixelBuffer, convert, sample).
class CVToMetal
{
public:
    CVToMetal();
    ~CVToMetal();

#ifdef __OBJC__
    bool Initialize(id<MTLDevice> device);
    // Returns an id<MTLTexture> aliasing the pixel buffer's IOSurface (BGRA8Unorm).
    // The backing CVMetalTextureRef is parked in an internal ring (depth >= the
    // SCStream queueDepth) so the IOSurface stays pinned while in-flight frames are
    // sampled; a ref is only released after RING_DEPTH newer frames arrive. Returns
    // nil on failure (incl. a non-32BGRA pixel buffer). Callers must still complete
    // GPU sampling within the same render-thread turn (see SCKCapture threading
    // contract); the ring protects against frame-pipelining, not arbitrary retention.
    id<MTLTexture> TextureFromPixelBuffer(CVPixelBufferRef pb);
    void           Flush();
#endif

private:
    struct Impl;
    Impl* p;
};

// What a capture source delivers per frame. The macOS analog of the single
// Process(texture, frameTicks, inputFrameNo) call.
struct CaptureFrame
{
    BackendTexture* texture;      // WrapNativeFrame'd, borrowed for the call
    uint32_t        width;
    uint32_t        height;
    uint64_t        frameTicks;   // monotonic ms
    uint64_t        inputFrameNo; // monotonic counter
};

using FrameSink = std::function<void(const CaptureFrame&)>;

// What to capture. Mirrors the engine's desktop-clone vs window-clone choice.
enum class CaptureTargetKind { Display, Window };

struct CaptureTarget
{
    CaptureTargetKind kind = CaptureTargetKind::Display;
    uint32_t          id   = 0; // CGDirectDisplayID for Display, CGWindowID for Window
};

// Live ScreenCaptureKit capture session. The permission-gated counterpart to
// CaptureSession's WinRT path. Owns the SCStream, the CVToMetal converter, and the
// frame-counter/clock; delivers frames to the sink. Functional run needs a TCC
// Screen Recording grant + a real display, so this is structurally complete but
// not headless-verifiable (the CVToMetal core IS verified by capture_test).
class SCKCapture
{
public:
    SCKCapture(IRenderBackend* backend, FrameSink sink);
    ~SCKCapture();

    // Enumerate capturable displays/windows (async TCC; invokes cb on the main queue).
    // cb receives false if the user has not granted Screen Recording.
    static void QueryShareableContent(std::function<void(bool granted)> cb);

    // Start capturing the given target at maxCaptureRate (mirrors MinUpdateInterval).
    // Returns false synchronously only on gross misconfiguration; permission denial
    // surfaces via the stream delegate's didStopWithError.
    bool Start(const CaptureTarget& target, bool maxCaptureRate, bool captureCursor);
    void Stop();

    // Toggle cursor capture (mirrors CaptureSession::UpdateCursor).
    void SetCursorCapture(bool enabled);

    // The last delivered content size (for the engine's resize path).
    void ContentSize(uint32_t& w, uint32_t& h) const;

private:
    struct Impl;
    Impl* p;
};

} // namespace sg
