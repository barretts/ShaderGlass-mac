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
    SGMetalView*    _view;
    LivePipeline*   _pipe;
    NSPopUpButton*  _targetPicker;
    NSPopUpButton*  _shaderPicker;
    NSButton*       _startStop;
    NSTimer*        _redrawTimer;     // L1/L2 static-image redraw (no capture)
    BOOL            _capturing;
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
    const CGFloat barH = 44;
    NSRect frame = NSMakeRect(0, 0, 960, 640 + barH);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|
                                                     NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"ShaderGlass (macOS)";
    [_window center];

    // Container content view: a control bar pinned to the top, the Metal view below.
    NSView* content = [[NSView alloc] initWithFrame:frame];
    _window.contentView = content;

    NSView* bar = [[NSView alloc] initWithFrame:NSMakeRect(0, frame.size.height - barH, frame.size.width, barH)];
    bar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    bar.wantsLayer = YES;
    bar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    [content addSubview:bar];
    [self buildControlsInBar:bar];

    _view = [[SGMetalView alloc] initWithFrame:NSMakeRect(0, 0, frame.size.width, frame.size.height - barH)];
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _view.sgDelegate = self;
    [content addSubview:_view];

    _shaderDir = [self resolveShaderDir];
    CGSize px = [_view backingPixelSize];
    _pipe = [[LivePipeline alloc] initWithLayer:_view.metalLayer
                                          width:(uint32_t)px.width height:(uint32_t)px.height
                                      shaderDir:_shaderDir];
    if (!_pipe) {
        [self fatal:@"Failed to initialize Metal pipeline (no GPU or shader compile error)."];
        return;
    }
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
    _shaderPicker = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(456, y, 140, h) pullsDown:NO];
    [_shaderPicker addItemsWithTitles:@[@"Passthrough", @"CRT"]];
    _shaderPicker.target = self; _shaderPicker.action = @selector(shaderChanged:);
    [bar addSubview:_shaderPicker];

    _startStop = [NSButton buttonWithTitle:@"Start" target:self action:@selector(toggleCapture:)];
    _startStop.frame = NSMakeRect(612, y - 2, 90, h + 4);
    _startStop.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:_startStop];

    NSButton* rescan = [NSButton buttonWithTitle:@"Rescan" target:self action:@selector(rescanTargets:)];
    rescan.frame = NSMakeRect(708, y - 2, 80, h + 4);
    rescan.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:rescan];
}

- (void)shaderChanged:(id)sender {
    [_pipe setShaderKind:(_shaderPicker.indexOfSelectedItem == 1) ? SGShaderCRT : SGShaderPassthrough];
    NSLog(@"ShaderGlass: shader -> %@", _shaderPicker.titleOfSelectedItem);
}

- (void)rescanTargets:(id)sender { [self refreshTargets]; }

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
                    t.label = [NSString stringWithFormat:@"Display %u (%dx%d)", (unsigned)d.displayID, (int)d.width, (int)d.height];
                    [self->_targetPicker addItemWithTitle:t.label];
                    self->_targetPicker.lastItem.representedObject = t;
                }
                for (SCWindow* w in c.windows) {
                    if (!w.title.length || w.frame.size.width < 64 || w.frame.size.height < 64) continue;
                    SGTargetItem* t = [SGTargetItem new];
                    t.kind = SGTargetWindow; t.targetID = (uint32_t)w.windowID;
                    NSString* app = w.owningApplication.applicationName ?: @"?";
                    t.label = [NSString stringWithFormat:@"%@ — %@", app, w.title];
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
    if (_capturing) {
        [_pipe stopCapture];
        _capturing = NO;
        _startStop.title = @"Start";
        [_pipe renderFrame];   // fall back to showing the static image
        return;
    }
    SGTargetItem* t = (SGTargetItem*)_targetPicker.selectedItem.representedObject;
    if (!t) {
        [self showTCCDeniedAlert];
        [self refreshTargets];
        return;
    }
    _capturing = YES;
    _startStop.title = @"Stop";
    [_pipe startCaptureKind:t.kind targetID:t.targetID];
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
