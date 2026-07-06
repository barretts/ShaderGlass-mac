/*
ShaderGlass macOS port -- LivePipeline.mm
*/

#import "LivePipeline.h"
#import "EngineBridge.h"
#import <Metal/Metal.h>
#include "../backend/sg_image.h"
#include "../capture/SCKCapture.h"
#include <atomic>
#include <cmath>
#include <unordered_map>
#include <string>
#include <vector>
#include <cstring>

using namespace sg;

static std::string readTextFile(NSString* path) {
    NSError* e = nil;
    NSString* s = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&e];
    return s ? std::string(s.UTF8String) : std::string();
}

@interface SGShaderPresetDescriptor ()
- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                    shaderFilename:(NSString*)shaderFilename
                        legacyKind:(SGShaderKind)legacyKind
                   legacyMenuIndex:(NSInteger)legacyMenuIndex;
@end

@implementation SGShaderPresetDescriptor

- (instancetype)initWithIdentifier:(NSString*)identifier
                             title:(NSString*)title
                    shaderFilename:(NSString*)shaderFilename
                        legacyKind:(SGShaderKind)legacyKind
                   legacyMenuIndex:(NSInteger)legacyMenuIndex {
    self = [super init];
    if (!self) return nil;
    _identifier = [identifier copy];
    _title = [title copy];
    _shaderFilename = [shaderFilename copy];
    _legacyKind = legacyKind;
    _legacyMenuIndex = legacyMenuIndex;
    return self;
}

@end

