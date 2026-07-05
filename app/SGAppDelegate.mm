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
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SGPresetDeckButton : NSButton
@property(nonatomic, copy) NSString* deckTitle;
@property(nonatomic, copy) NSString* deckCaption;
@property(nonatomic) BOOL deckSelected;
- (void)refreshStyle;
@end

@implementation SGPresetDeckButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (!self) return nil;
    self.bordered = NO;
    self.buttonType = NSButtonTypeMomentaryChange;
    self.alignment = NSTextAlignmentLeft;
    self.imagePosition = NSNoImage;
    self.focusRingType = NSFocusRingTypeExterior;
    self.wantsLayer = YES;
    self.layer.cornerRadius = 8.0;
    self.layer.borderWidth = 1.0;
    self.layer.masksToBounds = YES;
    [(NSButtonCell*)self.cell setWraps:YES];
    self.cell.lineBreakMode = NSLineBreakByWordWrapping;
    self.deckTitle = @"";
    self.deckCaption = @"";
    [self refreshStyle];
    return self;
}

- (void)setDeckTitle:(NSString*)deckTitle {
    _deckTitle = [deckTitle copy];
    [self refreshStyle];
}

- (void)setDeckCaption:(NSString*)deckCaption {
    _deckCaption = [deckCaption copy];
    [self refreshStyle];
}

- (void)setDeckSelected:(BOOL)deckSelected {
    _deckSelected = deckSelected;
    [self refreshStyle];
}

- (void)refreshStyle {
    NSColor* fill = self.deckSelected ? [NSColor colorWithCalibratedRed:0.17 green:0.30 blue:0.52 alpha:1.0]
                                      : [NSColor colorWithWhite:0.15 alpha:0.95];
    NSColor* stroke = self.deckSelected ? [NSColor colorWithCalibratedRed:0.34 green:0.54 blue:0.86 alpha:1.0]
                                        : [NSColor colorWithWhite:0.27 alpha:1.0];
    self.layer.backgroundColor = fill.CGColor;
    self.layer.borderColor = stroke.CGColor;

    NSMutableParagraphStyle* style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 2.0;
    style.alignment = NSTextAlignmentLeft;

    NSDictionary* titleAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: NSColor.whiteColor,
        NSParagraphStyleAttributeName: style,
    };
    NSDictionary* captionAttrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithWhite:0.82 alpha:1.0],
        NSParagraphStyleAttributeName: style,
    };

    NSString* title = self.deckTitle.length ? self.deckTitle : @"Preset";
    NSString* caption = self.deckCaption.length ? self.deckCaption : @"Ready";
    NSMutableAttributedString* text =
        [[NSMutableAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n%@", title, caption]
                                               attributes:titleAttrs];
    [text setAttributes:captionAttrs range:NSMakeRange(title.length + 1, caption.length)];
    self.attributedTitle = text;
    self.contentTintColor = NSColor.whiteColor;
}

@end

@interface SGMomentaryHoldButton : NSButton
@property(nonatomic, copy, nullable) dispatch_block_t holdDidBegin;
@property(nonatomic, copy, nullable) dispatch_block_t holdDidEnd;
@end

@implementation SGMomentaryHoldButton

- (void)mouseDown:(NSEvent*)event {
    if (self.holdDidBegin) self.holdDidBegin();
    [super mouseDown:event];
    if (self.holdDidEnd) self.holdDidEnd();
}

@end

@interface SGFlippedView : NSView
@end

@implementation SGFlippedView
- (BOOL)isFlipped { return YES; }
@end

// A resolved capture target stashed as an NSPopUpButton item's representedObject.
@interface SGTargetItem : NSObject
@property(nonatomic) SGTargetKind kind;
@property(nonatomic) uint32_t targetID;
@property(nonatomic, copy) NSString* label;
@end
@implementation SGTargetItem @end

static NSMenuItem* SGDisabledMenuItem(NSString* title) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
    item.enabled = NO;
    return item;
}

