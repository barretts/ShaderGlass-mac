/*
ShaderGlass macOS port -- main.mm

NSApplication bootstrap. Normal launch opens the live GUI. `--selftest <out.png>`
runs headless: builds the pipeline against a layer-less backend, renders the sample
image offscreen through passthrough, and writes a PNG (auto-verifiable golden,
never touches a drawable / TCC).
*/

#import <Cocoa/Cocoa.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import "SGAppDelegate.h"
#import "LivePipeline.h"
#include "../backend/sg_image.h"
#include <algorithm>
#include <climits>
#include <vector>

using namespace sg;

static long maxChannelDiff(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
    if (a.size() != b.size()) return LONG_MAX;
    long maxd = 0;
    for (size_t i = 0; i < a.size(); ++i)
        maxd = std::max(maxd, labs((long)a[i] - (long)b[i]));
    return maxd;
}

static long columnMaxDiff(const std::vector<uint8_t>& a,
                          const std::vector<uint8_t>& b,
                          uint32_t w,
                          uint32_t h,
                          uint32_t x) {
    if (a.size() != b.size() || x >= w) return LONG_MAX;
    long maxd = 0;
    for (uint32_t y = 0; y < h; ++y) {
        size_t base = ((size_t)y * w + x) * 4;
        for (size_t c = 0; c < 4; ++c)
            maxd = std::max(maxd, labs((long)a[base + c] - (long)b[base + c]));
    }
    return maxd;
}

static int runSelftest(NSString* outPath) {
    @autoreleasepool {
        NSString* res = [[NSBundle mainBundle] resourcePath];
        NSFileManager* fm = [NSFileManager defaultManager];
        BOOL bundled = res && [fm fileExistsAtPath:[res stringByAppendingPathComponent:@"passthrough.metal"]];
        NSString* shaderDir = bundled ? res : @"../spike";
        NSString* img = bundled ? [res stringByAppendingPathComponent:@"screen6.png"]
                                : @"../../images/screen6.png";
        // layer-less pipeline (Initialize(nil) => headless backend, present path inert)
        LivePipeline* pipe = [[LivePipeline alloc] initWithLayer:nil width:0 height:0 shaderDir:shaderDir];
        if (!pipe) { fprintf(stderr, "selftest FAIL: pipeline init (shaderDir=%s)\n", shaderDir.UTF8String); return 2; }
        if (![pipe setStaticImagePath:img]) { fprintf(stderr, "selftest FAIL: image load (%s)\n", img.UTF8String); return 2; }
        if (![pipe renderOffscreenToPNG:outPath]) { fprintf(stderr, "selftest FAIL: offscreen render\n"); return 1; }
        fprintf(stderr, "selftest OK: wrote %s\n", outPath.UTF8String);
        return 0;
    }
}

static NSString* defaultRenderImagePath(void) {
    NSString* res = [[NSBundle mainBundle] resourcePath];
    NSFileManager* fm = [NSFileManager defaultManager];
    BOOL bundled = res && [fm fileExistsAtPath:[res stringByAppendingPathComponent:@"passthrough.metal"]];
    return bundled ? [res stringByAppendingPathComponent:@"screen6.png"]
                   : @"../../images/screen6.png";
}

