// check_msl.cpp
// Proves spirv-cross-msl links and spirv_cross::CompilerMSL is usable for arm64 macOS.
//
// Strategy: load a real, validated SPIR-V module (a .spv file shipped in the
// SPIRV-Cross test corpus) from argv[1], hand it to spirv_cross::CompilerMSL,
// exercise the MSL options getter/setter, and run compile() to MSL source.
// If this links, parses, and emits non-empty MSL, the CompilerMSL codepath is
// proven end-to-end for arm64.
//
// Usage: check_msl <path-to.spv>

#include "spirv_msl.hpp"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <vector>

static std::vector<uint32_t> load_spirv(const char* path)
{
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f)
    {
        std::fprintf(stderr, "FAIL: cannot open SPIR-V file: %s\n", path);
        std::exit(4);
    }
    std::streamsize bytes = f.tellg();
    if (bytes <= 0 || (bytes % 4) != 0)
    {
        std::fprintf(stderr, "FAIL: bad SPIR-V size %lld (not a multiple of 4)\n",
                     static_cast<long long>(bytes));
        std::exit(5);
    }
    f.seekg(0, std::ios::beg);
    std::vector<uint32_t> words(static_cast<size_t>(bytes) / 4);
    f.read(reinterpret_cast<char*>(words.data()), bytes);
    return words;
}

int main(int argc, char** argv)
{
    if (argc < 2)
    {
        std::fprintf(stderr, "usage: %s <path-to.spv>\n", argv[0]);
        return 1;
    }

    std::vector<uint32_t> spirv = load_spirv(argv[1]);

    // Sanity: SPIR-V magic number, little-endian as stored on disk.
    if (spirv.empty() || spirv[0] != 0x07230203u)
    {
        std::fprintf(stderr, "FAIL: not a SPIR-V module (magic=0x%08x)\n",
                     spirv.empty() ? 0u : spirv[0]);
        return 6;
    }

    try
    {
        // Construct from SPIR-V words: proves the CompilerMSL ctor + parser link.
        spirv_cross::CompilerMSL msl(std::move(spirv));

        // Exercise MSL options getter/setter: proves the MSL options symbols link.
        spirv_cross::CompilerMSL::Options opts = msl.get_msl_options();
        opts.platform = spirv_cross::CompilerMSL::Options::macOS;
        opts.set_msl_version(2, 1, 0);
        opts.enable_decoration_binding = true;
        msl.set_msl_options(opts);

        // Run the full MSL emit path.
        std::string out = msl.compile();

        if (out.empty())
        {
            std::fprintf(stderr, "FAIL: CompilerMSL.compile() returned empty MSL\n");
            return 2;
        }

        spirv_cross::CompilerMSL::Options got = msl.get_msl_options();
        std::printf("OK: CompilerMSL linked and ran.\n");
        std::printf("    msl_version=%u platform=%d\n",
                    got.msl_version, static_cast<int>(got.platform));
        std::printf("    emitted MSL bytes=%zu\n", out.size());

        // Print just the first few lines as proof of real MSL output.
        size_t shown = 0, nl = 0;
        std::printf("---- MSL (first lines) ----\n");
        for (char c : out)
        {
            std::putchar(c);
            ++shown;
            if (c == '\n' && ++nl >= 12)
                break;
        }
        std::printf("---- (%zu of %zu bytes shown) ----\n", shown, out.size());
        return 0;
    }
    catch (const std::exception& e)
    {
        std::fprintf(stderr, "FAIL: exception from CompilerMSL: %s\n", e.what());
        return 3;
    }
}