static BOOL SGShouldOfferWindowCapture(SCWindow* window) API_AVAILABLE(macos(12.3)) {
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

@interface SGAppDelegate () <SGMetalViewDelegate, NSWindowDelegate>
- (void)refreshCompareControls;
- (void)installCompareKeyMonitors;
- (void)cancelBypassCompare;
- (void)applyCompareModeSelection:(SGCompareMode)mode updatePipeline:(BOOL)updatePipeline;
@end

@implementation SGAppDelegate {
    NSButton*       _exportButton;
    NSWindow*       _window;
    NSView*         _content;
    NSView*         _bar;
    NSView*         _workspace;
    NSView*         _viewHost;
    NSView*         _controlSurface;
    SGMetalView*    _view;
    LivePipeline*   _pipe;
    NSPopUpButton*  _targetPicker;
    NSButton*       _startStop;
    NSButton*       _rescanButton;
    NSTextField*    _captureLabel;
    NSTextField*    _statusLabel;
    NSSegmentedControl* _compareModeControl;
    SGMomentaryHoldButton* _compareBypassButton;
    NSTextField*    _presetDeckLabel;
    NSScrollView*   _presetDeckScroll;
    NSView*         _presetDeckContent;
    NSMutableArray<SGPresetDeckButton*>* _presetButtons;
    NSArray<SGShaderPresetDescriptor*>* _shaderCatalog;
    NSTextField*    _controlShellLabel;
    NSView*         _parameterShell;
    NSTextField*    _parameterHint;
    NSTextField*    _parameterIntensityLabel;
    NSTextField*    _parameterScanLabel;
    NSTextField*    _parameterMaskLabel;
    NSTextField*    _parameterColorLabel;
    NSTextField*    _compareSplitLabel;
    NSSlider*       _parameterIntensitySlider;
    NSSlider*       _parameterScanSlider;
    NSSlider*       _parameterMaskSlider;
    NSSlider*       _parameterColorSlider;
    NSSlider*       _compareSplitSlider;
    NSButton*       _parameterResetButton;
    NSTimer*        _redrawTimer;     // L1/L2 static-image redraw (no capture)
    BOOL            _capturing;
    BOOL            _captureStarting;
    BOOL            _overlayMode;
    CGFloat         _barH;
    NSRect          _normalWindowFrame;
    NSPanel*        _overlayWindow;
    NSString*       _shaderDir;
    BOOL            _compareBypassActive;
    id              _compareKeyDownMonitor;
    id              _compareKeyUpMonitor;
}

static NSString* const SGLastCaptureTargetKey = @"ShaderGlassLastCaptureTarget";
static NSString* const SGLastPresetIdentifierKey = @"ShaderGlassLastPresetIdentifier";
static NSString* const SGPresetParameterOverridesKey = @"ShaderGlassPresetParameterOverrides";

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
    _barH = 56;
    NSRect frame = NSMakeRect(0, 0, 1180, 720);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|
                                                     NSWindowStyleMaskMiniaturizable|NSWindowStyleMaskResizable)
                                            backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"ShaderGlass (macOS)";
    _window.delegate = self;
    _window.minSize = NSMakeSize(860, 560);
    [_window center];

    _content = [[NSView alloc] initWithFrame:frame];
    _window.contentView = _content;

    _bar = [[NSView alloc] initWithFrame:NSZeroRect];
    _bar.wantsLayer = YES;
    _bar.layer.backgroundColor = [NSColor windowBackgroundColor].CGColor;
    [_content addSubview:_bar];
    [self buildControlsInBar:_bar];

    _workspace = [[NSView alloc] initWithFrame:NSZeroRect];
    [_content addSubview:_workspace];

    _viewHost = [[NSView alloc] initWithFrame:NSZeroRect];
    _viewHost.wantsLayer = YES;
    _viewHost.layer.backgroundColor = [NSColor colorWithWhite:0.08 alpha:1.0].CGColor;
    [_workspace addSubview:_viewHost];

    _controlSurface = [[NSView alloc] initWithFrame:NSZeroRect];
    _controlSurface.wantsLayer = YES;
    _controlSurface.layer.backgroundColor = [NSColor colorWithWhite:0.11 alpha:0.98].CGColor;
    [_workspace addSubview:_controlSurface];
    [self buildControlSurfaceInView:_controlSurface];

    _view = [[SGMetalView alloc] initWithFrame:NSZeroRect];
    _view.sgDelegate = self;
    [_viewHost addSubview:_view];

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
    [self reloadShaderPresets];
    [self applyInitialPresetSelection];
    [self installCompareKeyMonitors];
    [self updateStatusLabel:@"Previewing sample image"];
    [self layoutChrome];

    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    [self refreshTargets];
}

- (void)tick { if (!_capturing) [_pipe renderFrame]; }

- (void)metalViewDidResizeToWidth:(uint32_t)width height:(uint32_t)height {
    [_pipe resizeToWidth:width height:height];
}

- (void)buildControlsInBar:(NSView*)bar {
    _captureLabel = [NSTextField labelWithString:@"Capture"];
    _captureLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    [bar addSubview:_captureLabel];
    _targetPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _targetPicker.target = self;
    _targetPicker.action = @selector(captureTargetSelectionChanged:);
    [_targetPicker addItemWithTitle:@"(scanning…)"];
    [bar addSubview:_targetPicker];

    _startStop = [NSButton buttonWithTitle:@"Start" target:self action:@selector(toggleCapture:)];
    _startStop.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:_startStop];

    _rescanButton = [NSButton buttonWithTitle:@"Rescan" target:self action:@selector(rescanTargets:)];
    _rescanButton.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:_rescanButton];

    _exportButton = [NSButton buttonWithTitle:@"Export" target:self action:@selector(exportMoment:)];
    _exportButton.bezelStyle = NSBezelStyleRounded;
    [bar addSubview:_exportButton];

    _compareModeControl = [[NSSegmentedControl alloc] initWithFrame:NSZeroRect];
    _compareModeControl.segmentCount = 2;
    [_compareModeControl setLabel:@"Off" forSegment:0];
    [_compareModeControl setLabel:@"Split" forSegment:1];
    _compareModeControl.trackingMode = NSSegmentSwitchTrackingSelectOne;
    _compareModeControl.target = self;
    _compareModeControl.action = @selector(compareModeChanged:);
    _compareModeControl.segmentStyle = NSSegmentStyleRounded;
    _compareModeControl.selectedSegment = 0;
    [bar addSubview:_compareModeControl];

    _compareBypassButton = [[SGMomentaryHoldButton alloc] initWithFrame:NSZeroRect];
    _compareBypassButton.title = @"Bypass";
    _compareBypassButton.bezelStyle = NSBezelStyleRounded;
    __weak SGAppDelegate* weakSelf = self;
    _compareBypassButton.holdDidBegin = ^{
        SGAppDelegate* self = weakSelf;
        if (!self) return;
        [self beginBypassCompare:self->_compareBypassButton];
    };
    _compareBypassButton.holdDidEnd = ^{
        SGAppDelegate* self = weakSelf;
        if (!self) return;
        [self endBypassCompare:self->_compareBypassButton];
    };
    [bar addSubview:_compareBypassButton];

    _statusLabel = [NSTextField labelWithString:@"Loading presets"];
    _statusLabel.alignment = NSTextAlignmentRight;
    _statusLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightRegular];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    [bar addSubview:_statusLabel];
}