static NSArray<SGShaderPresetDescriptor*>* SGShaderPresetCatalog(void) {
    static NSArray<SGShaderPresetDescriptor*>* catalog = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = @[
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"passthrough"
                                                           title:@"Passthrough"
                                                  shaderFilename:@"passthrough.metal"
                                                      legacyKind:SGShaderPassthrough
                                                 legacyMenuIndex:0],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"crt"
                                                           title:@"CRT"
                                                  shaderFilename:@"crt_demo.metal"
                                                      legacyKind:SGShaderCRT
                                                 legacyMenuIndex:1],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"crt-pro"
                                                           title:@"CRT Pro"
                                                  shaderFilename:@"crt_pro.metal"
                                                      legacyKind:SGShaderCRTPro
                                                 legacyMenuIndex:2],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"lcd-grid"
                                                           title:@"LCD Grid"
                                                  shaderFilename:@"lcd_grid.metal"
                                                      legacyKind:SGShaderLCDGrid
                                                 legacyMenuIndex:3],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"amber-mono"
                                                           title:@"Amber Mono"
                                                  shaderFilename:@"amber_mono.metal"
                                                      legacyKind:SGShaderAmberMono
                                                 legacyMenuIndex:4],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"vhs-soft"
                                                           title:@"VHS Soft"
                                                  shaderFilename:@"vhs_soft.metal"
                                                      legacyKind:SGShaderVHSSoft
                                                 legacyMenuIndex:5],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"green-mono"
                                                           title:@"Green Mono"
                                                  shaderFilename:@"green_mono.metal"
                                                      legacyKind:SGShaderGreenMono
                                                 legacyMenuIndex:6],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"pixel-grid"
                                                           title:@"Pixel Grid"
                                                  shaderFilename:@"pixel_grid.metal"
                                                      legacyKind:SGShaderPixelGrid
                                                 legacyMenuIndex:7],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"bloom-soft"
                                                           title:@"Bloom Soft"
                                                  shaderFilename:@"bloom_soft.metal"
                                                      legacyKind:SGShaderBloomSoft
                                                 legacyMenuIndex:8],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"pvm-slots"
                                                           title:@"PVM Slots"
                                                  shaderFilename:@"pvm_slots.metal"
                                                      legacyKind:SGShaderPVMSlots
                                                 legacyMenuIndex:9],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"noir-film"
                                                           title:@"Noir Film"
                                                  shaderFilename:@"noir_film.metal"
                                                      legacyKind:SGShaderNoirFilm
                                                 legacyMenuIndex:10],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"thermal-pop"
                                                           title:@"Thermal Pop"
                                                  shaderFilename:@"thermal_pop.metal"
                                                      legacyKind:SGShaderThermalPop
                                                 legacyMenuIndex:11],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"dream-blur"
                                                           title:@"Dream Blur"
                                                  shaderFilename:@"dream_blur.metal"
                                                      legacyKind:SGShaderDreamBlur
                                                 legacyMenuIndex:12],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"cyber-glow"
                                                           title:@"Cyber Glow"
                                                  shaderFilename:@"cyber_glow.metal"
                                                      legacyKind:SGShaderCyberGlow
                                                 legacyMenuIndex:13],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"amber-crt"
                                                           title:@"Amber CRT"
                                                  shaderFilename:@"amber_crt.metal"
                                                      legacyKind:SGShaderAmberCRT
                                                 legacyMenuIndex:14],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"blue-terminal"
                                                           title:@"Blue Terminal"
                                                  shaderFilename:@"blue_terminal.metal"
                                                      legacyKind:SGShaderBlueTerminal
                                                 legacyMenuIndex:15],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"hologram-glass"
                                                           title:@"Hologram Glass"
                                                  shaderFilename:@"hologram_glass.metal"
                                                      legacyKind:SGShaderHologramGlass
                                                 legacyMenuIndex:16],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"data-grid"
                                                           title:@"Data Grid"
                                                  shaderFilename:@"data_grid.metal"
                                                      legacyKind:SGShaderDataGrid
                                                 legacyMenuIndex:17],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"night-vision-hud"
                                                           title:@"Night Vision HUD"
                                                  shaderFilename:@"night_vision_hud.metal"
                                                      legacyKind:SGShaderNightVisionHUD
                                                 legacyMenuIndex:18],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"ice-crt"
                                                           title:@"Ice CRT"
                                                  shaderFilename:@"ice_crt.metal"
                                                      legacyKind:SGShaderIceCRT
                                                 legacyMenuIndex:19],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"vector-scope"
                                                           title:@"Vector Scope"
                                                  shaderFilename:@"vector_scope.metal"
                                                      legacyKind:SGShaderVectorScope
                                                 legacyMenuIndex:20],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"plasma-desk"
                                                           title:@"Plasma Desk"
                                                  shaderFilename:@"plasma_desk.metal"
                                                      legacyKind:SGShaderPlasmaDesk
                                                 legacyMenuIndex:21],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"security-cam-clean"
                                                           title:@"Security Cam Clean"
                                                  shaderFilename:@"security_cam_clean.metal"
                                                      legacyKind:SGShaderSecurityCamClean
                                                 legacyMenuIndex:22],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"hotdog-pro"
                                                           title:@"Hotdog Pro"
                                                  shaderFilename:@"hotdog_pro.metal"
                                                      legacyKind:SGShaderHotdogPro
                                                 legacyMenuIndex:23],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"dino-park"
                                                           title:@"Dino Park"
                                                  shaderFilename:@"dino_park.metal"
                                                      legacyKind:SGShaderDinoPark
                                                 legacyMenuIndex:24],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"game-boy"
                                                           title:@"Game Boy"
                                                  shaderFilename:@"game_boy.metal"
                                                      legacyKind:SGShaderGameBoy
                                                 legacyMenuIndex:25],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"snes-pop"
                                                           title:@"SNES Pop"
                                                  shaderFilename:@"snes_pop.metal"
                                                      legacyKind:SGShaderSNESPop
                                                 legacyMenuIndex:26],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"green-crt"
                                                           title:@"Green CRT"
                                                  shaderFilename:@"green_crt.metal"
                                                      legacyKind:SGShaderGreenCRT
                                                 legacyMenuIndex:27],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"ntsc-composite"
                                                           title:@"NTSC Composite"
                                                  shaderFilename:@"ntsc_composite.metal"
                                                      legacyKind:SGShaderNTSCComposite
                                                 legacyMenuIndex:28],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"crt-geom-style"
                                                           title:@"CRT Geom"
                                                  shaderFilename:@"crt_geom_style.metal"
                                                      legacyKind:SGShaderCRTGeomStyle
                                                 legacyMenuIndex:29],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"crt-easymode-style"
                                                           title:@"CRT Easymode"
                                                  shaderFilename:@"crt_easymode_style.metal"
                                                      legacyKind:SGShaderCRTEasymodeStyle
                                                 legacyMenuIndex:30],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"newpixie-crt"
                                                           title:@"Newpixie CRT"
                                                  shaderFilename:@"newpixie_crt.metal"
                                                      legacyKind:SGShaderNewpixieCRT
                                                 legacyMenuIndex:31],
            [[SGShaderPresetDescriptor alloc] initWithIdentifier:@"c64-monitor"
                                                           title:@"C64 Monitor"
                                                  shaderFilename:@"c64_monitor.metal"
                                                      legacyKind:SGShaderC64Monitor
                                                 legacyMenuIndex:32],
        ];
    });
    return catalog;
}

