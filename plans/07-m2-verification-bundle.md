# Feature 7.5 - M2 Verification Bundle

## Objective

Freeze the proof packet for the mandatory M2 inheritance manifest: generation, shared-engine execution, backend support, app selftest, and live smoke.

This is the `m2-verification-agent` artifact consumed by Director C and root.

## Verified Revisions

- shared repo commit: `c8033481`
- mac repo commit: `9088afc`
- upstream shader corpus commit: `a4f3aeec04fcb2624ec6df5dd17e38f9b575eab9`

## Required Commands And Evidence

| Command | Evidence log | Result |
| --- | --- | --- |
| `core/build_core.sh` | `.logs/build-core-m2-manifest-host.log` | passed |
| `backend/build_test.sh` | `.logs/build-backend-current-after-m2.log` | passed |
| `capture/build_test.sh` | `.logs/build-capture-current-after-m2.log` | passed |
| `app/build.sh selftest` | `.logs/build-app-selftest-current-after-m2.log` | passed |
| `app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-display app/build/smoke-display-after-m2.png` | `.logs/live-smoke-display-after-m2.log` | passed |
| `app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-window app/build/smoke-window-after-m2.png` | `.logs/live-smoke-window-after-m2.log` | passed |
| `app/build/ShaderGlass.app/Contents/MacOS/ShaderGlass --smoke-overlay` | `.logs/live-smoke-overlay-after-m2.log` | passed |

## Per-Preset Verification Summary

| Preset | Verification result | Evidence |
| --- | --- | --- |
| `pal/pal-singlepass` | stable generated single-pass output across cold runs | `.logs/build-core-m2-manifest-host.log` |
| `ntsc/ntsc-adaptive-4x` | non-identity generated multi-pass output and sequential phase activity | `.logs/build-core-m2-manifest-host.log` |
| `film/technicolor` | static textures bind and output is stable when time-varying shader params are neutralized for test isolation | `.logs/build-core-m2-manifest-host.log` |
| `motionblur/mix_frames` | `OriginalHistory1` affects output across frames | `.logs/build-core-m2-manifest-host.log` |

## Smoke Outputs

- display capture output: `app/build/smoke-display-after-m2.png`
- window capture output: `app/build/smoke-window-after-m2.png`
- overlay smoke: click-through verified in `.logs/live-smoke-overlay-after-m2.log`

## Known Warnings

- Generated shader headers still emit C++ warnings for assigning string literals to `char*` `Format` fields. This is pre-existing generated-header shape and did not block the green gates.
- The parent shared repo sees `mac/` as an untracked nested repo. The mac repository is intentionally committed and pushed independently; it was not converted into a submodule/gitlink.

## Promotion Recommendation

Recommendation: promote M2 from experimental to baseline inheritance for the pinned mandatory manifest only.

Do not treat this as broad corpus support. Future preset expansion must update `plans/07-m2-manifest-ledger.md`, regenerate outputs, and extend this verification bundle.
