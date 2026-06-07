/*
ShaderGlass macOS port -- SCKCapture.mm

CVToMetal (testable headless) + the SCStream wrapper (permission-gated).
*/

#import <Metal/Metal.h>
#import <CoreVideo/CoreVideo.h>
#import <mach/mach_time.h>
#include "SCKCapture.h"
#include <cstdio>

namespace sg {

// ---------------------------------------------------------------------------
uint64_t MonotonicMillis() {
    static mach_timebase_info_data_t tb = {0, 0};
    if (tb.denom == 0) mach_timebase_info(&tb);
    uint64_t ns = mach_absolute_time() * tb.numer / tb.denom;
    return ns / 1000000ull;
}

// ---------------------------------------------------------------------------
struct CVToMetal::Impl {
    id<MTLDevice>          device = nil;
    CVMetalTextureCacheRef cache  = nullptr;
    // Ring of CVMetalTextureRefs (NOT a single slot): the MTLTexture returned by
    // CVMetalTextureGetTexture only keeps its IOSurface pinned while its
    // CVMetalTextureRef is alive. With frames in flight (SCStream queueDepth >= 2,
    // mirroring the Windows depth-2 frame pool) a single slot would release the
    // surface of a frame the GPU is still sampling. We keep RING_DEPTH refs alive,
    // releasing each only after RING_DEPTH newer frames have been produced -- which,
    // combined with the per-pass waitUntilCompleted in MetalBackend, guarantees the
    // GPU finished sampling a frame before its ref is reclaimed.
    static constexpr int RING_DEPTH = 4;
    CVMetalTextureRef     ring[RING_DEPTH] = {nullptr};
    int                   ringPos = 0;
};

CVToMetal::CVToMetal() : p(new Impl) {}
CVToMetal::~CVToMetal() {
    if (p) {
        for (int i = 0; i < Impl::RING_DEPTH; ++i)
            if (p->ring[i]) CFRelease(p->ring[i]);
        if (p->cache) CFRelease(p->cache);
        p->device = nil;
        delete p; p = nullptr;
    }
}

bool CVToMetal::Initialize(id<MTLDevice> device) {
    p->device = device;
    CVReturn r = CVMetalTextureCacheCreate(kCFAllocatorDefault, nullptr, device, nullptr, &p->cache);
    if (r != kCVReturnSuccess) {
        fprintf(stderr, "CVToMetal: CVMetalTextureCacheCreate failed (%d)\n", r);
        return false;
    }
    return true;
}

id<MTLTexture> CVToMetal::TextureFromPixelBuffer(CVPixelBufferRef pb) {
    if (!pb || !p->cache) return nil;

    // Defensive: the BGRA8Unorm cache call below silently fails on YUV/10-bit
    // buffers. SCStreamConfiguration.pixelFormat is pinned to 32BGRA, but guard
    // against a misconfigured stream rather than dropping frames opaquely.
    OSType pf = CVPixelBufferGetPixelFormatType(pb);
    if (pf != kCVPixelFormatType_32BGRA) {
        fprintf(stderr, "CVToMetal: unexpected pixel format 0x%08x (expected 32BGRA)\n", (unsigned)pf);
        return nil;
    }

    size_t w = CVPixelBufferGetWidth(pb);
    size_t h = CVPixelBufferGetHeight(pb);

    // Request BGRA8Unorm (NOT _sRGB): the engine samples the captured frame as raw
    // UNORM, matching the D3D B8G8R8A8_UNORM capture path. sRGB applies only on
    // intermediate passes that declare srgb_framebuffer.
    CVMetalTextureRef cvtex = nullptr;
    CVReturn r = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault, p->cache, pb, nullptr,
        MTLPixelFormatBGRA8Unorm, w, h, 0, &cvtex);
    if (r != kCVReturnSuccess || !cvtex) {
        fprintf(stderr, "CVToMetal: CreateTextureFromImage failed (%d)\n", r);
        if (cvtex) CFRelease(cvtex);
        return nil;
    }
    // Park the ref in the ring; release the entry RING_DEPTH frames old (its GPU
    // work has long completed under the per-pass wait). Keeps in-flight frames pinned.
    if (p->ring[p->ringPos]) CFRelease(p->ring[p->ringPos]);
    p->ring[p->ringPos] = cvtex;
    p->ringPos = (p->ringPos + 1) % Impl::RING_DEPTH;