static SGShaderPresetDescriptor* SGShaderPresetForIdentifier(NSString* identifier) {
    if (identifier.length == 0) return nil;
    for (SGShaderPresetDescriptor* descriptor in SGShaderPresetCatalog()) {
        if ([descriptor.identifier isEqualToString:identifier]) return descriptor;
    }
    return nil;
}

static SGShaderPresetDescriptor* SGShaderPresetForLegacyKind(SGShaderKind kind) {
    for (SGShaderPresetDescriptor* descriptor in SGShaderPresetCatalog()) {
        if (descriptor.legacyKind == kind) return descriptor;
    }
    return nil;
}

// Private methods used before their definition (FrameSink lambda, render-thread routing).
@interface LivePipeline ()
- (void)onCaptureFrameTex:(BackendTexture*)tex w:(uint32_t)w h:(uint32_t)h frame:(uint32_t)frameCount;
- (void)drawSrc:(BackendTexture*)src toTarget:(BackendTexture*)target
           srcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
      frameCount:(uint32_t)frameCount;
- (void)renderFrameLocked;
- (void)applyPresetDescriptorLocked:(SGShaderPresetDescriptor*)descriptor updateSelectionState:(BOOL)updateSelectionState;
@end

@implementation LivePipeline {
    EngineBridge*    _bridge;
    SCKCapture*      _capture;            // C++ owned; created on first startCapture
    std::unordered_map<std::string, std::string> _shaderSourcesByIdentifier;
    SGShaderKind     _activeShaderKind;
    NSString*        _activeShaderPresetIdentifier;

    // static-image source (L1/L2)
    BackendTexture*  _staticSrc;
    uint32_t         _srcW, _srcH;        // current source dimensions
    uint32_t         _dstW, _dstH;        // current drawable dimensions (render-thread-only once capturing)
    std::atomic<bool> _capturing;         // read across threads; gates the render-thread routing
    dispatch_queue_t  _renderQueue;       // == SCKCapture's serial queue while capturing; the sole render thread
    NSURL*            _pendingExportURL;
    void (^_pendingExportCompletion)(BOOL success, NSString* _Nullable message);
    BOOL              _bypassCompareActive;
    NSString*         _bypassSavedPresetIdentifier;
    NSArray<NSDictionary<NSString*, id>*>* _bypassSavedParameterValues;
    SGCompareMode     _compareMode;
    float             _compareSplitPosition;
    BackendTexture*   _compareProcessedTexture;
    uint32_t          _compareProcessedWidth;
    uint32_t          _compareProcessedHeight;
}

- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                             shaderDir:(NSString*)shaderDir {
    self = [super init];
    if (!self) return nil;

    for (SGShaderPresetDescriptor* descriptor in SGShaderPresetCatalog()) {
        std::string src = readTextFile([shaderDir stringByAppendingPathComponent:descriptor.shaderFilename]);
        if (src.empty()) {
            NSLog(@"LivePipeline: cannot read shader %@ from %@", descriptor.shaderFilename, shaderDir);
            return nil;
        }
        _shaderSourcesByIdentifier[std::string(descriptor.identifier.UTF8String)] = std::move(src);
    }
    SGShaderPresetDescriptor* defaultPreset = SGShaderPresetForLegacyKind(SGShaderPassthrough);
    if (!defaultPreset) {
        NSLog(@"LivePipeline: missing default shader preset");
        return nil;
    }
    _activeShaderKind = defaultPreset.legacyKind;
    _activeShaderPresetIdentifier = [defaultPreset.identifier copy];
    const std::string& preprocessSource = _shaderSourcesByIdentifier[std::string(defaultPreset.identifier.UTF8String)];
    const std::string& shaderSource = _shaderSourcesByIdentifier[std::string(_activeShaderPresetIdentifier.UTF8String)];
    _bridge = [[EngineBridge alloc] initWithLayer:layer
                                            width:width
                                           height:height
                                preprocessSource:preprocessSource
                                    shaderSource:shaderSource];
    if (!_bridge) {
        NSLog(@"LivePipeline: EngineBridge init failed (no Metal device or shader compile error)");
        return nil;
    }
    __weak LivePipeline* weakSelf = self;
    _bridge.engineEventHandler = ^(SGEngineEvent event) {
        LivePipeline* s = weakSelf;
        if (!s || !s.engineEventHandler) return;
        if (event == SGEngineEventPresetChanged && s->_bypassCompareActive) return;
        s.engineEventHandler((NSInteger)event);
    };
    _dstW = width; _dstH = height;
    _compareMode = SGCompareModeOff;
    _compareSplitPosition = 0.5f;
    _compareProcessedTexture = nullptr;
    _compareProcessedWidth = 0;
    _compareProcessedHeight = 0;
    _capturing.store(false);
    [_bridge setPreprocessSource:preprocessSource
                    shaderSource:shaderSource
                        presetID:defaultPreset.identifier
                     displayName:defaultPreset.title
                        category:@"curated"];
    return self;
}

+ (NSArray<SGShaderPresetDescriptor*>*)shaderPresetCatalog {
    return SGShaderPresetCatalog();
}

+ (nullable SGShaderPresetDescriptor*)shaderPresetForIdentifier:(NSString*)identifier {
    return SGShaderPresetForIdentifier(identifier);
}

+ (nullable SGShaderPresetDescriptor*)shaderPresetForLegacyKind:(SGShaderKind)kind {
    return SGShaderPresetForLegacyKind(kind);
}

- (NSString*)activeShaderPresetIdentifier {
    return [_activeShaderPresetIdentifier copy];
}

- (SGShaderPresetDescriptor*)activeShaderPresetDescriptor {
    return SGShaderPresetForIdentifier(_activeShaderPresetIdentifier);
}

- (SGPresetMetadata*)activePresetMetadata {
    return [_bridge.activePresetMetadata copy];
}

- (BOOL)isBypassCompareActive {
    return _bypassCompareActive;
}

- (SGCompareMode)compareMode {
    return _compareMode;
}

- (float)compareSplitPosition {
    return _compareSplitPosition;
}

- (BOOL)setStaticImagePath:(NSString*)pngPath {
    uint32_t w=0, h=0; std::vector<uint8_t> px;
    if (!DecodeImageFileBGRA(pngPath.UTF8String, w, h, px)) {
        NSLog(@"LivePipeline: decode failed for %@", pngPath);
        return NO;
    }
    if (_staticSrc) { [_bridge destroyTexture:_staticSrc]; _staticSrc = nullptr; }
    _staticSrc = [_bridge createTexture:TextureDesc{w, h, PixFmt::BGRA8_UNORM, false, false} initialData:px.data() rowPitch:w*4];
    _srcW = w; _srcH = h;
    return _staticSrc != nullptr;
}

