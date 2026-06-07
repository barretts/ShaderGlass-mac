/*
ShaderGlass macOS port -- sg_clock.h

Single monotonic-millisecond clock for the whole engine + capture timeline.

CRITICAL (capture review wn0s5ydtc): the engine's Process() compares its own
"now" against CaptureFrame::frameTicks with a <20ms staleness guard
(ShaderGlass.cpp:434-435). Both sides MUST come from this one clock with one epoch,
or the staleness optimization silently breaks (and risks unsigned underflow).

Use SG_TICKS() at every site that currently calls GetTickCount64():
  - Windows host build: wraps GetTickCount64() (same monotonic-ms semantics).
  - macOS / libsgcore:   sg::MonotonicMillis() (mach_absolute_time based; defined
                         in mac/capture/SCKCapture.mm and also usable standalone).

Engine GetTickCount64 sites to convert (migration map §5):
  ShaderGlass.cpp:83,84,424,652,1165 ; CaptureSession.cpp:99,144
Fields: ULONGLONG -> uint64_t (ShaderGlass.h:95,98-100,Process param; CaptureSession.h:58,61).
*/

#pragma once

#include <cstdint>

namespace sg {
// Milliseconds since an arbitrary monotonic epoch. Defined in SCKCapture.mm.
uint64_t MonotonicMillis();
}

#ifdef SG_WINDOWS
  // <windows.h> provides GetTickCount64(); host build maps the shim to it so the
  // engine timeline and the (Windows) capture timeline share the OS clock.
  #define SG_TICKS() (::GetTickCount64())
#else
  #define SG_TICKS() (::sg::MonotonicMillis())
#endif
