/*
ShaderGlass macOS port -- sg_image.mm  (ImageIO decode/encode, BGRA8)
*/

#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>
#include "sg_image.h"
#include <cstdio>

namespace sg {

static bool DecodeImageSourceBGRA(CGImageSourceRef src, const char* label, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra) {
    if (!src) { fprintf(stderr, "sg_image: cannot open %s\n", label); return false; }
    CGImageRef img = CGImageSourceCreateImageAtIndex(src, 0, nullptr);
    if (!img) { fprintf(stderr, "sg_image: cannot decode %s\n", label); return false; }

    w = (uint32_t)CGImageGetWidth(img);
    h = (uint32_t)CGImageGetHeight(img);
    bgra.assign((size_t)w * h * 4, 0);

    // Draw into a BGRA8 context: kCGImageAlphaPremultipliedFirst + Little32 yields
    // byte order B,G,R,A in memory, matching the engine's BGRA chain.
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
    CGContextRef ctx = CGBitmapContextCreate(bgra.data(), w, h, 8, (size_t)w * 4, cs, bitmapInfo);
    CGColorSpaceRelease(cs);
    if (!ctx) { CGImageRelease(img); fprintf(stderr, "sg_image: bitmap ctx failed\n"); return false; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), img);
    CGContextRelease(ctx);
    CGImageRelease(img);
    return true;
}

bool DecodeImageFileBGRA(const std::string& path, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra) {
    CFStringRef cfp = CFStringCreateWithCString(kCFAllocatorDefault, path.c_str(), kCFStringEncodingUTF8);
    CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, cfp, kCFURLPOSIXPathStyle, false);
    CFRelease(cfp);
    CGImageSourceRef src = CGImageSourceCreateWithURL(url, nullptr);
    CFRelease(url);
    bool ok = DecodeImageSourceBGRA(src, path.c_str(), w, h, bgra);
    CFRelease(src);
    return ok;
}

bool DecodeImageMemoryBGRA(const uint8_t* data, size_t len, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra) {
    CFDataRef bytes = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, data, (CFIndex)len, kCFAllocatorNull);
    CGImageSourceRef src = CGImageSourceCreateWithData(bytes, nullptr);
    bool ok = DecodeImageSourceBGRA(src, "<memory>", w, h, bgra);
    if (src) CFRelease(src);
    CFRelease(bytes);
    return ok;
}

bool EncodePNGFromBGRA(const std::string& path, const uint8_t* bgra, uint32_t w, uint32_t h, size_t rowPitch) {
    if (rowPitch == 0) rowPitch = (size_t)w * 4;
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = (CGBitmapInfo)kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little;
    CGContextRef ctx = CGBitmapContextCreate((void*)bgra, w, h, 8, rowPitch, cs, bitmapInfo);
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