- (void)drawSrc:(BackendTexture*)src toTarget:(BackendTexture*)target
           srcW:(uint32_t)sw srcH:(uint32_t)sh dstW:(uint32_t)dw dstH:(uint32_t)dh
      frameCount:(uint32_t)frameCount {
    if (_compareMode == SGCompareModeSplit && !_bypassCompareActive) {
        BackendTexture* compositeTarget = target;
        BOOL borrowedFrameTarget = NO;
        if (!compositeTarget) {
            compositeTarget = [_bridge beginFrame];
            if (!compositeTarget) return;
            borrowedFrameTarget = YES;
        }

        if (!_compareProcessedTexture || _compareProcessedWidth != dw || _compareProcessedHeight != dh) {
            if (_compareProcessedTexture) {
                [_bridge destroyTexture:_compareProcessedTexture];
                _compareProcessedTexture = nullptr;
            }
            _compareProcessedTexture =
                [_bridge createTexture:TextureDesc {dw, dh, PixFmt::BGRA8_UNORM, true, true}
                           initialData:nullptr
                              rowPitch:0];
            _compareProcessedWidth = _compareProcessedTexture ? dw : 0;
            _compareProcessedHeight = _compareProcessedTexture ? dh : 0;
        }
        if (!_compareProcessedTexture) return;

        if (![_bridge renderSource:src
                       sourceWidth:sw
                      sourceHeight:sh
                          toTarget:_compareProcessedTexture
                       targetWidth:dw
                      targetHeight:dh
                        frameCount:frameCount]) {
            return;
        }
        if (![_bridge composeCompareOriginal:src
                                   processed:_compareProcessedTexture
                                    toTarget:compositeTarget
                                 targetWidth:dw
                                targetHeight:dh
                               splitPosition:_compareSplitPosition]) {
            return;
        }
        if (borrowedFrameTarget) [_bridge present];
        return;
    }
    [_bridge renderSource:src sourceWidth:sw sourceHeight:sh toTarget:target targetWidth:dw targetHeight:dh frameCount:frameCount];
}

// THREADING MODEL (REVIEW C1): the MetalBackend is touched from exactly one thread.
// While capturing, that thread is SCKCapture's serial render queue (_renderQueue);
// the FrameSink runs there and all other backend-touching work (resize, shader
// repaint) is marshaled onto it. While NOT capturing, the main thread owns the
// backend (the 30fps tick drives static redraws). runOnRenderThread routes accordingly.
- (void)runOnRenderThread:(dispatch_block_t)block {
    if (_capturing.load() && _renderQueue) dispatch_async(_renderQueue, block);
    else block();   // not capturing: caller is the main thread, which owns the backend
}

// Does the actual single-pass render+present. MUST run on the current render thread.
- (void)renderFrameLocked {
    if (!_staticSrc) return;
    @autoreleasepool {
        [self drawSrc:_staticSrc toTarget:nullptr
                 srcW:_srcW srcH:_srcH dstW:_dstW dstH:_dstH frameCount:0];
    }
}

// Public: the static-image repaint (timer / explicit). No-op while capturing (the
// capture queue drives frames). The atomic gate makes the cross-thread read safe.
- (void)renderFrame {
    if (_capturing.load()) return;   // capture path drives its own frames
    [self renderFrameLocked];
}

- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height {
    [self runOnRenderThread:^{
        _dstW = width; _dstH = height;          // render-thread-only once capturing
        [_bridge resizeToWidth:width height:height];
        if (!_capturing.load()) [self renderFrameLocked]; // capture path repaints next frame
    }];
}

