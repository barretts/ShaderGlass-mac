/*
ShaderGlass macOS port -- SGAppDelegate.mm

Window + CAMetalLayer view + toolbar pickers (Target / Shader / Start-Stop).
Drives LivePipeline. Capture target enumeration uses ScreenCaptureKit directly
(the TCC gate). L1/L2 work with no capture; L3+ wires Start.
*/

#import "SGAppDelegate.h"
#import "SGMetalView.h"
#import "LivePipeline.h"
#import <ScreenCaptureKit/ScreenCaptureKit.h>

// A resolved capture target stashed as an NSPopUpButton item's representedObject.
@interface SGTargetItem : NSObject
@property(nonatomic) SGTargetKind kind;
@property(nonatomic) uint32_t targetID;
@property(nonatomic, copy) NSString* label;
@end
@implementation SGTargetItem @end

@interface SGAppDelegate () <SGMetalViewDelegate>
@end

@implementation SGAppDelegate {
    NSWindow*       _window;
    NSView*         _content;
    NSView*         _bar;
    SGMetalView*    _view;
    LivePipeline*   _pipe;
    NSPopUpButton*  _targetPicker;
    NSPopUpButton*  _shaderPicker;
    NSButton*       _startStop;
    NSTimer*        _redrawTimer;     // L1/L2 static-image redraw (no capture)
    BOOL            _capturing;
    BOOL            _captureStarting;
    BOOL            _overlayMode;
    CGFloat         _barH;
    NSRect          _normalWindowFrame;
    NSPanel*        _overlayWindow;
    NSString*       _shaderDir;
}

// ---- resource location: bundle Resources, else a dev-relative fallback ----
- (NSString*)resolveShaderDir {
    NSString* res = [[NSBundle mainBundle] resourcePath];
    if (res && [[NSFileManager defaultManager] fileExistsAtPath:[res stringByAppendingPathComponent:@"passthrough.metal"]])
        return res;
    // loose build fallback: mac/spike relative to CWD
    return @"../spike";
}
- (NSString*)resolveSampleImage {
    NSString* res = [[NSBundle mainBundle] resourcePath];
    NSString* b = res ? [res stringByAppendingPathComponent:@"screen6.png"] : nil;
    if (b && [[NSFileManager defaultManager] fileExistsAtPath:b]) return b;
    return @"../../images/screen6.png";
}

- (void)applicationDidFinishLaunching:(NSNotification*)note {
    _barH = 44;
    NSRect frame = NSMakeRect(0, 0, 960, 640 + _barH);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|
                                                     NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"ShaderGlass (macOS)";
    [_window center];

    // Container content view: a control bar pinned to the top, the Metal view below.
    _content = [[NSView alloc] initWithFrame:frame];
    _window.contentView = _content;

    _bar = [[NSView alloc] initWithFrame:NSMakeRect(0, frame.size.height - _barH, frame.size.width, _barH)];
    _bar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _bar.wantsLayer = YES;
    _bar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    [_content addSubview:_bar];
    [self buildControlsInBar:_bar];

    _view = [[SGMetalView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - _barH)];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _view.sgDelegate = self;
    [_content addSubview:_view];

    _shaderDir = [self resolveShaderDir];
    CGSize px = [_view backingPixelSize];
    _pipe = [[LivePipeline alloc] initWithLayer:_view.metalLayer
                                          width:(uint32_t)px.width height:(uint32_t)px.height
                                      shaderDir:_shaderDir];
    if (!_pipe) {
        [self fatal:@"Failed to initialize Metal pipeline (no GPU or shader compile error)."];
        return;
    }
    __weak SGAppDelegate* weakSelf = self;
    _pipe.captureEventHandler = ^(BOOL started, NSString* message) {
        [weakSelf captureDidReportStarted:started message:message];
    };
    // L1/L2: show the sample image immediately, repaint on a light timer so resizes
    // and shader swaps are always reflected even before capture is started.
    [_pipe setStaticImagePath:[self resolveSampleImage]];
    [_pipe renderFrame];
    _redrawTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0 target:self
                                                  selector:@selector(tick) userInfo:nil repeats:YES];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [self refreshTargets];
}

