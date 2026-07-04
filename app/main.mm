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
#include <algorithm>

static int runSelftest(NSString* outPath) {
    @autoreleasepool {
        // Prefer the bundle Resources (CWD-independent); fall back to the dev-tree
        // relative paths only if running the bare binary outside a bundle.
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
                    if (!w.title.length || w.frame.size.width < 64 || w.frame.size.height < 64) continue;
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

        // minimal menu bar with Quit (Cmd-Q)
        NSMenu* menubar = [[NSMenu alloc] init];
        NSMenuItem* appItem = [[NSMenuItem alloc] init];
        [menubar addItem:appItem];
        NSMenu* appMenu = [[NSMenu alloc] init];
        [appMenu addItemWithTitle:@"Quit ShaderGlass" action:@selector(terminate:) keyEquivalent:@"q"];
        appItem.submenu = appMenu;
        app.mainMenu = menubar;

        [app run];
    }
    return 0;
}
