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

struct FrameGeometry {
    Rect sourceRect;
    Rect clientRect;
    Rect displayRect;
    Rect monitorRect;
    Rect outputRect;
    Point cursorPoint;
    bool cursorVisible = false;
};

class IGeometryProvider {
public:
    virtual ~IGeometryProvider() = default;
    virtual FrameGeometry Geometry(uint32_t sourceWidth,
                                   uint32_t sourceHeight,
                                   uint32_t outputWidth,
                                   uint32_t outputHeight) = 0;
};

class FullFrameGeometryProvider final : public IGeometryProvider {
public:
    FrameGeometry Geometry(uint32_t sourceWidth,
                           uint32_t sourceHeight,
                           uint32_t outputWidth,
                           uint32_t outputHeight) override
    {
        FrameGeometry g;
        g.sourceRect = Rect {0, 0, static_cast<int32_t>(sourceWidth), static_cast<int32_t>(sourceHeight)};
        g.clientRect = Rect {0, 0, static_cast<int32_t>(outputWidth), static_cast<int32_t>(outputHeight)};
        g.displayRect = g.clientRect;
        g.monitorRect = g.clientRect;
        g.outputRect = Rect {0, 0, static_cast<int32_t>(outputWidth), static_cast<int32_t>(outputHeight)};
        g.cursorPoint = Point {0, 0};
        g.cursorVisible = false;
        return g;
    }
};

} // namespace sg