static int runPresetRenderWithImage(NSString* presetID, NSString* imagePath, NSString* outPath) {
    @autoreleasepool {
        NSString* res = [[NSBundle mainBundle] resourcePath];
        NSFileManager* fm = [NSFileManager defaultManager];
        BOOL bundled = res && [fm fileExistsAtPath:[res stringByAppendingPathComponent:@"passthrough.metal"]];
        NSString* shaderDir = bundled ? res : @"../spike";
        LivePipeline* pipe = [[LivePipeline alloc] initWithLayer:nil width:0 height:0 shaderDir:shaderDir];
        if (!pipe) {
            fprintf(stderr, "preset-render FAIL: pipeline init (shaderDir=%s)\n", shaderDir.UTF8String);
            return 2;
        }
        if (![pipe setStaticImagePath:imagePath]) {
            fprintf(stderr, "preset-render FAIL: image load (%s)\n", imagePath.UTF8String);
            return 2;
        }
        if (![pipe setShaderPresetIdentifier:presetID]) {
            fprintf(stderr, "preset-render FAIL: preset not found (%s)\n", presetID.UTF8String);
            return 3;
        }
        if (![pipe renderOffscreenToPNG:outPath]) {
            fprintf(stderr, "preset-render FAIL: offscreen render (%s)\n", presetID.UTF8String);
            return 1;
        }
        fprintf(stderr, "preset-render OK: %s -> %s\n", presetID.UTF8String, outPath.UTF8String);
        return 0;
    }
}

static int runPresetRender(NSString* presetID, NSString* outPath) {
    return runPresetRenderWithImage(presetID, defaultRenderImagePath(), outPath);
}

static int runRenderAllPresetsWithImage(NSString* imagePath, NSString* outDir) {
    @autoreleasepool {
        NSFileManager* fm = [NSFileManager defaultManager];
        NSError* mkdirError = nil;
        if (![fm createDirectoryAtPath:outDir withIntermediateDirectories:YES attributes:nil error:&mkdirError]) {
            fprintf(stderr, "render-all FAIL: mkdir %s (%s)\n",
                    outDir.UTF8String,
                    mkdirError.localizedDescription.UTF8String);
            return 4;
        }
        NSArray<SGShaderPresetDescriptor*>* catalog = [LivePipeline shaderPresetCatalog];
        for (SGShaderPresetDescriptor* descriptor in catalog) {
            NSString* outPath = [outDir stringByAppendingPathComponent:[descriptor.identifier stringByAppendingString:@".png"]];
            int rc = runPresetRenderWithImage(descriptor.identifier, imagePath, outPath);
            if (rc != 0) return rc;
        }
        fprintf(stderr, "render-all OK: wrote %lu preset renders to %s\n",
                (unsigned long)catalog.count,
                outDir.UTF8String);
        return 0;
    }
}

static int runRenderAllPresets(NSString* outDir) {
    return runRenderAllPresetsWithImage(defaultRenderImagePath(), outDir);
}

