/*
ShaderGlass macOS port -- EngineBridge

Objective-C++ wrapper around the backend-neutral shared core engine.
*/

#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#include "../backend/IRenderBackend.h"
#include <string>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SGEngineEvent) {
    SGEngineEventPresetChanged = 0,
    SGEngineEventFrameRendered = 1,
};

typedef NS_ENUM(NSInteger, SGCompareMode) {
    SGCompareModeOff = 0,
    SGCompareModeSplit = 1,
};

@interface SGPresetMetadata : NSObject <NSCopying>

@property(nonatomic, readonly, copy) NSString* presetID;
@property(nonatomic, readonly, copy) NSString* displayName;
@property(nonatomic, readonly, copy) NSString* category;
@property(nonatomic, readonly) NSInteger passCount;

@end

@interface SGParameterSnapshot : NSObject <NSCopying>

@property(nonatomic, readonly, copy) NSString* identifier;
@property(nonatomic, readonly) NSInteger passIndex;
@property(nonatomic, readonly, copy) NSString* name;
@property(nonatomic, readonly, copy) NSString* parameterDescription;
@property(nonatomic, readonly) float minimumValue;
@property(nonatomic, readonly) float maximumValue;
@property(nonatomic, readonly) float defaultValue;
@property(nonatomic, readonly) float currentValue;
@property(nonatomic, readonly) float stepValue;

@end

@interface EngineBridge : NSObject

@property(nonatomic, copy, nullable) void (^engineEventHandler)(SGEngineEvent event);
@property(nonatomic, readonly, copy, nullable) SGPresetMetadata* activePresetMetadata;

- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                          shaderSource:(const std::string&)shaderSource;
- (nullable instancetype)initWithLayer:(nullable CAMetalLayer*)layer
                                 width:(uint32_t)width
                                height:(uint32_t)height
                       preprocessSource:(const std::string&)preprocessSource
                           shaderSource:(const std::string&)shaderSource;

- (BOOL)setShaderSource:(const std::string&)shaderSource;
- (BOOL)setShaderSource:(const std::string&)shaderSource
               presetID:(nullable NSString*)presetID
            displayName:(nullable NSString*)displayName
               category:(nullable NSString*)category;
- (BOOL)setPreprocessSource:(const std::string&)preprocessSource shaderSource:(const std::string&)shaderSource;
- (BOOL)setPreprocessSource:(const std::string&)preprocessSource
               shaderSource:(const std::string&)shaderSource
                   presetID:(nullable NSString*)presetID
                displayName:(nullable NSString*)displayName
                   category:(nullable NSString*)category;
- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height;

- (NSArray<SGParameterSnapshot*>*)parameterSnapshots;
- (nullable SGParameterSnapshot*)parameterSnapshotForIdentifier:(NSString*)identifier;
- (BOOL)updateParameterValue:(float)value forIdentifier:(NSString*)identifier;
- (BOOL)resetParameterForIdentifier:(NSString*)identifier;
- (BOOL)resetAllParameters;

- (nullable sg::BackendTexture*)beginFrame;
- (void)present;
- (BOOL)renderSource:(sg::BackendTexture*)source
         sourceWidth:(uint32_t)sourceWidth
        sourceHeight:(uint32_t)sourceHeight
            toTarget:(sg::BackendTexture*)target
         targetWidth:(uint32_t)targetWidth
        targetHeight:(uint32_t)targetHeight
          frameCount:(uint32_t)frameCount;
- (BOOL)composeCompareOriginal:(sg::BackendTexture*)original
                     processed:(sg::BackendTexture*)processed
                      toTarget:(sg::BackendTexture*)target
                   targetWidth:(uint32_t)targetWidth
                  targetHeight:(uint32_t)targetHeight
                 splitPosition:(float)splitPosition;

- (nullable sg::BackendTexture*)createTexture:(const sg::TextureDesc&)desc
                                  initialData:(nullable const void*)initialData
                                     rowPitch:(size_t)rowPitch;
- (void)destroyTexture:(nullable sg::BackendTexture*)texture;
- (void)readbackTexture:(sg::BackendTexture*)texture dst:(void*)dst rowPitch:(size_t)rowPitch;
- (nullable sg::BackendTexture*)grabOutput;
- (BOOL)readbackLastOutput:(void*)dst rowPitch:(size_t)rowPitch;

- (sg::IRenderBackend*)renderBackend;
- (nullable void*)nativeDevice;
- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
