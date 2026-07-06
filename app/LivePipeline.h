/*
ShaderGlass macOS port -- LivePipeline.h

The single renderer for the live GUI. Owns the MetalBackend, the shaders, the
once-created buffers/sampler, and (from L3) the SCKCapture. It is the ONLY place
that issues the BeginFrame -> BeginRenderPass -> ... -> Draw -> EndRenderPass ->
Present sequence (the block lifted verbatim from demo.mm:66-94).

Sources:
  L1/L2: a static image (SetStaticImage) rendered on demand (launch + resize).
  L3+:   live SCKCapture frames via the FrameSink (StartCapture).

This is an Objective-C++ class so AppKit (SGMetalView/SGAppDelegate) can hold it
while it owns the C++ MetalBackend/SCKCapture.
*/

#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import "EngineBridge.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SGShaderKind) {
    SGShaderPassthrough = 0,
    SGShaderCRT         = 1,
    SGShaderCRTPro      = 2,
    SGShaderLCDGrid     = 3,
    SGShaderAmberMono   = 4,
    SGShaderVHSSoft     = 5,
    SGShaderGreenMono   = 6,
    SGShaderPixelGrid   = 7,
    SGShaderBloomSoft   = 8,
    SGShaderPVMSlots    = 9,
    SGShaderNoirFilm    = 10,
    SGShaderThermalPop  = 11,
    SGShaderDreamBlur   = 12,
    SGShaderCyberGlow   = 13,
    SGShaderAmberCRT    = 14,
    SGShaderBlueTerminal = 15,
    SGShaderHologramGlass = 16,
    SGShaderDataGrid = 17,
    SGShaderNightVisionHUD = 18,
    SGShaderIceCRT = 19,
    SGShaderVectorScope = 20,
    SGShaderPlasmaDesk = 21,
    SGShaderSecurityCamClean = 22,
    SGShaderHotdogPro = 23,
    SGShaderDinoPark = 24,
    SGShaderGameBoy = 25,
    SGShaderSNESPop = 26,
    SGShaderGreenCRT = 27,
    SGShaderNTSCComposite = 28,
    SGShaderCRTGeomStyle = 29,
    SGShaderCRTEasymodeStyle = 30,
    SGShaderNewpixieCRT = 31,
    SGShaderC64Monitor = 32,
    SGShaderCount       = 33,
};

@interface SGShaderPresetDescriptor : NSObject

@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly, copy) NSString* title;
@property(nonatomic, readonly, copy) NSString* shaderFilename;
@property(nonatomic, readonly) SGShaderKind legacyKind;
@property(nonatomic, readonly) NSInteger legacyMenuIndex;

@end

// Capture target kinds mirrored for the UI layer (avoids exposing sg:: types here).
typedef NS_ENUM(NSInteger, SGTargetKind) {
    SGTargetDisplay = 0,
    SGTargetWindow  = 1,
};

@interface LivePipeline : NSObject

@property(nonatomic, copy, nullable) void (^captureEventHandler)(BOOL started, NSString* _Nullable message);
@property(nonatomic, copy, nullable) void (^engineEventHandler)(NSInteger event);
@property(nonatomic, readonly, copy) NSString* activeShaderPresetIdentifier;
@property(nonatomic, readonly) SGShaderPresetDescriptor* activeShaderPresetDescriptor;
@property(nonatomic, readonly, copy, nullable) SGPresetMetadata* activePresetMetadata;
@property(nonatomic, readonly, getter=isBypassCompareActive) BOOL bypassCompareActive;
@property(nonatomic, readonly) SGCompareMode compareMode;
@property(nonatomic, readonly) float compareSplitPosition;

+ (NSArray<SGShaderPresetDescriptor*>*)shaderPresetCatalog;
+ (nullable SGShaderPresetDescriptor*)shaderPresetForIdentifier:(NSString*)identifier;
+ (nullable SGShaderPresetDescriptor*)shaderPresetForLegacyKind:(SGShaderKind)kind;

// Bring up the backend on the view's CAMetalLayer at the given device-pixel size.
// shaderDir is the directory holding passthrough.metal / crt_demo.metal (the bundle
// Resources dir in the .app, or a relative path for loose builds). Returns nil on
// failure (no Metal device / shader compile error).
- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                             shaderDir:(NSString*)shaderDir;

// L1/L2: set a static image source (decoded from a PNG path) and render it once.
- (BOOL)setStaticImagePath:(NSString*)pngPath;

// Re-render the current source through the current shader into the drawable.
// Safe to call from the main thread (L1/L2 on-demand) — does its own work + present.
- (void)renderFrame;

// Drawable/layer resized to new device-pixel size; updates uniforms + re-renders.
- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height;

// Hot-swap the active shader (consumed at the top of the next frame; thread-safe).
- (BOOL)setShaderPresetIdentifier:(NSString*)identifier;
- (void)setShaderKind:(SGShaderKind)kind;
- (NSArray<SGParameterSnapshot*>*)parameterSnapshots;
- (nullable SGParameterSnapshot*)parameterSnapshotForIdentifier:(NSString*)identifier;
- (nullable SGParameterSnapshot*)parameterSnapshotNamed:(NSString*)name;
- (BOOL)updateParameterValue:(float)value forIdentifier:(NSString*)identifier;
- (BOOL)resetParameterForIdentifier:(NSString*)identifier;
- (BOOL)resetAllParameters;
- (BOOL)beginBypassCompare;
- (BOOL)endBypassCompare;
- (BOOL)setCompareMode:(SGCompareMode)mode;
- (BOOL)setCompareSplitPosition:(float)splitPosition;
- (void)exportMomentToURL:(NSURL*)url completion:(void (^)(BOOL success, NSString* _Nullable message))completion;

// L3+: start/stop live capture of a target. Runs the capture on its own serial
// queue; the FrameSink renders+presents per frame. id is CGDirectDisplayID or
// CGWindowID. Returns immediately; permission/enumeration is async.
- (BOOL)startCaptureKind:(SGTargetKind)kind targetID:(uint32_t)targetID;
- (BOOL)startCaptureKind:(SGTargetKind)kind
                targetID:(uint32_t)targetID
      excludingWindowIDs:(nullable NSArray<NSNumber*>*)excludedWindowIDs;
- (void)stopCapture;

// Render one frame into an OFFSCREEN cpuReadable texture and write it to a PNG.
// Used by the auto-verification (--selftest) path; never reads the drawable back.
- (BOOL)renderOffscreenToPNG:(NSString*)outPath;

// Write the most recently rendered engine output to a PNG.
- (BOOL)writeLastOutputToPNG:(NSString*)outPath;

- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
