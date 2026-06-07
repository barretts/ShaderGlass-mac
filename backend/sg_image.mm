/*
ShaderGlass macOS port -- sg_image.mm  (ImageIO decode/encode, BGRA8)
*/

#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>
#include "sg_image.h"
#include <cstdio>

namespace sg {

bool DecodeImageFileBGRA(const std::string& path, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra) {
    CFStringRef cfp = CFStringCreateWithCString(kCFAllocatorDefault, path.c_str(), kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfp, kCFURLPOSIXPathStyle, false);
    CFRelease(cfp);
    CGImageSourceRef src = CGImageSourceCreateWithURL(url, nullptr);
    CFRelease(url);
    if (!src) { fprintf(stderr, "sg_image: cannot open %s\n", path.c_str()); return false; }
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    CFRelease(src);
    if (!img) { fprintf(stderr, "sg_image: cannot decode %s\n", path.c_str()); return false; }

    w = (uint32_t)CGImageGetWidth(img);
    h = (uint32_t)CGImageGetHeight(img);
    bgra.assign((size_t)w * h * 4, 0);

    // Draw into a BGRA8 context: kCGImageAlphaPremultipliedFirst + Little32 yields
    // byte order B,G,R,A in memory, matching the engine's BGRA chain.
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(bgra.data(), w, h, 8, (size_t)w * 4, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(img); fprintf(stderr, "sg_image: bitmap ctx failed\n"); return false; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);
    CGImageRelease(img);
    return true;
}

bool EncodePNGFromBGRA(const std::string& path, const uint8_t* bgra, uint32_t w, uint32_t h, size_t rowPitch) {
    if (rowPitch == 0) rowPitch = (size_t)w * 4;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate((void*)bgra, w, h, 8, rowPitch, cs,
                                             kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(cs);
    if (!ctx) { fprintf(stderr, "sg_image: encode ctx failed\n"); return false; }
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    if (!img) return false;

    CFStringRef cfp = CFStringCreateWithCString(kCFAllocatorDefault, path.c_str(), kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfp, kCFURLPOSIXPathStyle, false);
    CFRelease(cfp);
    CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, nullptr);
    CFRelease(url);
    if (!dst) { CGImageRelease(img); return false; }
    CGImageDestinationAddImage(dst, img, nullptr);
    bool ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
    CGImageRelease(img);
    return ok;
}

} // namespace sg