- (void)buildControlSurfaceInView:(NSView*)surface {
    _presetButtons = [NSMutableArray array];

    _presetDeckLabel = [NSTextField labelWithString:@"Presets"];
    _presetDeckLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    _presetDeckLabel.textColor = NSColor.whiteColor;
    [surface addSubview:_presetDeckLabel];

    _presetDeckContent = [[SGFlippedView alloc] initWithFrame:NSZeroRect];
    _presetDeckScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    _presetDeckScroll.borderType = NSNoBorder;
    _presetDeckScroll.drawsBackground = NO;
    _presetDeckScroll.hasVerticalScroller = YES;
    _presetDeckScroll.autohidesScrollers = YES;
    _presetDeckScroll.documentView = _presetDeckContent;
    [surface addSubview:_presetDeckScroll];

    _controlShellLabel = [NSTextField labelWithString:@"Controls"];
    _controlShellLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    _controlShellLabel.textColor = NSColor.whiteColor;
    [surface addSubview:_controlShellLabel];

    _parameterShell = [[NSView alloc] initWithFrame:NSZeroRect];
    _parameterShell.wantsLayer = YES;
    _parameterShell.layer.cornerRadius = 8.0;
    _parameterShell.layer.backgroundColor = [NSColor colorWithWhite:0.14 alpha:1.0].CGColor;
    _parameterShell.layer.borderWidth = 1.0;
    _parameterShell.layer.borderColor = [NSColor colorWithWhite:0.24 alpha:1.0].CGColor;
    [surface addSubview:_parameterShell];

    _parameterHint = [NSTextField labelWithString:@"Preset-specific controls land here next. This shell stays wired while capture is running."];
    _parameterHint.font = [NSFont systemFontOfSize:11 weight:NSFontWeightRegular];
    _parameterHint.textColor = [NSColor secondaryLabelColor];
    _parameterHint.lineBreakMode = NSLineBreakByWordWrapping;
    _parameterHint.maximumNumberOfLines = 0;
    [_parameterShell addSubview:_parameterHint];

    _parameterIntensityLabel = [NSTextField labelWithString:@"Intensity"];
    _parameterIntensityLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _parameterIntensityLabel.textColor = [NSColor colorWithWhite:0.88 alpha:1.0];
    [_parameterShell addSubview:_parameterIntensityLabel];

    _parameterIntensitySlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _parameterIntensitySlider.enabled = NO;
    _parameterIntensitySlider.target = self;
    _parameterIntensitySlider.action = @selector(parameterSliderChanged:);
    [_parameterShell addSubview:_parameterIntensitySlider];

    _parameterScanLabel = [NSTextField labelWithString:@"Scanlines"];
    _parameterScanLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _parameterScanLabel.textColor = [NSColor colorWithWhite:0.88 alpha:1.0];
    [_parameterShell addSubview:_parameterScanLabel];

    _parameterScanSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _parameterScanSlider.enabled = NO;
    _parameterScanSlider.target = self;
    _parameterScanSlider.action = @selector(parameterSliderChanged:);
    [_parameterShell addSubview:_parameterScanSlider];

    _parameterMaskLabel = [NSTextField labelWithString:@"Mask"];
    _parameterMaskLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _parameterMaskLabel.textColor = [NSColor colorWithWhite:0.88 alpha:1.0];
    [_parameterShell addSubview:_parameterMaskLabel];

    _parameterMaskSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _parameterMaskSlider.enabled = NO;
    _parameterMaskSlider.target = self;
    _parameterMaskSlider.action = @selector(parameterSliderChanged:);
    [_parameterShell addSubview:_parameterMaskSlider];

    _parameterColorLabel = [NSTextField labelWithString:@"Color Boost"];
    _parameterColorLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _parameterColorLabel.textColor = [NSColor colorWithWhite:0.88 alpha:1.0];
    [_parameterShell addSubview:_parameterColorLabel];

    _parameterColorSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _parameterColorSlider.enabled = NO;
    _parameterColorSlider.target = self;
    _parameterColorSlider.action = @selector(parameterSliderChanged:);
    [_parameterShell addSubview:_parameterColorSlider];

    _compareSplitLabel = [NSTextField labelWithString:@"Split Position"];
    _compareSplitLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
    _compareSplitLabel.textColor = [NSColor colorWithWhite:0.88 alpha:1.0];
    [_parameterShell addSubview:_compareSplitLabel];

    _compareSplitSlider = [[NSSlider alloc] initWithFrame:NSZeroRect];
    _compareSplitSlider.minValue = 0.0;
    _compareSplitSlider.maxValue = 1.0;
    _compareSplitSlider.floatValue = 0.5f;
    _compareSplitSlider.enabled = NO;
    _compareSplitSlider.target = self;
    _compareSplitSlider.action = @selector(compareSplitPositionChanged:);
    [_parameterShell addSubview:_compareSplitSlider];

    _parameterResetButton = [NSButton buttonWithTitle:@"Reset Controls" target:self action:@selector(resetParameters:)];
    _parameterResetButton.bezelStyle = NSBezelStyleRounded;
    _parameterResetButton.enabled = NO;
    [_parameterShell addSubview:_parameterResetButton];
}

- (void)layoutChrome {
    NSRect bounds = _content.bounds;
    _bar.frame = NSMakeRect(0, bounds.size.height - _barH, bounds.size.width, _barH);
    _workspace.frame = NSMakeRect(0, 0, bounds.size.width, MAX(1, bounds.size.height - _barH));

    [self layoutBarControls];
    [self layoutWorkspace];
}

- (void)layoutBarControls {
    const CGFloat pad = 14.0;
    const CGFloat pickerH = 28.0;
    const CGFloat y = floor((_barH - pickerH) * 0.5);
    _captureLabel.frame = NSMakeRect(pad, y + 3.0, 56.0, 20.0);

    CGFloat statusW = _bar.bounds.size.width >= 1080.0 ? 250.0 : (_bar.bounds.size.width >= 960.0 ? 170.0 : 0.0);
    _statusLabel.hidden = statusW == 0.0;
    _statusLabel.frame = NSMakeRect(MAX(pad, _bar.bounds.size.width - pad - statusW), y + 3.0, statusW, 20.0);

    CGFloat right = _statusLabel.hidden ? _bar.bounds.size.width - pad : NSMinX(_statusLabel.frame) - 10.0;
    _startStop.frame = NSMakeRect(right - 92.0, y - 1.0, 92.0, 30.0);
    _exportButton.frame = NSMakeRect(NSMinX(_startStop.frame) - 82.0, y - 1.0, 76.0, 30.0);
    _compareBypassButton.frame = NSMakeRect(NSMinX(_exportButton.frame) - 102.0, y - 1.0, 96.0, 30.0);
    _compareModeControl.frame = NSMakeRect(NSMinX(_compareBypassButton.frame) - 118.0, y - 1.0, 112.0, 30.0);
    _rescanButton.frame = NSMakeRect(NSMinX(_compareModeControl.frame) - 78.0, y - 1.0, 72.0, 30.0);

    CGFloat pickerX = NSMaxX(_captureLabel.frame) + 8.0;
    CGFloat pickerW = MAX(180.0, NSMinX(_rescanButton.frame) - 12.0 - pickerX);
    _targetPicker.frame = NSMakeRect(pickerX, y, pickerW, pickerH);
}

