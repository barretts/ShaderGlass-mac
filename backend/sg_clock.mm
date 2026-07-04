/*
ShaderGlass macOS port -- sg_clock.mm
*/

#include "sg_clock.h"
#include <mach/mach_time.h>

namespace sg {

uint64_t MonotonicMillis()
{
    static mach_timebase_info_data_t tb = {0, 0};
    if(tb.denom == 0)
        mach_timebase_info(&tb);
    uint64_t ns = mach_absolute_time() * tb.numer / tb.denom;
    return ns / 1000000ull;
}

} // namespace sg