static int runSplitSelftest(NSString* outPath) {
    @autoreleasepool {
        NSString* res = [[NSBundle mainBundle] resourcePath];
        NSFileManager* fm = [NSFileManager defaultManager];
        BOOL bundled = res && [fm fileExistsAtPath:[res stringByAppendingPathComponent:@"passthrough.metal"]];
        NSString* shaderDir = bundled ? res : @"../spike";
        NSString* img = bundled ? [res stringByAppendingPathComponent:@"screen6.png"]
                                : @"../../images/screen6.png";
        LivePipeline* pipe = [[LivePipeline alloc] initWithLayer:nil width:0 height:0 shaderDir:shaderDir];
        if (!pipe) { fprintf(stderr, "split-selftest FAIL: pipeline init (shaderDir=%s)\n", shaderDir.UTF8String); return 2; }
        if (![pipe setStaticImagePath:img]) { fprintf(stderr, "split-selftest FAIL: image load (%s)\n", img.UTF8String); return 2; }

        NSString* outDir = [outPath stringByDeletingLastPathComponent];
        NSString* outStem = [[outPath lastPathComponent] stringByDeletingPathExtension];
        NSString* originalPath = [outDir stringByAppendingPathComponent:[outStem stringByAppendingString:@"-original.png"]];
        NSString* processedPath = [outDir stringByAppendingPathComponent:[outStem stringByAppendingString:@"-processed.png"]];
        NSString* splitZeroPath = [outDir stringByAppendingPathComponent:[outStem stringByAppendingString:@"-split0.png"]];
        NSString* splitHundredPath = [outDir stringByAppendingPathComponent:[outStem stringByAppendingString:@"-split100.png"]];

        uint32_t w = 0, h = 0;
        std::vector<uint8_t> sourcePixels;
        if (!DecodeImageFileBGRA(img.UTF8String, w, h, sourcePixels) || !w || !h) {
            fprintf(stderr, "split-selftest FAIL: could not decode source pixels\n");
            return 2;
        }

        [pipe setCompareMode:SGCompareModeOff];
        [pipe setShaderPresetIdentifier:@"passthrough"];
        if (![pipe renderOffscreenToPNG:originalPath]) { fprintf(stderr, "split-selftest FAIL: original render\n"); return 1; }

        [pipe setShaderPresetIdentifier:@"crt"];
        if (![pipe renderOffscreenToPNG:processedPath]) { fprintf(stderr, "split-selftest FAIL: processed render\n"); return 1; }

        [pipe setCompareMode:SGCompareModeSplit];
        [pipe setCompareSplitPosition:0.0f];
        if (![pipe renderOffscreenToPNG:splitZeroPath]) { fprintf(stderr, "split-selftest FAIL: split 0 render\n"); return 1; }

        [pipe setCompareSplitPosition:0.5f];
        if (![pipe renderOffscreenToPNG:outPath]) { fprintf(stderr, "split-selftest FAIL: split 50 render\n"); return 1; }

        [pipe setCompareSplitPosition:1.0f];
        if (![pipe renderOffscreenToPNG:splitHundredPath]) { fprintf(stderr, "split-selftest FAIL: split 100 render\n"); return 1; }

        std::vector<uint8_t> originalPixels, processedPixels, splitZeroPixels, splitFiftyPixels, splitHundredPixels;
        uint32_t ow = 0, oh = 0, pw = 0, ph = 0, zW = 0, zH = 0, fW = 0, fH = 0, hW = 0, hH = 0;
        if (!DecodeImageFileBGRA(originalPath.UTF8String, ow, oh, originalPixels) ||
            !DecodeImageFileBGRA(processedPath.UTF8String, pw, ph, processedPixels) ||
            !DecodeImageFileBGRA(splitZeroPath.UTF8String, zW, zH, splitZeroPixels) ||
            !DecodeImageFileBGRA(outPath.UTF8String, fW, fH, splitFiftyPixels) ||
            !DecodeImageFileBGRA(splitHundredPath.UTF8String, hW, hH, splitHundredPixels)) {
            fprintf(stderr, "split-selftest FAIL: could not decode rendered outputs\n");
            return 1;
        }
        if (ow != w || oh != h || pw != w || ph != h || zW != w || zH != h || fW != w || fH != h || hW != w || hH != h) {
            fprintf(stderr, "split-selftest FAIL: unexpected output dimensions\n");
            return 1;
        }

        long splitZeroDiff = maxChannelDiff(splitZeroPixels, processedPixels);
        if (splitZeroDiff != 0) {
            fprintf(stderr, "split-selftest FAIL: split 0 does not match processed baseline (max=%ld)\n", splitZeroDiff);
            return 1;
        }

        uint32_t leftColumn = std::max<uint32_t>(1, w / 4);
        uint32_t rightColumn = std::min<uint32_t>(w - 2, (w * 3) / 4);
        uint32_t nearRightEdge = std::max<uint32_t>(1, w - 3);
        long originalProcessedLeft = columnMaxDiff(originalPixels, processedPixels, w, h, leftColumn);
        long originalProcessedRight = columnMaxDiff(originalPixels, processedPixels, w, h, rightColumn);
        if (originalProcessedLeft == 0 && originalProcessedRight == 0) {
            fprintf(stderr, "split-selftest FAIL: processed baseline is not distinguishable from original at sample columns\n");
            return 1;
        }

        long splitLeftDiff = columnMaxDiff(splitFiftyPixels, originalPixels, w, h, leftColumn);
        if (splitLeftDiff != 0) {
            fprintf(stderr, "split-selftest FAIL: split 50 left column does not match original (max=%ld)\n", splitLeftDiff);
            return 1;
        }
        long splitRightDiff = columnMaxDiff(splitFiftyPixels, processedPixels, w, h, rightColumn);
        if (splitRightDiff != 0) {
            fprintf(stderr, "split-selftest FAIL: split 50 right column does not match processed (max=%ld)\n", splitRightDiff);
            return 1;
        }
        long splitHundredDiff = columnMaxDiff(splitHundredPixels, originalPixels, w, h, nearRightEdge);
        if (splitHundredDiff != 0) {
            fprintf(stderr, "split-selftest FAIL: split 100 interior column does not match original (max=%ld)\n", splitHundredDiff);
            return 1;
        }

        [fm removeItemAtPath:originalPath error:nil];
        [fm removeItemAtPath:processedPath error:nil];
        [fm removeItemAtPath:splitZeroPath error:nil];
        [fm removeItemAtPath:splitHundredPath error:nil];
        fprintf(stderr, "split-selftest OK: wrote %s\n", outPath.UTF8String);
        return 0;
    }
}