    return CVMetalTextureGetTexture(cvtex);
}

void CVToMetal::Flush() {
    for (int i = 0; i < Impl::RING_DEPTH; ++i)
        if (p->ring[i]) { CFRelease(p->ring[i]); p->ring[i] = nullptr; }
    p->ringPos = 0;
    if (p->cache) CVMetalTextureCacheFlush(p->cache, 0);
}

} // namespace sg

// ---------------------------------------------------------------------------
// SCStream wrapper. Compiled only when ScreenCaptureKit is available (macOS 12.3+).
// The frame-callback -> content-size -> counter/clock -> WrapNativeFrame -> sink
// pipeline mirrors CaptureSession::OnFrameArrived/OnInputFrame/ProcessInput. This
// part is permission-gated (TCC Screen Recording) and not headless-testable, so it
// is kept thin and delegates all the testable work to CVToMetal above.

#if __has_include(<ScreenCaptureKit/ScreenCaptureKit.h>)
#import <ScreenCaptureKit/ScreenCaptureKit.h>

API_AVAILABLE(macos(12.3))
@interface SGCaptureDelegate : NSObject <SCStreamOutput, SCStreamDelegate>
@end

@implementation SGCaptureDelegate {
@public
    sg::CVToMetal*           _conv;
    sg::IRenderBackend*      _backend;
    sg::FrameSink            _sink;
    uint64_t                 _frameNo;
    uint32_t                 _lastW, _lastH;
}

- (void)stream:(SCStream*)stream
    didOutputSampleBuffer:(CMSampleBufferRef)sb
                   ofType:(SCStreamOutputType)type API_AVAILABLE(macos(12.3))
{
    if (type != SCStreamOutputTypeScreen) return;
    if (!CMSampleBufferIsValid(sb)) return;
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sb);
    if (!pb) return;

    id<MTLTexture> mtl = _conv->TextureFromPixelBuffer(pb);
    if (!mtl) return;

    uint32_t w = (uint32_t)CVPixelBufferGetWidth(pb);
    uint32_t h = (uint32_t)CVPixelBufferGetHeight(pb);
    _lastW = w; _lastH = h; // content-size tracking (SCK reconfig handled by caller)

    sg::TextureDesc td{ w, h, sg::PixFmt::BGRA8_UNORM, false };
    sg::BackendTexture* bt = _backend->WrapNativeFrame((__bridge void*)mtl, td);

    sg::CaptureFrame f;
    f.texture      = bt;
    f.width        = w;
    f.height       = h;
    f.frameTicks   = sg::MonotonicMillis(); // mirrors OnInputFrame m_frameTicks
    f.inputFrameNo = ++_frameNo;            // mirrors m_numInputFrames++
    if (_sink) _sink(f);

    _backend->DestroyTexture(bt); // releases the wrapper, not the IOSurface
}

- (void)stream:(SCStream*)stream didStopWithError:(NSError*)error API_AVAILABLE(macos(12.3)) {
    fprintf(stderr, "SCKCapture: stream stopped: %s\n", error.localizedDescription.UTF8String);
}
@end
#endif // ScreenCaptureKit available (delegate block)