- (void)layoutWorkspace {
    NSRect bounds = _workspace.bounds;
    CGFloat surfaceW = _overlayMode ? bounds.size.width : MIN(340.0, MAX(280.0, floor(bounds.size.width * 0.28)));
    if (_overlayMode) {
        _viewHost.hidden = YES;
        _controlSurface.frame = bounds;
    } else {
        _viewHost.hidden = NO;
        _viewHost.frame = NSMakeRect(0, 0, MAX(1.0, bounds.size.width - surfaceW), bounds.size.height);
        _controlSurface.frame = NSMakeRect(NSMaxX(_viewHost.frame), 0, surfaceW, bounds.size.height);
        _view.frame = _viewHost.bounds;
        _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }
    [self layoutControlSurface];
}

- (void)layoutControlSurface {
    NSRect bounds = _controlSurface.bounds;
    const CGFloat pad = 14.0;
    const CGFloat sectionTitleH = 20.0;
    const CGFloat gap = 10.0;
    const CGFloat sectionGap = 18.0;
    CGFloat shellH = MIN(292.0, MAX(246.0, floor(bounds.size.height * 0.45)));
    CGFloat scrollH = MAX(120.0, bounds.size.height - (pad * 2.0) - sectionTitleH - gap - sectionGap - sectionTitleH - gap - shellH);

    CGFloat y = bounds.size.height - pad - sectionTitleH;
    _presetDeckLabel.frame = NSMakeRect(pad, y, bounds.size.width - pad * 2.0, sectionTitleH);
    y -= (gap + scrollH);
    _presetDeckScroll.frame = NSMakeRect(pad, y, bounds.size.width - pad * 2.0, scrollH);
    y -= (sectionGap + sectionTitleH);
    _controlShellLabel.frame = NSMakeRect(pad, y, bounds.size.width - pad * 2.0, sectionTitleH);
    y -= (gap + shellH);
    _parameterShell.frame = NSMakeRect(pad, MAX(pad, y), bounds.size.width - pad * 2.0, shellH);

    [self layoutPresetDeckButtons];
    [self layoutParameterShell];
}

- (void)layoutPresetDeckButtons {
    const CGFloat rowH = 52.0;
    const CGFloat gap = 8.0;
    CGFloat contentW = MAX(1.0, _presetDeckScroll.contentSize.width);
    CGFloat y = gap;
    for (SGPresetDeckButton* button in _presetButtons) {
        button.frame = NSMakeRect(0, y, contentW, rowH);
        y += rowH + gap;
    }
    _presetDeckContent.frame = NSMakeRect(0, 0, contentW, y);
}

- (void)layoutParameterShell {
    NSRect bounds = _parameterShell.bounds;
    const CGFloat pad = 12.0;
    const CGFloat labelW = 84.0;
    const CGFloat rowH = 22.0;
    CGFloat y = bounds.size.height - pad - 34.0;
    _parameterHint.frame = NSMakeRect(pad, y, bounds.size.width - pad * 2.0, 32.0);

    y -= 34.0;
    _parameterIntensityLabel.frame = NSMakeRect(pad, y + 2.0, labelW, rowH);
    _parameterIntensitySlider.frame = NSMakeRect(pad + labelW, y - 2.0, bounds.size.width - (pad * 2.0) - labelW, 24.0);

    y -= 34.0;
    _parameterScanLabel.frame = NSMakeRect(pad, y + 2.0, labelW, rowH);
    _parameterScanSlider.frame = NSMakeRect(pad + labelW, y - 2.0, bounds.size.width - (pad * 2.0) - labelW, 24.0);

    y -= 34.0;
    _parameterMaskLabel.frame = NSMakeRect(pad, y + 2.0, labelW, rowH);
    _parameterMaskSlider.frame = NSMakeRect(pad + labelW, y - 2.0, bounds.size.width - (pad * 2.0) - labelW, 24.0);

    y -= 34.0;
    _parameterColorLabel.frame = NSMakeRect(pad, y + 2.0, labelW, rowH);
    _parameterColorSlider.frame = NSMakeRect(pad + labelW, y - 2.0, bounds.size.width - (pad * 2.0) - labelW, 24.0);

    y -= 34.0;
    _compareSplitLabel.frame = NSMakeRect(pad, y + 2.0, labelW, rowH);
    _compareSplitSlider.frame = NSMakeRect(pad + labelW, y - 2.0, bounds.size.width - (pad * 2.0) - labelW, 24.0);

    y -= 40.0;
    _parameterResetButton.frame = NSMakeRect(pad, y, 132.0, 28.0);
}

- (void)reloadShaderPresets {
    _shaderCatalog = [[LivePipeline shaderPresetCatalog] copy] ?: @[];
    for (NSView* view in _presetButtons) [view removeFromSuperview];
    [_presetButtons removeAllObjects];

    for (NSUInteger i = 0; i < _shaderCatalog.count; ++i) {
        SGShaderPresetDescriptor* descriptor = _shaderCatalog[i];
        SGPresetDeckButton* button = [[SGPresetDeckButton alloc] initWithFrame:NSZeroRect];
        button.tag = (NSInteger)i;
        button.target = self;
        button.action = @selector(presetSelected:);
        button.deckTitle = descriptor.title;
        button.deckCaption = descriptor.identifier;
        [_presetDeckContent addSubview:button];
        [_presetButtons addObject:button];
    }
    [self layoutPresetDeckButtons];
}

- (NSMutableDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>*)mutablePresetOverrideStore {
    NSDictionary* stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:SGPresetParameterOverridesKey];
    return stored ? [stored mutableCopy] : [NSMutableDictionary dictionary];
}

- (void)persistPresetOverrideStore:(NSDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>*)store {
    [[NSUserDefaults standardUserDefaults] setObject:store ?: @{} forKey:SGPresetParameterOverridesKey];
}

