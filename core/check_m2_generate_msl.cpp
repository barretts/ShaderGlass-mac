#include "../../ShaderGC/SPIRV.h"

#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <sstream>
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
        std::fprintf(stderr, "FAIL: bad SPIR-V size %lld\n", static_cast<long long>(bytes));
        std::exit(5);
    }
    f.seekg(0, std::ios::beg);
    std::vector<uint32_t> words(static_cast<size_t>(bytes) / 4);
    f.read(reinterpret_cast<char*>(words.data()), bytes);
    return words;
}

int main(int argc, char** argv)
{
    if (argc != 2)
    {
        std::fprintf(stderr, "usage: %s <path-to.spv>\n", argv[0]);
        return 1;
    }

    auto spirv = load_spirv(argv[1]);
    bool warn = false;
    std::ostringstream log;

    try
    {
        auto result = SPIRV::GenerateMSL(spirv, true, log, warn);
        if (result.first.empty())
        {
            std::fprintf(stderr, "FAIL: GenerateMSL returned empty source\n");
            return 2;
        }
        if (result.first.find("#include <metal_stdlib>") == std::string::npos)
        {
            std::fprintf(stderr, "FAIL: output does not look like MSL\n");
            return 3;
        }
        std::printf("OK: GenerateMSL emitted %zu bytes, metadata=%zu, warn=%d\n",
                    result.first.size(), result.second.size(), warn ? 1 : 0);
        return 0;
    }
    catch (const std::exception& ex)
    {
        std::fprintf(stderr, "FAIL: %s\n", ex.what());
        return 6;
    }
}