static void runLoopUntil(NSTimeInterval seconds, BOOL (^done)(void)) {
    NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!done() && [deadline timeIntervalSinceNow] > 0) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
}

static NSString* shaderDirForCommandLine() {
    NSString* res = [[NSBundle mainBundle] resourcePath];
    NSFileManager* fm = [NSFileManager defaultManager];
    if (res && [fm fileExistsAtPath:[res stringByAppendingPathComponent:@"passthrough.metal"]])
        return res;
    return @"../spike";
}

static BOOL shouldUseWindowForSmoke(SCWindow* window) API_AVAILABLE(macos(12.3)) {
    if (!window) return NO;
    if (!window.title.length || window.frame.size.width < 64 || window.frame.size.height < 64) return NO;
    NSString* appName = window.owningApplication.applicationName ?: @"";
    NSString* bundleID = window.owningApplication.bundleIdentifier ?: @"";
    if ([window.title localizedCaseInsensitiveContainsString:@"Fullscreen Backdrop"]) return NO;
    if ([window.title localizedCaseInsensitiveContainsString:@"Wallpaper"]) return NO;
    if ([appName localizedCaseInsensitiveContainsString:@"WindowManager"]) return NO;
    if ([appName localizedCaseInsensitiveContainsString:@"Dock"]) return NO;
    if ([bundleID isEqualToString:@"com.apple.WindowManager"]) return NO;
    if ([bundleID isEqualToString:@"com.apple.dock"]) return NO;
    return YES;
}