- (void)persistSelectedPresetIdentifier:(NSString*)identifier {
    if (identifier.length == 0) return;
    [[NSUserDefaults standardUserDefaults] setObject:identifier forKey:SGLastPresetIdentifierKey];
}

- (nullable SGShaderPresetDescriptor*)preferredPresetDescriptor {
    NSString* persistedIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:SGLastPresetIdentifierKey];
    if (persistedIdentifier.length > 0) {
        SGShaderPresetDescriptor* persisted = [LivePipeline shaderPresetForIdentifier:persistedIdentifier];
        if (persisted) return persisted;
    }
    NSString* activeIdentifier = _pipe.activeShaderPresetIdentifier;
    if (activeIdentifier.length > 0) {
        SGShaderPresetDescriptor* active = [LivePipeline shaderPresetForIdentifier:activeIdentifier];
        if (active) return active;
    }
    if (_pipe.activeShaderPresetDescriptor) return _pipe.activeShaderPresetDescriptor;
    return _shaderCatalog.firstObject;
}

- (void)applyPersistedParameterOverridesForCurrentPreset {
    if (_compareBypassActive) return;
    NSString* presetIdentifier = _pipe.activeShaderPresetIdentifier;
    if (presetIdentifier.length == 0) return;
    NSDictionary* allOverrides = [[NSUserDefaults standardUserDefaults] dictionaryForKey:SGPresetParameterOverridesKey];
    NSDictionary<NSString*, NSNumber*>* presetOverrides = allOverrides[presetIdentifier];
    if (presetOverrides.count == 0) {
        [self refreshParameterControls];
        return;
    }
    for (SGParameterSnapshot* snapshot in [_pipe parameterSnapshots]) {
        NSNumber* value = presetOverrides[snapshot.identifier];
        if (!value) continue;
        [_pipe updateParameterValue:value.floatValue forIdentifier:snapshot.identifier];
    }
    [self refreshParameterControls];
}

- (void)persistParameterOverrideForIdentifier:(NSString*)identifier value:(float)value {
    NSString* presetIdentifier = _pipe.activeShaderPresetIdentifier;
    if (presetIdentifier.length == 0 || identifier.length == 0) return;
    NSMutableDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>* store = [self mutablePresetOverrideStore];
    NSMutableDictionary<NSString*, NSNumber*>* presetOverrides = [store[presetIdentifier] mutableCopy] ?: [NSMutableDictionary dictionary];
    presetOverrides[identifier] = @(value);
    store[presetIdentifier] = [presetOverrides copy];
    [self persistPresetOverrideStore:store];
}

- (void)clearParameterOverridesForCurrentPreset {
    NSString* presetIdentifier = _pipe.activeShaderPresetIdentifier;
    if (presetIdentifier.length == 0) return;
    NSMutableDictionary<NSString*, NSDictionary<NSString*, NSNumber*>*>* store = [self mutablePresetOverrideStore];
    [store removeObjectForKey:presetIdentifier];
    [self persistPresetOverrideStore:store];
}

- (void)applyInitialPresetSelection {
    SGShaderPresetDescriptor* preferred = [self preferredPresetDescriptor];
    if (preferred) {
        BOOL shouldApply = ![_pipe.activeShaderPresetIdentifier isEqualToString:preferred.identifier];
        [self selectPresetDescriptor:preferred applyToPipeline:shouldApply];
        [self persistSelectedPresetIdentifier:preferred.identifier];
        [self applyPersistedParameterOverridesForCurrentPreset];
    } else {
        [self refreshParameterControls];
        [self refreshCompareControls];
    }
}

- (void)selectPresetDescriptor:(SGShaderPresetDescriptor*)descriptor applyToPipeline:(BOOL)applyToPipeline {
    if (!descriptor) return;

    if (applyToPipeline) {
        BOOL switched = [_pipe setShaderPresetIdentifier:descriptor.identifier];
        if (!switched) [_pipe setShaderKind:descriptor.legacyKind];
        [self persistSelectedPresetIdentifier:descriptor.identifier];
        [self applyPersistedParameterOverridesForCurrentPreset];
        [self updateStatusLabel:[NSString stringWithFormat:@"Preset: %@", descriptor.title]];
    }

    for (NSUInteger i = 0; i < _shaderCatalog.count && i < _presetButtons.count; ++i) {
        SGShaderPresetDescriptor* candidate = _shaderCatalog[i];
        SGPresetDeckButton* button = _presetButtons[i];
        BOOL selected = [candidate.identifier isEqualToString:descriptor.identifier];
        button.deckSelected = selected;
        button.deckCaption = selected ? @"Active preset" : candidate.identifier;
    }
    [self refreshParameterControls];
    [self refreshCompareControls];
}

- (void)applyPresetFromIndex:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_shaderCatalog.count) return;
    [self selectPresetDescriptor:_shaderCatalog[(NSUInteger)index] applyToPipeline:YES];
}

- (void)presetSelected:(id)sender {
    if (_compareBypassActive) return;
    [self applyPresetFromIndex:[sender tag]];
}

- (void)updateStatusLabel:(NSString*)text {
    _statusLabel.stringValue = text ?: @"";
}

- (NSString*)captureTargetPersistenceKeyForItem:(SGTargetItem*)item {
    if (!item) return @"";
    return [NSString stringWithFormat:@"%ld:%u", (long)item.kind, item.targetID];
}

- (void)updateCaptureSelectionState {
    BOOL hasTarget = (((SGTargetItem*)_targetPicker.selectedItem.representedObject) != nil);
    _startStop.enabled = hasTarget && !_captureStarting;
}

- (void)persistSelectedCaptureTarget {
    SGTargetItem* item = (SGTargetItem*)_targetPicker.selectedItem.representedObject;
    if (!item) return;
    [[NSUserDefaults standardUserDefaults] setObject:[self captureTargetPersistenceKeyForItem:item]
                                              forKey:SGLastCaptureTargetKey];
}

