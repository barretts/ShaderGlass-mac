/*
ShaderGlass macOS port -- sg_image.h

Host image decode/encode helpers (the macOS replacement for the WIC decode in
Texture.cpp -- migration map gap G2). NOT part of IRenderBackend: this is plain
CPU image I/O, fed into IRenderBackend::CreateTexture(initialData) for preset
images, and used to save GrabOutput/ReadbackTexture results to PNG.

Pixels are BGRA8 (matching the engine's internal BGRA chain and CreateTexture's
PixFmt::BGRA8_UNORM default), 4 bytes/pixel, tightly packed (rowPitch = w*4).
*/

#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

namespace sg {

// Decode an image file (PNG/JPEG/etc via ImageIO) to tightly-packed BGRA8.
// Returns false on failure. On Windows this would wrap WIC; here it's ImageIO.
bool DecodeImageFileBGRA(const std::string& path, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra);

// Decode in-memory image bytes to tightly-packed BGRA8. Used by shared preset
// TextureDef blobs when WIC is not available.
bool DecodeImageMemoryBGRA(const uint8_t* data, size_t len, uint32_t& w, uint32_t& h, std::vector<uint8_t>& bgra);

// Encode tightly-packed BGRA8 pixels to a PNG file (ImageIO). rowPitch defaults to w*4.
bool EncodePNGFromBGRA(const std::string& path, const uint8_t* bgra, uint32_t w, uint32_t h, size_t rowPitch = 0);

} // namespace sg
