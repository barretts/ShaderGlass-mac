# Seven-Feature Director And Agent Register

## Objective

Give root orchestration one compact control artifact that covers all seven roadmap features, their owning directors, the first agent packets to release, the next bounded implementation action, and the evidence required before promotion.

This file does not replace the feature plans. It is the routing and release register that lets root and the directors decide what to run next without reopening chat history.

## Procedure

### Root Release Model

Root orchestrator: `expert-orchestrator-simon`

Release chain:
1. root releases one director
2. director releases one or more bounded feature agents
3. agents return artifacts to the director
4. director updates the owning feature plan
5. root decides whether the feature advances, holds, or escalates

Promotion rule:
- no feature advances on prose alone
- every released packet must come back with a log, screenshot, manifest note, matrix update, or explicit blocker

### Feature Register

| Feature | Owner | Current truth | First agent packet to release | Next bounded action | Required artifact before promotion | Stop gate |
| --- | --- | --- | --- | --- | --- | --- |
| 1 Preset Deck | Director A | implemented baseline | `preset-regression-agent` | revalidate stable preset ids, selection, restore, and placeholder fallback | selftest or build log, deck screenshot, preset-id note | stop if preset ids or persistence keys would change |
| 2 Live Control Surface | Director A | implemented baseline | `parameter-regression-agent` | revalidate metadata contract, reset behavior, and per-preset replay | selftest or build log, control-surface screenshot, replay note | stop if UI needs raw engine internals or replay stops keying off stable preset id |
| 3 Before/After Magic | Director A | implemented and strongly verified baseline | `compare-regression-agent` | preserve bypass and split compare determinism as app/render code moves | selftest log, split compare screenshot, restore-exactness note | stop if compare requires new engine lifetime or backend semantics outside Director A |
| 4 Capture Picker Polish | Director B | implemented baseline | `capture-regression-agent` | revalidate target restore, stale-target recovery, permission truth, and start/stop safety | capture or app log, picker screenshot or smoke note, permission-state note | stop if fix requires capture-model redesign or non-Director-B ownership |
| 5 Export Moment | Director B | implemented baseline | `export-contract-agent` | revalidate that export still means processed output and still resolves once under resize/stop/quit pressure | selftest or export log, exported PNG evidence, export contract note | stop if exported surface can no longer be stated without policy change |
| 6 Private Release Build | Director B | implemented baseline | `gate-audit-agent` and `release-runner-agent` | revalidate branch-gate truth, signing truth, and artifact parity on the current SHA | `release/private-build.sh` log, manifest, checksums, release-notes truth note | stop if any claimed gate or signing result lacks current artifact backing |
| 7 Shader Inheritance M2 | Director C | active bounded implementation with mandatory manifest mac gates green | `m2-backend-agent`, then `m2-verification-agent` | extend from mandatory-manifest core proof into live smoke and explicit binding-map evidence | current core/backend/capture/app logs, generated-output manifest, updated phase ledger | stop if the manifest forces out-of-scope compute, storage-image, mipmap, or unstable binding behavior |

### Director Release Order

Director A release order:
1. Feature 1 preservation packet
2. Feature 2 preservation packet
3. Feature 3 preservation packet

Director B release order:
1. Feature 4 evidence refresh packet
2. Feature 5 export contract packet
3. Feature 6 shipping-truth packet

Director C release order:
1. Feature 7 backend capability packet
2. Feature 7 verification packet
3. Feature 7 broader corpus or live-smoke packet

### Agent Packet Minimum

Every director-issued agent packet must state:
- feature id
- exact owned files or surfaces
- preserved invariants
- one bounded next action
- one named return artifact
- one explicit stop gate

### Current Branch Recommendation

Recommended next releases from root:
1. keep Director C active on Feature 7 and shift from codegen/engine closure into live smoke and verification expansion; `ntsc-adaptive-4x` remains phase-active rather than cold-run deterministic, while `film/technicolor` and `motionblur/mix_frames` are now green in host-backed core coverage
2. keep Director A and Director B in preservation mode unless Feature 7 changes spill into app, compare, export, or release contracts
3. require any new branch claims for Features 4-6 to cite current artifacts on the same SHA

## Stopping Conditions

Stop and escalate to root when:
- two active packets want the same write surface
- a director needs to widen a feature contract to finish a bounded task
- the required artifact cannot be produced on the current machine
- Feature 7 instability starts masking M1 baseline truth

## Procedure Risks

- A compact register can drift if the detailed feature plans move and this file is not refreshed.
- Director C can still sprawl if manifest-first discipline weakens.
- Director B can accept stale evidence unless artifact freshness is checked against the current SHA.

## Evaluation

This register is correct when:
- root can choose the next release without reopening the full feature plans first
- each director has an obvious first packet to issue
- every feature has a concrete artifact and stop gate attached to it

## Current Evidence

Feature 7 current gate evidence:
- core: `.logs/build-core-m2-manifest-host.log`
- backend: `.logs/build-backend-current-after-m2.log`
- capture: `.logs/build-capture-current-after-m2.log`
- app selftest: `.logs/build-app-selftest-current-after-m2.log`