- (void)restoreSelectedCaptureTargetIfPossible {
    NSString* lastTarget = [[NSUserDefaults standardUserDefaults] stringForKey:SGLastCaptureTargetKey];
    BOOL matched = NO;
    if (lastTarget.length > 0) {
        for (NSMenuItem* menuItem in _targetPicker.itemArray) {
            SGTargetItem* item = (SGTargetItem*)menuItem.representedObject;
            if (item && [[self captureTargetPersistenceKeyForItem:item] isEqualToString:lastTarget]) {
                [_targetPicker selectItem:menuItem];
                matched = YES;
                break;
            }
        }
    }
    if (!matched) {
        for (NSMenuItem* menuItem in _targetPicker.itemArray) {
            if (menuItem.representedObject) {
                [_targetPicker selectItem:menuItem];
                matched = YES;
                break;
            }
        }
    }
    if (!matched && _targetPicker.numberOfItems > 0) [_targetPicker selectItemAtIndex:0];
    [self updateCaptureSelectionState];
}

- (void)captureTargetSelectionChanged:(id)sender {
    [self updateCaptureSelectionState];
}

- (nullable SGParameterSnapshot*)parameterSnapshotNamed:(NSString*)name {
    return [_pipe parameterSnapshotNamed:name];
}

- (void)configureSlider:(NSSlider*)slider
                  label:(NSTextField*)label
           withSnapshot:(nullable SGParameterSnapshot*)snapshot
          fallbackTitle:(NSString*)fallbackTitle {
    label.stringValue = fallbackTitle;
    if (!snapshot) {
        slider.enabled = NO;
        slider.minValue = 0.0;
        slider.maxValue = 1.0;
        slider.floatValue = 0.0f;
        return;
    }
    label.stringValue = snapshot.name;
    slider.enabled = YES;
    slider.minValue = snapshot.minimumValue;
    slider.maxValue = snapshot.maximumValue;
    slider.floatValue = snapshot.currentValue;
}

- (void)refreshParameterControls {
    [self configureSlider:_parameterIntensitySlider
                    label:_parameterIntensityLabel
             withSnapshot:[self parameterSnapshotNamed:@"SGIntensity"]
            fallbackTitle:@"Intensity"];
    [self configureSlider:_parameterScanSlider
                    label:_parameterScanLabel
             withSnapshot:[self parameterSnapshotNamed:@"SGScanlineStrength"]
            fallbackTitle:@"Scanlines"];
    [self configureSlider:_parameterMaskSlider
                    label:_parameterMaskLabel
             withSnapshot:[self parameterSnapshotNamed:@"SGMaskStrength"]
            fallbackTitle:@"Mask"];
    [self configureSlider:_parameterColorSlider
                    label:_parameterColorLabel
             withSnapshot:[self parameterSnapshotNamed:@"SGColorBoost"]
            fallbackTitle:@"Color Boost"];
    BOOL anyEnabled = _parameterIntensitySlider.enabled || _parameterScanSlider.enabled ||
                      _parameterMaskSlider.enabled || _parameterColorSlider.enabled;
    BOOL controlsEnabled = anyEnabled && !_compareBypassActive;
    _parameterIntensitySlider.enabled = _parameterIntensitySlider.enabled && controlsEnabled;
    _parameterScanSlider.enabled = _parameterScanSlider.enabled && controlsEnabled;
    _parameterMaskSlider.enabled = _parameterMaskSlider.enabled && controlsEnabled;
    _parameterColorSlider.enabled = _parameterColorSlider.enabled && controlsEnabled;
    _parameterResetButton.enabled = controlsEnabled;
    _parameterHint.stringValue = anyEnabled
        ? (_compareBypassActive
            ? @"Bypass is held. Release to return to the active preset controls."
            : @"These controls update the active preset live through the shared engine.")
        : @"This preset is not exposing live controls yet.";
}

- (void)refreshCompareControls {
    BOOL supportsCompare = ![_pipe.activeShaderPresetIdentifier isEqualToString:@"passthrough"];
    if (!supportsCompare && _pipe.compareMode != SGCompareModeOff)
        [self applyCompareModeSelection:SGCompareModeOff updatePipeline:YES];
    _compareModeControl.enabled = supportsCompare && !_compareBypassActive;
    _compareModeControl.selectedSegment = (_pipe.compareMode == SGCompareModeSplit) ? 1 : 0;
    _compareSplitSlider.floatValue = _pipe.compareSplitPosition;
    _compareSplitSlider.enabled = supportsCompare && !_compareBypassActive && _pipe.compareMode == SGCompareModeSplit;
    _compareBypassButton.enabled = supportsCompare;
    _compareBypassButton.title = _compareBypassActive ? @"Release Bypass" : @"Bypass";
    for (SGPresetDeckButton* button in _presetButtons) button.enabled = !_compareBypassActive;
}

- (void)applyCompareModeSelection:(SGCompareMode)mode updatePipeline:(BOOL)updatePipeline {
    if (updatePipeline) [_pipe setCompareMode:mode];
    _compareModeControl.selectedSegment = (mode == SGCompareModeSplit) ? 1 : 0;
    [self refreshCompareControls];
}

- (void)compareModeChanged:(id)sender {
    if (_compareBypassActive) {
        [self refreshCompareControls];
        return;
    }
    SGCompareMode mode = (_compareModeControl.selectedSegment == 1) ? SGCompareModeSplit : SGCompareModeOff;
    [self applyCompareModeSelection:mode updatePipeline:YES];
    [self updateStatusLabel:(mode == SGCompareModeSplit) ? @"Split compare" : @"Compare off"];
}

- (void)compareSplitPositionChanged:(NSSlider*)sender {
    [_pipe setCompareSplitPosition:sender.floatValue];
    [self updateStatusLabel:[NSString stringWithFormat:@"Split %.0f%%", sender.floatValue * 100.0f]];
}

- (void)parameterSliderChanged:(NSSlider*)sender {
    if (_compareBypassActive) return;
    NSString* name = nil;
    if (sender == _parameterIntensitySlider) name = @"SGIntensity";
    else if (sender == _parameterScanSlider) name = @"SGScanlineStrength";
    else if (sender == _parameterMaskSlider) name = @"SGMaskStrength";
    else if (sender == _parameterColorSlider) name = @"SGColorBoost";
    if (name.length == 0) return;

    SGParameterSnapshot* snapshot = [self parameterSnapshotNamed:name];
    if (!snapshot) return;
    [_pipe updateParameterValue:sender.floatValue forIdentifier:snapshot.identifier];
    [self persistParameterOverrideForIdentifier:snapshot.identifier value:sender.floatValue];
    [self updateStatusLabel:[NSString stringWithFormat:@"%@ %.2f", snapshot.name, sender.floatValue]];
}