static int runCaptureSmoke(BOOL windowMode, NSString* outPath) {
    @autoreleasepool {
        if (@available(macOS 12.3, *)) {
            __block SCShareableContent* content = nil;
            __block NSError* contentError = nil;
            __block BOOL contentDone = NO;
            [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* c, NSError* e) {
                content = c;
                contentError = e;
                contentDone = YES;
            }];
            runLoopUntil(10.0, ^BOOL{ return contentDone; });
            if (!content || contentError) {
                fprintf(stderr, "smoke FAIL: shareable content unavailable: %s\n",
                        contentError ? contentError.localizedDescription.UTF8String : "timeout/no content");
                return 3;
            }

            SGTargetKind kind = windowMode ? SGTargetWindow : SGTargetDisplay;
            uint32_t targetID = 0;
            uint32_t width = 0, height = 0;
            if (windowMode) {
                for (SCWindow* w in content.windows) {
                    if (!shouldUseWindowForSmoke(w)) continue;
                    targetID = (uint32_t)w.windowID;
                    width = (uint32_t)w.frame.size.width;
                    height = (uint32_t)w.frame.size.height;
                    fprintf(stderr, "smoke: selected window %u %ux%u %s\n",
                            targetID, width, height, w.title.UTF8String);
                    break;
                }
            } else {
                SCDisplay* d = content.displays.firstObject;
                if (d) {
                    targetID = (uint32_t)d.displayID;
                    width = (uint32_t)d.width;
                    height = (uint32_t)d.height;
                    fprintf(stderr, "smoke: selected display %u %ux%u\n", targetID, width, height);
                }
            }
            if (!targetID || !width || !height) {
                fprintf(stderr, "smoke FAIL: no %s target found\n", windowMode ? "window" : "display");
                return 4;
            }

            LivePipeline* pipe = [[LivePipeline alloc] initWithLayer:nil
                                                               width:width
                                                              height:height
                                                           shaderDir:shaderDirForCommandLine()];
            if (!pipe) {
                fprintf(stderr, "smoke FAIL: pipeline init\n");
                return 5;
            }

            __block BOOL started = NO;
            __block BOOL failed = NO;
            __block int rendered = 0;
            __block NSString* message = nil;
            pipe.captureEventHandler = ^(BOOL s, NSString* msg) {
                started = s;
                failed = !s;
                message = msg;
                fprintf(stderr, "smoke: capture event started=%d %s\n", s ? 1 : 0, msg ? msg.UTF8String : "");
            };
            pipe.engineEventHandler = ^(NSInteger event) {
                if (event == 1) rendered++;
            };

            if (![pipe startCaptureKind:kind targetID:targetID excludingWindowIDs:nil]) {
                fprintf(stderr, "smoke FAIL: capture start rejected\n");
                [pipe shutdown];
                return 6;
            }
            runLoopUntil(10.0, ^BOOL{ return started || failed; });
            if (!started || failed) {
                fprintf(stderr, "smoke FAIL: capture did not start: %s\n", message ? message.UTF8String : "timeout");
                [pipe shutdown];
                return 7;
            }

            runLoopUntil(4.0, ^BOOL{ return rendered >= 3; });
            if (rendered == 0) {
                fprintf(stderr, "smoke FAIL: no engine-rendered capture frames\n");
                [pipe shutdown];
                return 8;
            }
            int afterInitialFrames = rendered;
            [pipe resizeToWidth:std::max<uint32_t>(1, width / 2) height:std::max<uint32_t>(1, height / 2)];
            runLoopUntil(4.0, ^BOOL{ return rendered >= afterInitialFrames + 2; });
            if (rendered < afterInitialFrames + 2) {
                fprintf(stderr, "smoke FAIL: capture did not render after resize\n");
                [pipe shutdown];
                return 9;
            }
            [pipe resizeToWidth:width height:height];
            runLoopUntil(4.0, ^BOOL{ return rendered >= afterInitialFrames + 4; });
            if (rendered < afterInitialFrames + 4) {
                fprintf(stderr, "smoke FAIL: capture did not render after resize restore\n");
                [pipe shutdown];
                return 10;
            }
            [pipe stopCapture];
            int afterStopFrames = rendered;
            started = NO;
            failed = NO;
            message = nil;
            if (![pipe startCaptureKind:kind targetID:targetID excludingWindowIDs:nil]) {
                fprintf(stderr, "smoke FAIL: capture restart rejected\n");
                [pipe shutdown];
                return 11;
            }
            runLoopUntil(10.0, ^BOOL{ return started || failed; });
            if (!started || failed) {
                fprintf(stderr, "smoke FAIL: capture restart did not start: %s\n", message ? message.UTF8String : "timeout");
                [pipe shutdown];
                return 12;
            }
            runLoopUntil(4.0, ^BOOL{ return rendered >= afterStopFrames + 3; });
            if (rendered < afterStopFrames + 3) {
                fprintf(stderr, "smoke FAIL: no frames after capture restart\n");
                [pipe shutdown];
                return 13;
            }

            BOOL wrote = [pipe writeLastOutputToPNG:outPath];
            [pipe stopCapture];
            [pipe shutdown];
            if (!wrote) {
                fprintf(stderr, "smoke FAIL: could not write last output\n");
                return 14;
            }
            fprintf(stderr, "smoke OK: %s capture rendered %d frame(s), resize+restart passed, wrote %s\n",
                    windowMode ? "window" : "display", rendered, outPath.UTF8String);
            return 0;
        }
        fprintf(stderr, "smoke FAIL: ScreenCaptureKit requires macOS 12.3+\n");
        return 10;
    }
}