// ---------------------------------------------------------------------------
// SCKCapture -- live SCStream session.
//
// THREADING CONTRACT (mirrors the IRenderBackend single-render-thread invariant,
// IRenderBackend.h): the SCStream sample handler runs on ONE serial dispatch queue,
// and that queue IS the render thread. The sink (the engine's Process) runs to
// completion synchronously on it -- including all MetalBackend draw/readback -- and
// nothing else may touch the backend. This makes the per-frame
// WrapNativeFrame -> sink -> DestroyTexture lifetime correct: the borrowed
// BackendTexture is valid only for the synchronous sink() call, and the CVToMetal
// ring keeps the IOSurface pinned across the SCStream queueDepth. A separate
// present thread would require a wake primitive (mirroring the Win32 m_frameEvent)
// AND cross-thread retention of the CVMetalTextureRef -- explicitly out of scope here.
namespace sg {

struct SCKCapture::Impl {
    IRenderBackend* backend = nullptr;
    FrameSink       sink;
    CVToMetal       conv;
#if __has_include(<ScreenCaptureKit/ScreenCaptureKit.h>)
    SCStream*           stream   = nil;
    SGCaptureDelegate*  delegate = nil;
    dispatch_queue_t    queue    = nil;
    bool                maxRate  = false;
    bool                cursor   = false;
#endif
};

SCKCapture::SCKCapture(IRenderBackend* backend, FrameSink sink) : p(new Impl) {
    p->backend = backend;
    p->sink    = std::move(sink);
}

SCKCapture::~SCKCapture() {
    if (p) { Stop(); delete p; p = nullptr; }
}

void SCKCapture::ContentSize(uint32_t& w, uint32_t& h) const {
#if __has_include(<ScreenCaptureKit/ScreenCaptureKit.h>)
    if (@available(macOS 12.3, *)) {
        if (p->delegate) { w = p->delegate->_lastW; h = p->delegate->_lastH; return; }
    }
#endif
    w = 0; h = 0;
}

#if __has_include(<ScreenCaptureKit/ScreenCaptureKit.h>)

void SCKCapture::QueryShareableContent(std::function<void(bool)> cb) {
    if (@available(macOS 12.3, *)) {
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* c, NSError* e) {
            bool granted = (c != nil && e == nil); // TCC denial surfaces as SCStreamErrorUserDeclined
            dispatch_async(dispatch_get_main_queue(), ^{ cb(granted); });
        }];
    } else {
        cb(false);
    }
}

// Build an SCStreamConfiguration with the format/colorspace pinned to match the
// engine's raw-BGRA-UNORM sampling contract (review finding: never rely on defaults).
static SCStreamConfiguration* makeConfig(uint32_t w, uint32_t h, bool maxRate, bool cursor) API_AVAILABLE(macos(12.3)) {
    SCStreamConfiguration* cfg = [[SCStreamConfiguration alloc] init];
    cfg.pixelFormat = kCVPixelFormatType_32BGRA;        // matches CVToMetal BGRA8Unorm
    cfg.colorSpaceName = kCGColorSpaceSRGB;             // pin; unset => display colorspace (P3/EDR) divergence
    if (w) cfg.width = w;
    if (h) cfg.height = h;
    cfg.showsCursor = cursor;
    cfg.queueDepth = 5;                                 // > CVToMetal ring is sized for this
    cfg.minimumFrameInterval = CMTimeMake(1, maxRate ? 250 : 60); // mirrors 4ms / 15ms MinUpdateInterval
    return cfg;
}

