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

@interface EngineBridge : NSObject

@property(nonatomic, copy, nullable) void (^engineEventHandler)(SGEngineEvent event);

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
- (BOOL)setPreprocessSource:(const std::string&)preprocessSource shaderSource:(const std::string&)shaderSource;
- (void)resizeToWidth:(uint32_t)width height:(uint32_t)height;

- (nullable sg::BackendTexture*)beginFrame;
- (void)present;
- (BOOL)renderSource:(sg::BackendTexture*)source
         sourceWidth:(uint32_t)sourceWidth
        sourceHeight:(uint32_t)sourceHeight
            toTarget:(sg::BackendTexture*)target
         targetWidth:(uint32_t)targetWidth
        targetHeight:(uint32_t)targetHeight
          frameCount:(uint32_t)frameCount;

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
