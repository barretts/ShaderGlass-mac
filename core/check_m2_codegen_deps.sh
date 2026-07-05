#!/bin/zsh
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
mac_root=$(cd "$script_dir/.." && pwd)

checker="$mac_root/deps/check_msl"
fixture="$mac_root/deps/SPIRV-Cross/tests-other/msl_resource_binding.spv"

fail() {
  echo "m2-codegen-deps: $*" >&2
  exit 1
}

[[ -x "$checker" ]] || fail "missing executable checker: $checker"
[[ -f "$fixture" ]] || fail "missing SPIR-V fixture: $fixture"

output=$("$checker" "$fixture" 2>&1)
checker_rc=$?
if [[ $checker_rc -ne 0 ]]; then
  printf '%s\n' "$output" >&2
  fail "CompilerMSL proof binary failed"
fi

if [[ "$output" != *"OK: CompilerMSL linked and ran."* ]]; then
  printf '%s\n' "$output" >&2
  fail "CompilerMSL proof output missing success marker"
fi

if [[ "$output" != *"emitted MSL bytes="* ]]; then
  printf '%s\n' "$output" >&2
  fail "CompilerMSL proof output missing emitted-byte marker"
fi

printf '%s\n' "$output"
echo "m2-codegen-deps: OK"
