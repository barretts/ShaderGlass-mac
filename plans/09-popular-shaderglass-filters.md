# Popular ShaderGlass Filter Expansion

## Objective

Add the missing popular ShaderGlass / RetroArch-style filter families to the mac app in a controlled sequence, starting with a small user-visible set that is fun, recognizable, and still readable.

This plan covers both:
- near-term hand-authored Metal approximations that can ship quickly in the current single-pass app catalog
- longer-term generated/shared-engine presets that should inherit from upstream shader sources instead of being reimplemented by hand

## Current State

The mac app currently exposes a curated catalog of hand-authored `.metal` presets through `app/LivePipeline.*`, plus the shared-engine M2 path has proven generated preset support for the pinned manifest.

Already covered by the app catalog:
- passthrough
- CRT approximations
- LCD/grid looks
- amber and green monochrome looks
- VHS-style soft composite
- bloom/glow
- playful and futuristic filters
- Game Boy and SNES-style approximations

Missing popular ShaderGlass families:
- real CRT classics: `crt-geom`, `crt-easymode`, `crt-royale`, `guest-advanced`, `newpixie-crt`
- NTSC / TV-out: composite, S-Video, RF, artifact colors
- Retro Crisis / GDV NTSC console presets
- Mega Bezel / HSM MegaBezel presets
- handheld bezel presets: Game Boy, GBA, Game Gear, Super Game Boy
- scalers and sharpeners: xBR, super-xBR, Anime4K, adaptive sharpen
- film/color: Film Grain, Technicolor, Grade, Natural Vision
- novelty misc: ASCII, halftone, EGA, night mode, edge detect

## First Implementation Slice

Start with five presets that are high-value, readable, and feasible as current-app bundled Metal filters:

1. `NTSC Composite`
   - Goal: authentic-ish composite color bleed, mild dot crawl, soft chroma/luma separation.
   - Keep readable by limiting blur radius and avoiding heavy shimmer.
   - Current likely implementation: hand-authored single-pass `.metal`.
   - Later upstream target: generated `ntsc-simple`, `mame-ntsc`, or `ntsc-adaptive` preset.

2. `CRT Geom`
   - Goal: closer `crt-geom` feel than the current generic CRT: curvature, vignette, scanlines, phosphor mask.
   - Keep readable by preserving source contrast and limiting bezel/warp.
   - Current likely implementation: hand-authored single-pass `.metal`.
   - Later upstream target: generated real `crt-geom`.

3. `CRT Easymode`
   - Goal: lightweight, clean CRT look with scanlines and subtle mask, tuned for desktop readability.
   - Keep readable by making it less aggressive than `CRT Geom`.
   - Current likely implementation: hand-authored single-pass `.metal`.
   - Later upstream target: generated real `crt-easymode`.

4. `Newpixie CRT`
   - Goal: chunky retro monitor look with visible pixel structure, bloom, and softened edges.
   - Keep readable by avoiding large blur and preserving UI/text edges.
   - Current likely implementation: hand-authored single-pass `.metal`.
   - Later upstream target: generated real `newpixie-crt`.

5. `C64 Monitor`
   - Goal: Commodore-style monitor palette, soft chroma, scanline/slot-mask feel.
   - Keep readable by leaving luma structure intact and using color grade rather than heavy posterization.
   - Current likely implementation: hand-authored single-pass `.metal`.
   - Later upstream target: generated C64/monitor preset family if added to the M2 manifest.

## Implementation Procedure

### Stage 1 - Current-App Presets

For each first-slice preset:
- add `spike/<preset>.metal`
- use the existing shader ABI:
  - `UBO` at buffer 0
  - `Push` at buffer 1
  - `Source` texture/sampler at slot 2
- add enum entry in `app/LivePipeline.h`
- add catalog entry in `app/LivePipeline.mm`
- add resource copy line in `app/build.sh`
- preserve existing preset identifiers and ordering

Verification:

```sh
app/build.sh selftest
app/build.sh
```

Post-build checks:
- installed app includes the new `.metal` resources
- `dist/ShaderGlass.app` is refreshed from `app/build/ShaderGlass.app`
- `git diff --check` passes

### Stage 2 - M2 Generated Preset Candidates

After the five hand-authored approximations are usable, evaluate which should become real upstream inherited presets.

Candidate order:
1. real `ntsc-simple` or `mame-ntsc`
2. real `crt-easymode`
3. real `crt-geom`
4. real `newpixie-crt`
5. one C64 monitor preset

Required artifacts:
- update `plans/07-m2-manifest-ledger.md` with selected candidates
- add a generated-output manifest section or a new follow-on artifact
- add core tests for every generated preset promoted into the shared-engine path
- record unsupported shader keys before expanding beyond the current M2 baseline

Stop gate:
- do not add Mega Bezel, CRT Royale, or broad Retro Crisis presets until the generated path can prove the smaller CRT/NTSC candidates first.

## Full Backlog

### CRT And Display

- `crt-geom`
- `crt-easymode`
- `newpixie-crt`
- `crt-royale`
- `guest-advanced`
- PVM / Trinitron variants
- C64 monitor
- DOS VGA / EGA monitor looks

### TV And Signal

- NTSC composite
- NTSC S-Video
- RF / dirty RF
- artifact colors
- VHS tracking / tape damage
- TV-out console presets

### Console Families

- NES clean / composite / RGB
- SNES clean / composite / RF
- Genesis / Mega Drive clean / RF / RGB
- PlayStation clean / dirty
- N64
- Dreamcast
- Saturn
- PC Engine
- DOS low-res and high-res

### Handheld

- Game Boy LCD
- Game Boy Player
- Super Game Boy
- GBA LCD/grid
- Game Gear LCD/grid
- handheld bezel variants

### Enhancement

- adaptive sharpen
- super-xBR / super-res
- Anime4K
- cheap sharpen / RCAS
- deband

### Color And Film

- Film Grain
- Technicolor
- Grade / Grade No LUT
- Natural Vision
- color mangler / white point / chromaticity
- night mode

### Novelty And Utility

- ASCII
- halftone / CMYK dot
- edge detect
- EGA
- accessibility mods
- test pattern

## Acceptance Criteria

For the first implementation slice:
- five new presets appear in the app deck
- existing presets still load
- `app/build.sh selftest` passes
- normal `app/build.sh` installs the app
- `dist/ShaderGlass.app` contains the same new resources
- changes are committed and pushed

For later generated inheritance slices:
- selected presets are added to an M2 follow-on manifest
- generated MSL payloads are reproducible
- offscreen core tests exercise the generated preset definitions
- app exposure is gated on passing core/backend/app evidence

## Notes

Prefer readable approximations in the app catalog when the upstream preset is too heavy for immediate use. Prefer generated upstream inheritance when the preset relies on multi-pass semantics, history/feedback, static textures, or a large shader family that would be brittle to hand-port.
