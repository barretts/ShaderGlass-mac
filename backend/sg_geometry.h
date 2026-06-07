/*
ShaderGlass macOS port -- sg_geometry.h

Portable replacements for the Win32 RECT / POINT used throughout the engine's
geometry/crop/box math (ShaderGlass.cpp:467-549 etc.). Field names and order match
the Win32 structs so the existing arithmetic ports verbatim:
  RECT  { LONG left, top, right, bottom; }
  POINT { LONG x, y; }
*/

#pragma once

#include <cstdint>

namespace sg {

struct Rect {
    int32_t left   = 0;
    int32_t top    = 0;
    int32_t right  = 0;
    int32_t bottom = 0;
};

struct Point {
    int32_t x = 0;
    int32_t y = 0;
};

} // namespace sg