- (void)tick { if (!_capturing) [_pipe renderFrame]; }

- (void)metalViewDidResizeToWidth:(uint32_t)width height:(uint32_t)height {
    [_pipe resizeToWidth:width height:height];
}

// ---- control bar: Target picker | Shader picker | Start/Stop (plain subviews) ----
// NSToolbar custom-view items are finicky (dead clicks without explicit min/maxSize);
// a plain subview bar with explicit frames is robust.
- (void)buildControlsInBar:(NSView*)bar {
    const CGFloat y = 10, h = 24;

    NSTextField* tl = [NSTextField labelWithString:@"Target:"];
    tl.frame = NSMakeRect(10, y, 50, h);
    [bar addSubview:tl];
    _targetPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(64, y, 320, h) pullsDown:NO];
    [_targetPicker addItemWithTitle:@"(scanning…)"];
    [bar addSubview:_targetPicker];

    NSTextField* sl = [NSTextField labelWithString:@"Shader:"];
    sl.frame = NSMakeRect(400, y, 52, h);
    [bar addSubview:sl];
    _shaderPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(456, y, 220, h) pullsDown:NO];
    [_shaderPicker addItemsWithTitles:@[
        @"Passthrough",
        @"CRT",
        @"CRT Pro",
        @"LCD Grid",
        @"Amber Mono",
        @"VHS Soft",
        @"Green Mono",
        @"Pixel Grid",
        @"Bloom Soft",
        @"PVM Slots",
    ]];
    _shaderPicker.target = self; _shaderPicker.action = @selector(shaderChanged:);
    [bar addSubview:_shaderPicker];

    _startStop = [NSButton buttonWithTitle:@"Start" target:self action:@selector(toggleCapture:)];
    _startStop.frame = NSMakeRect(692, y - 2, 90, h + 4);
    _startStop.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:_startStop];

    NSButton* rescan = [NSButton buttonWithTitle:@"Rescan" target:self action:@selector(rescanTargets:)];
    rescan.frame = NSMakeRect(788, y - 2, 80, h + 4);
    rescan.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:rescan];
}

- (void)shaderChanged:(id)sender {
    [_pipe setShaderKind:(SGShaderKind)_shaderPicker.indexOfSelectedItem];
    NSLog(@"ShaderGlass: shader -> %@", _shaderPicker.titleOfSelectedItem);
}

- (void)rescanTargets:(id)sender { [self refreshTargets]; }

- (void)captureDidReportStarted:(BOOL)started message:(NSString*)message {
    if (started) {
        _captureStarting = NO;
        _capturing = YES;
        _startStop.enabled = YES;
        _startStop.title = @"Stop";
        NSLog(@"ShaderGlass: capture started");
        return;
    }

    NSLog(@"ShaderGlass: capture failed: %@", message ?: @"unknown error");
    [_pipe stopCapture];
    _captureStarting = NO;
    _capturing = NO;
    [self leaveOverlayMode];
    _startStop.enabled = YES;
    _startStop.title = @"Start";
    [_pipe renderFrame];

    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = @"Capture failed";
    a.informativeText = message.length ? message : @"ShaderGlass could not start ScreenCaptureKit capture.";
    [a addButtonWithTitle:@"OK"];
    [a beginSheetModalForWindow:_window completionHandler:nil];
}

- (NSScreen*)screenForDisplayID:(uint32_t)displayID {
    for (NSScreen* screen in NSScreen.screens) {
        NSNumber* n = screen.deviceDescription[@"NSScreenNumber"];
        if (n && n.unsignedIntValue == displayID) return screen;
    }
    return nil;
}

- (void)resizePipelineToCurrentView {
    CGSize px = [_view backingPixelSize];
    [_pipe resizeToWidth:(uint32_t)px.width height:(uint32_t)px.height];
}

