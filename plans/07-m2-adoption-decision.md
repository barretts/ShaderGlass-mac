# Feature 7.6 - M2 Adoption Decision

## Objective

Record the root/director decision after the first bounded M2 inheritance slice passed its required proof gates.

## Decision

Adopt the generated shared-engine path as the baseline inheritance path for the pinned mandatory manifest:

- `pal/pal-singlepass`
- `ntsc/ntsc-adaptive-4x`
- `film/technicolor`
- `motionblur/mix_frames`

This adoption is limited to the manifest above. It is not approval for broad upstream corpus support.

## Runtime Exposure

- Core/offscreen verification may use the generated preset definitions directly.
- The mac app can continue exposing curated app-facing preset choices while using the shared-engine path underneath.
- Additional generated presets must remain opt-in until they are added to the manifest ledger and pass the same evidence bundle shape.

## Follow-On Ledger

| Follow-on | Owner | Gate |
| --- | --- | --- |
| explicit generated binding-map extraction automation | `m2-codegen-agent` | generated-output manifest update |
| `OriginalHistory2` through `OriginalHistory7` coverage | `m2-engine-agent` and `m2-verification-agent` | new manifest preset requiring it |
| preset-driven `PassFeedbackN` support | `m2-engine-agent` | new manifest preset requiring it |
| mipmap behavior | `m2-backend-agent` | new manifest preset requiring it |
| broader corpus support | Director C with root approval | updated manifest ledger and verification bundle |
| Windows-preserving dual-runtime cleanup | future cross-platform pass | explicit root scheduling |

## Evidence Consumed

- generated-output manifest: `plans/07-m2-generated-output-manifest.md`
- engine parity checklist: `plans/07-m2-engine-parity-checklist.md`
- backend capability matrix: `plans/07-m2-backend-capability-matrix.md`
- verification bundle: `plans/07-m2-verification-bundle.md`

## Stop Gate

If a future change adds generated preset coverage without updating the manifest ledger and verification bundle, root should treat it as unpromoted experimental work.
