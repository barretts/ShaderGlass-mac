# ShaderGlass macOS — Building & Running

Requirements: Apple Silicon Mac, macOS 12.3+, Xcode (for the SDK + `metal` compiler).
On the dev machine here, **GPU/Metal/clang/git need the command sandbox disabled**.

## One-time setup: persistent signing cert (so the Screen Recording grant survives rebuilds)

```sh
cd mac/app
./make-signing-cert.sh        # creates a self-signed "ShaderGlassDev" cert in your login keychain
```

`build.sh` now signs with `ShaderGlassDev` **by default** (stable cdhash). It bounds the
cert-sign with a `timeout` and falls back to ad-hoc if codesign would block on a keychain
prompt, so headless builds never wedge. Force ad-hoc with `SG_SIGN_CERT=0`.

Each build also installs a copy to `~/Applications/ShaderGlass.app`, so **cmd-space (Spotlight)
launches the current cert-signed build** — just type "ShaderGlass". Skip with `SG_INSTALL=0`.

Why: macOS TCC keys the Screen Recording permission to the binary's **code-signature cdhash**.
Ad-hoc signing (`codesign -s -`) produces a new cdhash on every rebuild, so a previously-granted
permission silently stops applying ("System Settings says granted, but the app says it isn't"). A
stable signing identity fixes this. The cert is reversible — delete `ShaderGlassDev` in Keychain
Access to undo.

Note: the cert lists as `CSSMERR_TP_NOT_TRUSTED` (it's self-signed) and won't appear under
`security find-identity -v` ("valid only"). That's fine — `codesign` uses it anyway, and TCC only
needs a *stable* cdhash, not a *trusted* one. `build.sh` detects it with
`security find-identity -p codesigning` (no `-v`).

## Build + run the live app

```sh
cd mac/app
./build.sh                    # compile, assemble ShaderGlass.app, sign with ShaderGlassDev
open ./build/ShaderGlass.app  # launch the GUI

# or build + run the headless offscreen golden render (no window, no TCC):
./build.sh selftest           # writes build/selftest.png (byte-identical to demo/out/passthrough.png)
```

### Using the GUI
1. **Shader dropdown → CRT** — flips the displayed image to the CRT effect. Needs no permission, so
   it's the quickest check that the controls are wired.
2. **Target dropdown / Rescan** — lists capturable windows + displays (requires the Screen Recording
   grant; see below if empty).
3. Pick a **window** (window-clone avoids the see-itself feedback loop), click **Start** → live.
4. Resize the window — output re-fits (aspect-preserved letterbox).

## Granting Screen Recording (first run / after a fresh machine)

ScreenCaptureKit is TCC-gated. On first capture attempt macOS should prompt; if not:
1. System Settings → Privacy & Security → **Screen Recording** → enable **ShaderGlass**.
2. **Relaunch the app** (macOS requires a relaunch after a fresh Screen Recording grant).
3. Click **Rescan** — the Target dropdown should populate.

### Troubleshooting: "Settings says granted but the app says no"
This is the ad-hoc-cdhash problem. Fix:
```sh
cd mac/app
./make-signing-cert.sh                       # if not already done
./build.sh                                    # re-sign with the stable cert
tccutil reset ScreenCapture net.shaderglass.mac   # clear stale grant records
open ./build/ShaderGlass.app                  # relaunch, re-grant once
```
If still stuck: in System Settings → Screen Recording, **remove any stale "ShaderGlass" entry with
the "–" button**, toggle the current one on, relaunch.

## Regression tests (auto-verifiable, no window/TCC)

```sh
mac/backend/build_test.sh     # IRenderBackend/MetalBackend conformance (offscreen, pixel-diff)
mac/capture/build_test.sh     # CVToMetal capture-core + ring stress (no Screen Recording needed)
mac/demo/build.sh             # PNG → pipeline → PNG; writes demo/out/{passthrough,crt}.png
mac/spike/build.sh            # M-1 Metal-mapping proof (5 cases)
```
All should print `PASS` / `OVERALL PASS`. Run any GPU-touching build with the sandbox disabled.

## Rebuilding the arm64 shader-toolchain deps (only needed for M4 later)

```sh
# glslang + SPIRV-Cross (with MSL) are in mac/deps/ (gitignored). To rebuild:
# see mac/deps/.logs/ for the original configure/build invocations, and the memory note
# arm64-spirv-cross-build for the link-order / header / sandbox gotchas.
```