static int runOverlaySmoke() {
    @autoreleasepool {
        if (@available(macOS 12.3, *)) {
            [NSApplication sharedApplication];
            __block SCShareableContent* content = nil;
            __block NSError* contentError = nil;
            __block BOOL contentDone = NO;
            [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* c, NSError* e) {
                content = c;
                contentError = e;
                contentDone = YES;
            }];
            runLoopUntil(10.0, ^BOOL{ return contentDone; });
            SCDisplay* display = content.displays.firstObject;
            if (!display || contentError) {
                fprintf(stderr, "overlay-smoke FAIL: no display target: %s\n",
                        contentError ? contentError.localizedDescription.UTF8String : "timeout/no content");
                return 3;
            }
            NSScreen* screen = NSScreen.screens.firstObject;
            if (!screen) {
                fprintf(stderr, "overlay-smoke FAIL: no NSScreen\n");
                return 4;
            }
            NSRect frame = screen.frame;
            NSPanel* overlay = [[NSPanel alloc] initWithContentRect:frame
                                                          styleMask:(NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel)
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO
                                                             screen:screen];
            overlay.releasedWhenClosed = NO;
            overlay.opaque = NO;
            overlay.backgroundColor = NSColor.clearColor;
            overlay.hasShadow = NO;
            overlay.ignoresMouseEvents = YES;
            overlay.level = CGWindowLevelForKey(kCGScreenSaverWindowLevelKey);
            overlay.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                          NSWindowCollectionBehaviorFullScreenAuxiliary |
                                          NSWindowCollectionBehaviorStationary |
                                          NSWindowCollectionBehaviorIgnoresCycle);
            NSView* view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height)];
            CAMetalLayer* layer = [CAMetalLayer layer];
            view.wantsLayer = YES;
            view.layer = layer;
            overlay.contentView = view;
            [overlay orderFrontRegardless];
            if (!overlay.ignoresMouseEvents) {
                fprintf(stderr, "overlay-smoke FAIL: overlay is not click-through\n");
                [overlay close];
                return 5;
            }

            const uint32_t width = (uint32_t)std::max<CGFloat>((CGFloat)1, frame.size.width * screen.backingScaleFactor);
            const uint32_t height = (uint32_t)std::max<CGFloat>((CGFloat)1, frame.size.height * screen.backingScaleFactor);
            LivePipeline* pipe = [[LivePipeline alloc] initWithLayer:layer width:width height:height shaderDir:shaderDirForCommandLine()];
            if (!pipe) {
                fprintf(stderr, "overlay-smoke FAIL: pipeline init\n");
                [overlay close];
                return 6;
            }
            __block BOOL started = NO;
            __block BOOL failed = NO;
            __block int rendered = 0;
            __block NSString* message = nil;
            pipe.captureEventHandler = ^(BOOL s, NSString* msg) {
                started = s;
                failed = !s;
                message = msg;
                fprintf(stderr, "overlay-smoke: capture event started=%d %s\n", s ? 1 : 0, msg ? msg.UTF8String : "");
            };
            pipe.engineEventHandler = ^(NSInteger event) {
                if (event == 1) rendered++;
            };
            NSArray<NSNumber*>* excluded = overlay.windowNumber > 0 ? @[@((uint32_t)overlay.windowNumber)] : nil;
            if (![pipe startCaptureKind:SGTargetDisplay targetID:(uint32_t)display.displayID excludingWindowIDs:excluded]) {
                fprintf(stderr, "overlay-smoke FAIL: capture start rejected\n");
                [pipe shutdown];
                [overlay close];
                return 7;
            }
            runLoopUntil(10.0, ^BOOL{ return started || failed; });
            if (!started || failed) {
                fprintf(stderr, "overlay-smoke FAIL: capture did not start: %s\n", message ? message.UTF8String : "timeout");
                [pipe shutdown];
                [overlay close];
                return 8;
            }
            runLoopUntil(4.0, ^BOOL{ return rendered >= 3; });
            [pipe stopCapture];
            [pipe shutdown];
            [overlay close];
            if (rendered == 0) {
                fprintf(stderr, "overlay-smoke FAIL: no rendered overlay frames\n");
                return 9;
            }
            fprintf(stderr, "overlay-smoke OK: click-through=%d rendered=%d excluded=%s\n",
                    overlay.ignoresMouseEvents ? 1 : 0, rendered, excluded.description.UTF8String);
            return 0;
        }
        fprintf(stderr, "overlay-smoke FAIL: ScreenCaptureKit requires macOS 12.3+\n");
        return 10;
    }
}