- (BOOL)setShaderPresetIdentifier:(NSString*)identifier {
    SGShaderPresetDescriptor* descriptor = SGShaderPresetForIdentifier(identifier);
    if (!descriptor) return NO;
    [self runOnRenderThread:^{
        if ([_activeShaderPresetIdentifier isEqualToString:descriptor.identifier]) return;
        [self applyPresetDescriptorLocked:descriptor updateSelectionState:YES];
        if (_bypassCompareActive) return;
        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return YES;
}

- (void)setShaderKind:(SGShaderKind)kind {
    SGShaderPresetDescriptor* descriptor = SGShaderPresetForLegacyKind(kind);
    if (!descriptor) descriptor = SGShaderPresetForLegacyKind(SGShaderPassthrough);
    if (!descriptor) return;
    [self setShaderPresetIdentifier:descriptor.identifier];
}

- (NSArray<SGParameterSnapshot*>*)parameterSnapshots {
    return [_bridge parameterSnapshots];
}

- (nullable SGParameterSnapshot*)parameterSnapshotForIdentifier:(NSString*)identifier {
    return [_bridge parameterSnapshotForIdentifier:identifier];
}

- (nullable SGParameterSnapshot*)parameterSnapshotNamed:(NSString*)name {
    if (name.length == 0) return nil;
    for (SGParameterSnapshot* snapshot in [_bridge parameterSnapshots])
        if ([snapshot.name isEqualToString:name])
            return snapshot;
    return nil;
}

- (BOOL)updateParameterValue:(float)value forIdentifier:(NSString*)identifier {
    if (identifier.length == 0) return NO;
    if (_bypassCompareActive) return NO;
    __block BOOL queued = YES;
    [self runOnRenderThread:^{
        if (_bypassCompareActive) {
            queued = NO;
            return;
        }
        if (![_bridge updateParameterValue:value forIdentifier:identifier]) {
            queued = NO;
            return;
        }
        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return queued;
}

- (BOOL)resetParameterForIdentifier:(NSString*)identifier {
    if (identifier.length == 0) return NO;
    if (_bypassCompareActive) return NO;
    __block BOOL queued = YES;
    [self runOnRenderThread:^{
        if (_bypassCompareActive) {
            queued = NO;
            return;
        }
        if (![_bridge resetParameterForIdentifier:identifier]) {
            queued = NO;
            return;
        }
        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return queued;
}

- (BOOL)resetAllParameters {
    if (_bypassCompareActive) return NO;
    __block BOOL queued = YES;
    [self runOnRenderThread:^{
        if (_bypassCompareActive) {
            queued = NO;
            return;
        }
        if (![_bridge resetAllParameters]) {
            queued = NO;
            return;
        }
        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return queued;
}

- (void)applyPresetDescriptorLocked:(SGShaderPresetDescriptor*)descriptor updateSelectionState:(BOOL)updateSelectionState {
    if (!descriptor) return;
    if (updateSelectionState) {
        _activeShaderKind = descriptor.legacyKind;
        _activeShaderPresetIdentifier = [descriptor.identifier copy];
    }
    SGShaderPresetDescriptor* preprocessPreset = SGShaderPresetForLegacyKind(SGShaderPassthrough);
    const std::string& preprocessSource =
        _shaderSourcesByIdentifier[std::string(preprocessPreset.identifier.UTF8String)];
    const std::string& shaderSource =
        _shaderSourcesByIdentifier[std::string(descriptor.identifier.UTF8String)];
    [_bridge setPreprocessSource:preprocessSource
                    shaderSource:shaderSource
                        presetID:descriptor.identifier
                     displayName:descriptor.title
                        category:@"curated"];
}

- (BOOL)beginBypassCompare {
    if (_bypassCompareActive) return YES;
    __block BOOL started = YES;
    [self runOnRenderThread:^{
        SGShaderPresetDescriptor* activeDescriptor = SGShaderPresetForIdentifier(_activeShaderPresetIdentifier);
        SGShaderPresetDescriptor* passthroughDescriptor = SGShaderPresetForLegacyKind(SGShaderPassthrough);
        if (!activeDescriptor || !passthroughDescriptor ||
            [activeDescriptor.identifier isEqualToString:passthroughDescriptor.identifier]) {
            started = NO;
            return;
        }

        NSMutableArray<NSDictionary<NSString*, id>*>* saved = [NSMutableArray array];
        for (SGParameterSnapshot* snapshot in [_bridge parameterSnapshots]) {
            if (!snapshot.identifier.length) continue;
            [saved addObject:@{
                @"identifier": snapshot.identifier,
                @"value": @(snapshot.currentValue),
            }];
        }

        _bypassSavedPresetIdentifier = [_activeShaderPresetIdentifier copy];
        _bypassSavedParameterValues = [saved copy];
        _bypassCompareActive = YES;
        [self applyPresetDescriptorLocked:passthroughDescriptor updateSelectionState:NO];
        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return started;
}

- (BOOL)endBypassCompare {
    if (!_bypassCompareActive) return YES;
    __block BOOL ended = YES;
    [self runOnRenderThread:^{
        if (!_bypassCompareActive) return;

        NSString* selectedIdentifier = [_activeShaderPresetIdentifier copy];
        NSString* savedIdentifier = [_bypassSavedPresetIdentifier copy];
        NSArray<NSDictionary<NSString*, id>*>* savedValues = [_bypassSavedParameterValues copy];

        SGShaderPresetDescriptor* restoreDescriptor =
            SGShaderPresetForIdentifier(selectedIdentifier ?: savedIdentifier);
        if (!restoreDescriptor) {
            restoreDescriptor = SGShaderPresetForIdentifier(savedIdentifier);
        }
        if (!restoreDescriptor) {
            ended = NO;
            return;
        }

        _bypassCompareActive = NO;
        _bypassSavedPresetIdentifier = nil;
        _bypassSavedParameterValues = nil;
        [self applyPresetDescriptorLocked:restoreDescriptor updateSelectionState:NO];

        BOOL restoreSavedParams = savedIdentifier.length > 0 &&
                                  [savedIdentifier isEqualToString:restoreDescriptor.identifier];
        if (restoreSavedParams) {
            for (NSDictionary<NSString*, id>* entry in savedValues) {
                NSString* identifier = entry[@"identifier"];
                NSNumber* value = entry[@"value"];
                if (identifier.length == 0 || !value) continue;
                [_bridge updateParameterValue:value.floatValue forIdentifier:identifier];
            }
        }

        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return ended;
}

- (BOOL)setCompareMode:(SGCompareMode)mode {
    __block BOOL changed = YES;
    [self runOnRenderThread:^{
        if (_compareMode == mode) return;
        _compareMode = mode;
        if (!_capturing.load()) [self renderFrameLocked];
    }];
    return changed;
}

- (BOOL)setCompareSplitPosition:(float)splitPosition {
    const float clamped = std::clamp(splitPosition, 0.0f, 1.0f);
    __block BOOL changed = YES;
    [self runOnRenderThread:^{
        if (fabsf(_compareSplitPosition - clamped) < 0.0001f) return;
        _compareSplitPosition = clamped;
        if (_compareMode == SGCompareModeSplit && !_capturing.load()) [self renderFrameLocked];
    }];
    return changed;
}

- (BOOL)startCaptureKind:(SGTargetKind)kind targetID:(uint32_t)targetID {
    return [self startCaptureKind:kind targetID:targetID excludingWindowIDs:nil];
}

- (BOOL)startCaptureKind:(SGTargetKind)kind
                targetID:(uint32_t)targetID
      excludingWindowIDs:(nullable NSArray<NSNumber*>*)excludedWindowIDs {
    if (!_capture) {
        __weak LivePipeline* weakSelf = self;
        // FrameSink runs on the capture serial queue (the render thread).
        FrameSink sink = [weakSelf](const CaptureFrame& f) {
            LivePipeline* s = weakSelf;
            if (!s) return;
            [s onCaptureFrameTex:f.texture w:f.width h:f.height frame:(uint32_t)f.inputFrameNo];
        };
        CaptureEventSink events = [weakSelf](const CaptureEvent& e) {
            LivePipeline* s = weakSelf;
            if (!s || !s.captureEventHandler) return;
            NSString* msg = [NSString stringWithUTF8String:e.message.c_str()];
            s.captureEventHandler(e.kind == CaptureEventKind::Started, msg);
        };
        // Share the backend's MTLDevice (J7) so the captured texture is sampleable.
        _capture = new SCKCapture([_bridge renderBackend], sink, [_bridge nativeDevice], events);
        _renderQueue = (__bridge dispatch_queue_t)_capture->RenderQueue();
    }
    _capturing.store(true);          // set BEFORE Start so routing engages immediately
    CaptureTarget t;
    t.kind = (kind == SGTargetWindow) ? CaptureTargetKind::Window : CaptureTargetKind::Display;
    t.id   = targetID;
    for (NSNumber* n in excludedWindowIDs)
        t.excludedWindowIDs.push_back((uint32_t)n.unsignedIntValue);
    return _capture->Start(t, /*maxRate*/false, /*cursor*/false);
}

// Called from the capture serial queue (the render thread).
- (void)onCaptureFrameTex:(BackendTexture*)tex w:(uint32_t)w h:(uint32_t)h frame:(uint32_t)frameCount {
    @autoreleasepool {
        [self drawSrc:tex toTarget:nullptr srcW:w srcH:h dstW:_dstW dstH:_dstH frameCount:frameCount];
        if (_pendingExportURL) {
            NSURL* exportURL = _pendingExportURL;
            void (^completion)(BOOL, NSString*) = [_pendingExportCompletion copy];
            _pendingExportURL = nil;
            _pendingExportCompletion = nil;
            BOOL ok = [self writeLastOutputToPNG:exportURL.path];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(ok, ok ? @"Exported current frame" : @"Could not export current frame");
            });
        }
    }
}

// MUST be called from the main thread (SCKCapture::Stop does a dispatch_sync onto the
// render queue; calling from that queue would deadlock).
- (void)stopCapture {
    _capturing.store(false);          // stop routing new work onto the render queue
    if (_capture) _capture->Stop();   // drains the render queue synchronously before returning
}

- (BOOL)renderOffscreenToPNG:(NSString*)outPath {
    if (!_staticSrc) return NO;
    uint32_t w = _srcW, h = _srcH;   // 1:1 offscreen render for a clean golden diff
    BackendTexture* target =
        [_bridge createTexture:TextureDesc {w, h, PixFmt::BGRA8_UNORM, true, true}
                   initialData:nullptr
                      rowPitch:0];
    if (!target) return NO;
    [self drawSrc:_staticSrc toTarget:target srcW:w srcH:h dstW:w dstH:h frameCount:0];
    std::vector<uint8_t> px((size_t)w * h * 4);
    [_bridge readbackTexture:target dst:px.data() rowPitch:w * 4];
    [_bridge destroyTexture:target];
    return EncodePNGFromBGRA(outPath.UTF8String, px.data(), w, h, w * 4);
}

- (BOOL)writeLastOutputToPNG:(NSString*)outPath {
    uint32_t w = _dstW, h = _dstH;
    if (!w || !h) {
        w = _srcW; h = _srcH;
    }
    if (!w || !h) return NO;
    std::vector<uint8_t> px((size_t)w*h*4);
    BOOL readbackOK = [_bridge readbackLastOutput:px.data() rowPitch:w*4];
    bool ok = EncodePNGFromBGRA(outPath.UTF8String, px.data(), w, h, w*4);
    return readbackOK && ok;
}

- (void)exportMomentToURL:(NSURL*)url completion:(void (^)(BOOL success, NSString* _Nullable message))completion {
    if (!url) {
        if (completion) completion(NO, @"Missing export destination");
        return;
    }

    if (_capturing.load()) {
        _pendingExportURL = [url copy];
        _pendingExportCompletion = [completion copy];
        return;
    }

    [self runOnRenderThread:^{
        if (!_staticSrc) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) completion(NO, @"No frame available to export");
            });
            return;
        }
        [self renderFrameLocked];
        BOOL ok = [self writeLastOutputToPNG:url.path];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(ok, ok ? @"Exported current frame" : @"Could not export current frame");
        });
    }];
}

- (void)shutdown {
    [self stopCapture];
    if (_capture) { delete _capture; _capture = nullptr; }
    if (_compareProcessedTexture) { [_bridge destroyTexture:_compareProcessedTexture]; _compareProcessedTexture = nullptr; }
    if (_staticSrc) { [_bridge destroyTexture:_staticSrc]; _staticSrc = nullptr; }
    [_bridge shutdown];
    _bridge = nil;
}

- (void)dealloc { [self shutdown]; }

@end