- (void)installMetalViewInCloneWindow {
    [_view removeFromSuperview];
    NSRect bounds = _content.bounds;
    _bar.frame = NSMakeRect(0, MAX(0, bounds.size.height - _barH), bounds.size.width, _barH);
    _view.frame = NSMakeRect(0, 0, bounds.size.width, MAX(1, bounds.size.height - _barH));
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_content addSubview:_view positioned:NSWindowBelow relativeTo:_bar];
    [self resizePipelineToCurrentView];
}

- (void)installMetalViewInOverlayWindow:(NSWindow*)window {
    [_view removeFromSuperview];
    NSView* content = window.contentView;
    _view.frame = content.bounds;
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [content addSubview:_view];
    [self resizePipelineToCurrentView];
}

- (NSArray<NSNumber*>*)captureExclusionWindowIDs {
    NSMutableArray<NSNumber*>* ids = [NSMutableArray array];
    if (_window.windowNumber > 0) [ids addObject:@((uint32_t)_window.windowNumber)];
    if (_overlayWindow.windowNumber > 0) [ids addObject:@((uint32_t)_overlayWindow.windowNumber)];
    return ids;
}

- (BOOL)enterOverlayModeForDisplayID:(uint32_t)displayID {
    NSScreen* screen = [self screenForDisplayID:displayID];
    if (!screen) {
        NSLog(@"ShaderGlass: overlay display %u did not match any NSScreen", (unsigned)displayID);
        for (NSScreen* s in NSScreen.screens) {
            NSNumber* n = s.deviceDescription[@"NSScreenNumber"];
            NSLog(@"ShaderGlass: NSScreen id=%@ frame=%@", n, NSStringFromRect(s.frame));
        }
        return NO;
    }

    _normalWindowFrame = _window.frame;
    NSRect f = screen.frame;
    NSInteger overlayLevel = CGWindowLevelForKey(kCGScreenSaverWindowLevelKey);
    _overlayWindow = [[NSPanel alloc] initWithContentRect:f
                                                styleMask:(NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel)
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO
                                                   screen:screen];
    _overlayWindow.releasedWhenClosed = NO;
    _overlayWindow.opaque = NO;
    _overlayWindow.backgroundColor = NSColor.clearColor;
    _overlayWindow.hasShadow = NO;
    _overlayWindow.ignoresMouseEvents = YES;
    _overlayWindow.level = overlayLevel;
    _overlayWindow.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                         NSWindowCollectionBehaviorFullScreenAuxiliary |
                                         NSWindowCollectionBehaviorStationary |
                                         NSWindowCollectionBehaviorIgnoresCycle);
    _overlayWindow.contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, f.size.width, f.size.height)];
    _overlayWindow.contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    [self installMetalViewInOverlayWindow:_overlayWindow];
    [_overlayWindow orderFrontRegardless];

    [_window setContentSize:NSMakeSize(800, _barH)];
    [_window setFrameTopLeftPoint:NSMakePoint(f.origin.x + 20, NSMaxY(f) - 20)];
    _window.title = @"ShaderGlass Controls";
    _window.level = overlayLevel + 1;
    _window.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary);
    _bar.frame = _content.bounds;
    _bar.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_window makeKeyAndOrderFront:nil];

    _overlayMode = YES;
    NSLog(@"ShaderGlass: overlay display %u screen=%@ level=%ld controls=%ld excluded=%@",
          (unsigned)displayID, NSStringFromRect(f), (long)_overlayWindow.level,
          (long)_window.level, [self captureExclusionWindowIDs]);
    return YES;
}

- (void)leaveOverlayMode {
    if (!_overlayMode) return;
    [_overlayWindow orderOut:nil];
    [_overlayWindow close];
    _overlayWindow = nil;

    _window.title = @"ShaderGlass (macOS)";
    _window.level = NSNormalWindowLevel;
    _window.collectionBehavior = NSWindowCollectionBehaviorManaged;
    [_window setFrame:_normalWindowFrame display:YES];
    _bar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [self installMetalViewInCloneWindow];
    [_window makeKeyAndOrderFront:nil];
    _overlayMode = NO;
}