bool SCKCapture::Start(const CaptureTarget& target, bool maxCaptureRate, bool captureCursor) {
    if (@available(macOS 12.3, *)) {
        if (!p->conv.Initialize(MTLCreateSystemDefaultDevice())) return false;
        p->maxRate = maxCaptureRate;
        p->cursor  = captureCursor;
        if (!p->queue)
            p->queue = dispatch_queue_create("net.shaderglass.capture", DISPATCH_QUEUE_SERIAL);

        p->delegate = [SGCaptureDelegate new];
        p->delegate->_conv    = &p->conv;
        p->delegate->_backend = p->backend;
        p->delegate->_sink    = p->sink;
        p->delegate->_frameNo = 0;
        p->delegate->_lastW = p->delegate->_lastH = 0;

        // Re-query the shareable content to resolve the target into an SCContentFilter.
        // (Synchronous resolution would be cleaner with a cached snapshot from
        // QueryShareableContent; re-querying keeps Start self-contained.)
        __block bool started = false;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        CaptureTarget t = target;
        IRenderBackend* backend = p->backend;
        (void)backend;
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* content, NSError* e) {
            if (!content || e) { dispatch_semaphore_signal(done); return; }
            SCContentFilter* filter = nil;
            uint32_t cw = 0, ch = 0;
            if (t.kind == CaptureTargetKind::Display) {
                for (SCDisplay* d in content.displays) {
                    if (d.displayID == (CGDirectDisplayID)t.id) {
                        filter = [[SCContentFilter alloc] initWithDisplay:d excludingWindows:@[]];
                        cw = (uint32_t)d.width; ch = (uint32_t)d.height;
                        break;
                    }
                }
            } else {
                for (SCWindow* win in content.windows) {
                    if (win.windowID == (CGWindowID)t.id) {
                        filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:win];
                        cw = (uint32_t)win.frame.size.width; ch = (uint32_t)win.frame.size.height;
                        break;
                    }
                }
            }
            if (!filter) { dispatch_semaphore_signal(done); return; }

            SCStreamConfiguration* cfg = makeConfig(cw, ch, p->maxRate, p->cursor);
            NSError* se = nil;
            p->stream = [[SCStream alloc] initWithFilter:filter configuration:cfg delegate:p->delegate];
            [p->stream addStreamOutput:p->delegate type:SCStreamOutputTypeScreen
                     sampleHandlerQueue:p->queue error:&se];
            if (se) { fprintf(stderr, "SCKCapture: addStreamOutput failed: %s\n", se.localizedDescription.UTF8String);
                      p->stream = nil; dispatch_semaphore_signal(done); return; }
            [p->stream startCaptureWithCompletionHandler:^(NSError* err) {
                if (err) fprintf(stderr, "SCKCapture: startCapture failed: %s\n", err.localizedDescription.UTF8String);
            }];
            started = true;
            dispatch_semaphore_signal(done);
        }];
        // bounded wait for filter resolution (the async getShareableContent)
        dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        return started;
    }
    return false; // SCK requires 12.3+
}

void SCKCapture::Stop() {
    if (@available(macOS 12.3, *)) {
        if (p->stream) {
            [p->stream stopCaptureWithCompletionHandler:^(NSError*) {}];
            p->stream = nil;
        }
        p->delegate = nil;
        p->conv.Flush();
    }
}

void SCKCapture::SetCursorCapture(bool enabled) {
    if (@available(macOS 12.3, *)) {
        if (!p->stream) return;
        p->cursor = enabled;
        uint32_t w = 0, h = 0; ContentSize(w, h);
        SCStreamConfiguration* cfg = makeConfig(w, h, p->maxRate, enabled);
        [p->stream updateConfiguration:cfg completionHandler:^(NSError* e) {
            if (e) fprintf(stderr, "SCKCapture: updateConfiguration failed: %s\n", e.localizedDescription.UTF8String);
        }];
    }
}

#else // no ScreenCaptureKit (< macOS 12.3) -- fallback so the engine still links

void SCKCapture::QueryShareableContent(std::function<void(bool)> cb) { cb(false); }
bool SCKCapture::Start(const CaptureTarget&, bool, bool) {
    fprintf(stderr, "SCKCapture: ScreenCaptureKit unavailable (requires macOS 12.3+)\n");
    return false;
}
void SCKCapture::Stop() {}
void SCKCapture::SetCursorCapture(bool) {}

#endif // ScreenCaptureKit available

} // namespace sg