int main(int argc, const char* argv[]) {
    @autoreleasepool {
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--selftest") == 0 && i + 1 < argc)
                return runSelftest([NSString stringWithUTF8String:argv[i+1]]);
            if (strcmp(argv[i], "--selftest-split") == 0 && i + 1 < argc)
                return runSplitSelftest([NSString stringWithUTF8String:argv[i+1]]);
            if (strcmp(argv[i], "--render-preset") == 0 && i + 2 < argc)
                return runPresetRender([NSString stringWithUTF8String:argv[i+1]],
                                       [NSString stringWithUTF8String:argv[i+2]]);
            if (strcmp(argv[i], "--render-preset-from") == 0 && i + 3 < argc)
                return runPresetRenderWithImage([NSString stringWithUTF8String:argv[i+1]],
                                                [NSString stringWithUTF8String:argv[i+2]],
                                                [NSString stringWithUTF8String:argv[i+3]]);
            if (strcmp(argv[i], "--render-all-presets") == 0 && i + 1 < argc)
                return runRenderAllPresets([NSString stringWithUTF8String:argv[i+1]]);
            if (strcmp(argv[i], "--render-all-presets-from") == 0 && i + 2 < argc)
                return runRenderAllPresetsWithImage([NSString stringWithUTF8String:argv[i+1]],
                                                    [NSString stringWithUTF8String:argv[i+2]]);
            if (strcmp(argv[i], "--smoke-display") == 0 && i + 1 < argc)
                return runCaptureSmoke(NO, [NSString stringWithUTF8String:argv[i+1]]);
            if (strcmp(argv[i], "--smoke-window") == 0 && i + 1 < argc)
                return runCaptureSmoke(YES, [NSString stringWithUTF8String:argv[i+1]]);
            if (strcmp(argv[i], "--smoke-overlay") == 0)
                return runOverlaySmoke();
        }
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        SGAppDelegate* delegate = [[SGAppDelegate alloc] init];
        app.delegate = delegate;

        // minimal menu bar with compare, export, and quit
        NSMenu* menubar = [[NSMenu alloc] init];
        NSMenuItem* appItem = [[NSMenuItem alloc] init];
        [menubar addItem:appItem];
        NSMenu* appMenu = [[NSMenu alloc] init];
        NSMenuItem* splitCompareItem = [appMenu addItemWithTitle:@"Toggle Split Compare"
                                                          action:@selector(toggleSplitCompare:)
                                                   keyEquivalent:@"/"];
        splitCompareItem.target = delegate;
        NSMenuItem* exportItem = [appMenu addItemWithTitle:@"Export Moment..."
                                                    action:@selector(exportMoment:)
                                             keyEquivalent:@"e"];
        exportItem.target = delegate;
        [appMenu addItem:[NSMenuItem separatorItem]];
        [appMenu addItemWithTitle:@"Quit ShaderGlass" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu;
        app.mainMenu = menubar;

        [app run];
    }
    return 0;
}