// ---- capture target enumeration (TCC gate) ----
- (void)refreshTargets {
    if (@available(macOS 12.3, *)) {
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* c, NSError* e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_targetPicker removeAllItems];
                if (!c || e) {
                    [self->_targetPicker addItemWithTitle:@"(Screen Recording not granted)"];
                    return;
                }
                for (SCDisplay* d in c.displays) {
                    SGTargetItem* t = [SGTargetItem new];
                    t.kind = SGTargetDisplay; t.targetID = (uint32_t)d.displayID;
                    t.label = [NSString stringWithFormat:@"Glass Overlay — Display %u (%dx%d)", (unsigned)d.displayID, (int)d.width, (int)d.height];
                    [self->_targetPicker addItemWithTitle:t.label];
                    self->_targetPicker.lastItem.representedObject = t;
                }
                for (SCWindow* w in c.windows) {
                    if (!w.title.length || w.frame.size.width < 64 || w.frame.size.height < 64) continue;
                    SGTargetItem* t = [SGTargetItem new];
                    t.kind = SGTargetWindow; t.targetID = (uint32_t)w.windowID;
                    NSString* app = w.owningApplication.applicationName ?: @"?";
                    t.label = [NSString stringWithFormat:@"Window Clone — %@ — %@", app, w.title];
                    [self->_targetPicker addItemWithTitle:t.label];
                    self->_targetPicker.lastItem.representedObject = t;
                }
                if (self->_targetPicker.numberOfItems == 0)
                    [self->_targetPicker addItemWithTitle:@"(no targets)"];
            });
        }];
    } else {
        [_targetPicker removeAllItems];
        [_targetPicker addItemWithTitle:@"(requires macOS 12.3+)"];
    }
}

- (void)toggleCapture:(id)sender {
    if (_captureStarting) return;
    if (_capturing) {
        [_pipe stopCapture];
        _capturing = NO;
        _captureStarting = NO;
        [self leaveOverlayMode];
        _startStop.title = @"Start";
        _startStop.enabled = YES;
        [_pipe renderFrame];   // fall back to showing the static image
        return;
    }
    SGTargetItem* t = (SGTargetItem*)_targetPicker.selectedItem.representedObject;
    if (!t) {
        [self showTCCDeniedAlert];
        [self refreshTargets];
        return;
    }
    BOOL useOverlay = (t.kind == SGTargetDisplay);
    if (useOverlay && ![self enterOverlayModeForDisplayID:t.targetID]) {
        NSLog(@"ShaderGlass: display %u has no matching NSScreen; using windowed clone mode", (unsigned)t.targetID);
        useOverlay = NO;
    }
    if (!useOverlay) {
        NSLog(@"ShaderGlass: starting windowed clone capture for %@", t.label);
    }
    _captureStarting = YES;
    _startStop.title = @"Starting…";
    _startStop.enabled = NO;
    BOOL accepted = [_pipe startCaptureKind:t.kind
                                   targetID:t.targetID
                         excludingWindowIDs:useOverlay ? [self captureExclusionWindowIDs] : nil];
    if (!accepted) {
        [self captureDidReportStarted:NO message:@"ScreenCaptureKit is unavailable or capture initialization failed."];
    }
}

- (void)showTCCDeniedAlert {
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = @"Screen Recording permission needed";
    a.informativeText = @"Grant ShaderGlass access in System Settings > Privacy & Security > Screen Recording, then relaunch.";
    [a addButtonWithTitle:@"Open System Settings"];
    [a addButtonWithTitle:@"Cancel"];
    if ([a runModal] == NSAlertFirstButtonReturn) {
        [[NSWorkspace sharedWorkspace] openURL:
            [NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]];
    }
}

- (void)fatal:(NSString*)msg {
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = @"ShaderGlass"; a.informativeText = msg;
    [a runModal];
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app { return YES; }
- (void)applicationWillTerminate:(NSNotification*)note {
    [_redrawTimer invalidate];
    [_pipe shutdown];
}

@end