- (void)resetParameters:(id)sender {
    if (_compareBypassActive) return;
    if ([_pipe resetAllParameters]) {
        [self clearParameterOverridesForCurrentPreset];
        [self refreshParameterControls];
        [self updateStatusLabel:@"Controls reset"];
    }
}

- (void)windowDidResize:(NSNotification*)note {
    [self layoutChrome];
}

- (void)rescanTargets:(id)sender { [self refreshTargets]; }

- (void)captureDidReportStarted:(BOOL)started message:(NSString*)message {
    if (started) {
        _captureStarting = NO;
        _capturing = YES;
        _startStop.enabled = YES;
        _startStop.title = @"Stop";
        [self updateStatusLabel:@"Capture running"];
        NSLog(@"ShaderGlass: capture started");
        return;
    }

    NSLog(@"ShaderGlass: capture failed: %@", message ?: @"unknown error");
    [self cancelBypassCompare];
    [_pipe stopCapture];
    _captureStarting = NO;
    _capturing = NO;
    [self leaveOverlayMode];
    _startStop.enabled = YES;
    _startStop.title = @"Start";
    [self updateStatusLabel:@"Capture failed"];
    [self refreshTargets];
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
    _view.frame = _viewHost.bounds;
    _view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_viewHost addSubview:_view];
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

    _overlayMode = YES;
    _window.minSize = NSMakeSize(460, 420);
    NSRect controlsFrame = NSMakeRect(f.origin.x + 24.0, NSMaxY(f) - 560.0, 480.0, 520.0);
    [_window setFrame:controlsFrame display:YES];
    _window.title = @"ShaderGlass Controls";
    _window.level = overlayLevel + 1;
    _window.collectionBehavior = (NSWindowCollectionBehaviorCanJoinAllSpaces |
                                  NSWindowCollectionBehaviorFullScreenAuxiliary);
    [self updateStatusLabel:@"Overlay capture armed"];
    [self layoutChrome];
    [_window makeKeyAndOrderFront:nil];

    NSLog(@"ShaderGlass: overlay display %u screen=%@ level=%ld controls=%ld excluded=%@",
          (unsigned)displayID, NSStringFromRect(f), (long)_overlayWindow.level,
          (long)_window.level, [self captureExclusionWindowIDs]);
    return YES;
}

- (void)leaveOverlayMode {
    if (!_overlayMode) return;
    [self cancelBypassCompare];
    [_overlayWindow orderOut:nil];
    [_overlayWindow close];
    _overlayWindow = nil;

    _window.title = @"ShaderGlass (macOS)";
    _window.level = NSNormalWindowLevel;
    _window.collectionBehavior = NSWindowCollectionBehaviorManaged;
    _window.minSize = NSMakeSize(860, 560);
    _overlayMode = NO;
    [_window setFrame:_normalWindowFrame display:YES];
    [self installMetalViewInCloneWindow];
    [self updateStatusLabel:_capturing ? @"Capture running" : @"Previewing sample image"];
    [self layoutChrome];
    [_window makeKeyAndOrderFront:nil];
}

// ---- capture target enumeration (TCC gate) ----
- (void)refreshTargets {
    if (@available(macOS 12.3, *)) {
        [SCShareableContent getShareableContentWithCompletionHandler:^(SCShareableContent* c, NSError* e) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self->_targetPicker removeAllItems];
                if (!c || e) {
                    [self->_targetPicker.menu addItem:SGDisabledMenuItem(@"Screen Recording Permission Needed")];
                    [self updateStatusLabel:@"Screen Recording permission needed"];
                    [self updateCaptureSelectionState];
                    return;
                }

                NSMutableArray<SCDisplay*>* displays = [c.displays mutableCopy] ?: [NSMutableArray array];
                [displays sortUsingComparator:^NSComparisonResult(SCDisplay* a, SCDisplay* b) {
                    if (a.displayID < b.displayID) return NSOrderedAscending;
                    if (a.displayID > b.displayID) return NSOrderedDescending;
                    return NSOrderedSame;
                }];

                NSMutableArray<SCWindow*>* windows = [NSMutableArray array];
                for (SCWindow* w in c.windows) {
                    if (!SGShouldOfferWindowCapture(w)) continue;
                    [windows addObject:w];
                }
                [windows sortUsingComparator:^NSComparisonResult(SCWindow* a, SCWindow* b) {
                    NSString* appA = a.owningApplication.applicationName ?: @"";
                    NSString* appB = b.owningApplication.applicationName ?: @"";
                    NSComparisonResult appCmp = [appA localizedCaseInsensitiveCompare:appB];
                    if (appCmp != NSOrderedSame) return appCmp;
                    NSComparisonResult titleCmp = [a.title localizedCaseInsensitiveCompare:b.title];
                    if (titleCmp != NSOrderedSame) return titleCmp;
                    if (a.windowID < b.windowID) return NSOrderedAscending;
                    if (a.windowID > b.windowID) return NSOrderedDescending;
                    return NSOrderedSame;
                }];

                if (displays.count > 0) {
                    [self->_targetPicker.menu addItem:SGDisabledMenuItem(@"Displays")];
                }
                for (SCDisplay* d in displays) {
                    SGTargetItem* t = [SGTargetItem new];
                    t.kind = SGTargetDisplay; t.targetID = (uint32_t)d.displayID;
                    t.label = [NSString stringWithFormat:@"Glass Overlay — Display %u (%dx%d)", (unsigned)d.displayID, (int)d.width, (int)d.height];
                    [self->_targetPicker addItemWithTitle:t.label];
                    self->_targetPicker.lastItem.representedObject = t;
                }

                if (windows.count > 0 && displays.count > 0) {
                    [self->_targetPicker.menu addItem:[NSMenuItem separatorItem]];
                }
                if (windows.count > 0) {
                    [self->_targetPicker.menu addItem:SGDisabledMenuItem(@"Windows")];
                }
                for (SCWindow* w in windows) {
                    SGTargetItem* t = [SGTargetItem new];
                    t.kind = SGTargetWindow; t.targetID = (uint32_t)w.windowID;
                    NSString* app = w.owningApplication.applicationName ?: @"?";
                    t.label = [NSString stringWithFormat:@"Window Clone — %@ — %@ (%dx%d)",
                               app, w.title, (int)w.frame.size.width, (int)w.frame.size.height];
                    [self->_targetPicker addItemWithTitle:t.label];
                    self->_targetPicker.lastItem.representedObject = t;
                }

                if (displays.count == 0 && windows.count == 0) {
                    [self->_targetPicker.menu addItem:SGDisabledMenuItem(@"No Capture Targets Available")];
                    [self updateStatusLabel:@"No capturable displays or windows found"];
                } else {
                    [self updateStatusLabel:@"Targets refreshed"];
                }
                [self restoreSelectedCaptureTargetIfPossible];
            });
        }];
    } else {
        [_targetPicker removeAllItems];
        [_targetPicker.menu addItem:SGDisabledMenuItem(@"Requires macOS 12.3+")];
        [self updateCaptureSelectionState];
        [self updateStatusLabel:@"Requires macOS 12.3+"];
    }
}

- (void)toggleCapture:(id)sender {
    if (_captureStarting) return;
    if (_capturing) {
        [self cancelBypassCompare];
        [_pipe stopCapture];
        _capturing = NO;
        _captureStarting = NO;
        [self leaveOverlayMode];
        _startStop.title = @"Start";
        _startStop.enabled = YES;
        [self updateStatusLabel:@"Previewing sample image"];
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
    [self persistSelectedCaptureTarget];
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
    [self updateStatusLabel:useOverlay ? @"Starting overlay capture" : @"Starting window capture"];
    BOOL accepted = [_pipe startCaptureKind:t.kind
                                   targetID:t.targetID
                         excludingWindowIDs:useOverlay ? [self captureExclusionWindowIDs] : nil];
    if (!accepted) {
        [self captureDidReportStarted:NO message:@"ScreenCaptureKit is unavailable or capture initialization failed."];
    }
}

- (void)installCompareKeyMonitors {
    __weak SGAppDelegate* weakSelf = self;
    _compareKeyDownMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
                                                                   handler:^NSEvent* _Nullable(NSEvent* event) {
        SGAppDelegate* self = weakSelf;
        if (!self) return event;
        if (event.keyCode == 49 && !event.isARepeat) {
            [self beginBypassCompare:nil];
            return nil;
        }
        return event;
    }];
    _compareKeyUpMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyUp
                                                                 handler:^NSEvent* _Nullable(NSEvent* event) {
        SGAppDelegate* self = weakSelf;
        if (!self) return event;
        if (event.keyCode == 49) {
            [self endBypassCompare:nil];
            return nil;
        }
        return event;
    }];
}

- (void)beginBypassCompare:(id)sender {
    if (_compareBypassActive) return;
    if ([_pipe beginBypassCompare]) {
        _compareBypassActive = YES;
        [self refreshCompareControls];
        [self refreshParameterControls];
        [self updateStatusLabel:@"Bypass compare"];
    }
}

- (void)cancelBypassCompare {
    if (_compareBypassActive) [self endBypassCompare:nil];
}

- (void)endBypassCompare:(id)sender {
    if (!_compareBypassActive) return;
    if ([_pipe endBypassCompare]) {
        _compareBypassActive = NO;
        [self refreshCompareControls];
        [self refreshParameterControls];
        SGShaderPresetDescriptor* descriptor = _pipe.activeShaderPresetDescriptor;
        [self updateStatusLabel:descriptor ? [NSString stringWithFormat:@"Preset: %@", descriptor.title]
                                          : @"Compare released"];
    }
}

- (void)toggleSplitCompare:(id)sender {
    SGCompareMode nextMode = (_pipe.compareMode == SGCompareModeSplit) ? SGCompareModeOff : SGCompareModeSplit;
    [self applyCompareModeSelection:nextMode updatePipeline:YES];
    [self updateStatusLabel:(nextMode == SGCompareModeSplit) ? @"Split compare" : @"Compare off"];
}

- (void)exportMoment:(id)sender {
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.allowedContentTypes = @[UTTypePNG];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"ShaderGlass-%@.png",
                                  [[NSDateFormatter localizedStringFromDate:[NSDate date]
                                                                 dateStyle:NSDateFormatterNoStyle
                                                                 timeStyle:NSDateFormatterMediumStyle]
                                   stringByReplacingOccurrencesOfString:@":" withString:@"-"]];
    [panel beginSheetModalForWindow:_window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        self->_exportButton.enabled = NO;
        [self updateStatusLabel:@"Exporting frame"];
        [self->_pipe exportMomentToURL:panel.URL completion:^(BOOL success, NSString* message) {
            self->_exportButton.enabled = YES;
            [self updateStatusLabel:success ? @"Frame exported" : @"Export failed"];
            if (!success) {
                NSAlert* alert = [[NSAlert alloc] init];
                alert.messageText = @"Export failed";
                alert.informativeText = message.length ? message : @"ShaderGlass could not export the current frame.";
                [alert beginSheetModalForWindow:self->_window completionHandler:nil];
            }
        }];
    }];
}

- (void)showTCCDeniedAlert {
    [self cancelBypassCompare];
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
    [self cancelBypassCompare];
    NSAlert* a = [[NSAlert alloc] init];
    a.messageText = @"ShaderGlass"; a.informativeText = msg;
    [a runModal];
    [NSApp terminate:nil];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)app { return YES; }
- (void)applicationWillTerminate:(NSNotification*)note {
    [self cancelBypassCompare];
    if (_compareKeyDownMonitor) [NSEvent removeMonitor:_compareKeyDownMonitor];
    if (_compareKeyUpMonitor) [NSEvent removeMonitor:_compareKeyUpMonitor];
    [_redrawTimer invalidate];
    [_pipe shutdown];
}

@end
