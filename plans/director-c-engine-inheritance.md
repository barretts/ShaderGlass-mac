# Director C - Engine Inheritance

## Objective

Own the bounded M2 inheritance path from upstream-shaped presets into the shared ShaderGlass engine on Metal, without destabilizing the shipped mac app baseline.

Owned feature:
- Feature 7 - Shader Inheritance M2

## Intake Packet

Use this packet when Director C is released for a future implementation pass.

- mission:
  - land the smallest durable M2 inheritance slice that converts selected upstream-shaped presets into Metal-ready runtime presets
- immutable current truth:
  - M2 pinned-manifest inheritance is implemented and adopted as the baseline for the selected corpus
  - Phase 7.1 manifest planning exists
  - Phase 7.2 prerequisite proof exists
  - generator integration is proven for the mandatory manifest presets
  - engine, backend, verification, and adoption artifacts now exist for the pinned corpus
- owned artifacts:
  - `plans/07-shader-inheritance-m2.md`
  - `plans/07-m2-manifest-ledger.md`
  - `plans/07-m2-codegen-prereqs.md`
  - `plans/07-m2-generated-output-manifest.md`
  - `plans/07-m2-engine-parity-checklist.md`
  - `plans/07-m2-backend-capability-matrix.md`
  - `plans/07-m2-verification-bundle.md`
  - `plans/07-m2-adoption-decision.md`
- release rule:
  - do not expand scope beyond the pinned manifest without updating the ledger first
- implementation objective:
  - move from planning proof to executable phase packets that a subordinate agent can run without reconstructing context from chat

## Procedure

### Stage 0 - Ownership Boundary

Director C owns:
- manifest-first preset selection for M2
- ShaderGC MSL generation path
- shared-engine behavior closure for the chosen manifest
- backend capability proof required by that manifest
- M2 verification artifacts

Director C does not own:
- M1 preset browsing and parameter UI
- capture picker UX
- release packaging policy

### Stage 1 - Agent Release Rules

Director C may create these agents:
- `m2-preset-agent`
- `m2-codegen-agent`
- `m2-engine-agent`
- `m2-backend-agent`
- `m2-verification-agent`

Release order:
1. `m2-preset-agent`
2. `m2-codegen-agent`
3. `m2-engine-agent`
4. `m2-backend-agent`
5. `m2-verification-agent`

No later agent starts before the previous one produces a durable artifact.

Director C agent packet rule:
- each agent gets one phase, one file cluster, and one artifact type
- each later agent must cite the prior artifact it is consuming
- each agent must classify every failure as `fix-here`, `defer-out-of-manifest`, or `block-root`

Artifact contract per agent:
- `m2-preset-agent` produces the manifest-first preset ledger inside the project plan set
- `m2-codegen-agent` produces a generator-output manifest and binding notes
- `m2-engine-agent` produces an engine parity checklist tied to manifest requirements
- `m2-backend-agent` produces a backend capability matrix
- `m2-verification-agent` produces the final evidence bundle and acceptance summary

### Stage 1A - Director Packet Format

Every subordinate release packet should include:
- intake:
  - exact phase name
  - consumed artifacts
  - allowed file surfaces
  - explicit non-goals
- implementation stages:
  - 2-5 bounded steps with a concrete done signal for each
- verification artifacts:
  - logs, generated manifests, matrices, or goldens the agent must leave behind
- stop gates:
  - exact conditions that require halting instead of guessing
- handoff packet:
  - what the next agent may assume is true
  - what remains hypothesis until re-verified

### Stage 2 - Current State

Verified current state:
- M2 is implemented for the pinned mandatory manifest and remains intentionally bounded.
- The mac app already renders through the shared engine, which makes inheritance work realistic.
- Metal-ready generated payloads for the pinned manifest are consumed by the mac core path.
- Phase 7.1 manifest work is already captured in `plans/07-m2-manifest-ledger.md`.
- Phase 7.2 prerequisite proof and first `GenerateMSL(...)` proof are already captured in `plans/07-m2-codegen-prereqs.md` and `.logs/check-m2-generate-msl.log`.
- Mandatory preset generated output and binding notes are captured in `plans/07-m2-generated-output-manifest.md`.
- Engine parity is captured in `plans/07-m2-engine-parity-checklist.md`.
- Metal backend capability is captured in `plans/07-m2-backend-capability-matrix.md`.
- Verification and live smoke evidence are captured in `plans/07-m2-verification-bundle.md`.
- Runtime adoption and follow-on scope are captured in `plans/07-m2-adoption-decision.md`.

### Stage 3 - Active Next Work

Next bounded task:
- preserve the pinned manifest baseline and release only follow-on agents for explicitly recorded expansion work

Completed for the pinned corpus:
1. generator integration for the mandatory manifest
2. engine semantics needed by the manifest
3. backend capability proof
4. verification evidence, including live smoke
5. adoption decision and follow-on ledger

Immediate root handoff rule:
- Director C does not re-run `m2-preset-agent` work unless the manifest changes
- Director C does not release broader-corpus work until the follow-on ledger is turned into a new bounded manifest
- Director C treats binding-map extraction automation, histories 2-7, feedback presets, mipmaps, broader corpus support, and Windows cleanup as follow-on work

### Stage 4 - Phase Release Packets

#### Packet A - Manifest Intake To Codegen

- producer:
  - `m2-preset-agent`
- consumed artifact:
  - `plans/07-m2-manifest-ledger.md`
- codegen may assume:
  - the four pinned presets are the only mandatory corpus for the first M2 pass
  - unsupported keys already encountered are classified
  - later corpus expansion is out of scope
- codegen must still prove:
  - real generator output for mandatory presets
  - stable entry points
  - stable binding metadata

#### Packet B - Codegen Intake To Engine

- producer:
  - `m2-codegen-agent`
- required artifact:
  - generated-output manifest with per-pass binding maps
- current artifact:
  - `plans/07-m2-generated-output-manifest.md`
- engine may assume:
  - at least one mandatory preset generates repeatably
  - output pass order and symbol names are stable enough to consume
- engine must still prove:
  - shared engine semantics actually satisfy the generated preset
  - no preset-specific hand edits are required after generation

#### Packet C - Engine Intake To Backend

- producer:
  - `m2-engine-agent`
- required artifact:
  - parity checklist mapping each manifest behavior to concrete engine code paths
- current artifact:
  - `plans/07-m2-engine-parity-checklist.md`
- backend may assume:
  - required formats, copies, textures, and samplers are now concrete instead of speculative
- backend must still prove:
  - Metal support exists for every mandatory manifest requirement

#### Packet D - Backend Intake To Verification

- producer:
  - `m2-backend-agent`
- required artifact:
  - backend capability matrix with explicit supported, deferred, or blocking status
- current artifact:
  - `plans/07-m2-backend-capability-matrix.md`
- verification may assume:
  - remaining failures are render correctness or integration failures, not unknown backend capability
- verification must still prove:
  - offscreen goldens, history behavior, static textures, and one app-level smoke
- current artifact:
  - `plans/07-m2-verification-bundle.md`

#### Packet E - Verification Intake To Adoption

- producer:
  - `m2-verification-agent`
- required artifact:
  - verification bundle with core/backend/capture/app logs and live smoke outputs
- current artifact:
  - `plans/07-m2-adoption-decision.md`
- root may assume:
  - the pinned M2 corpus is adopted as the current generated shared-engine baseline
  - broader corpus expansion is follow-on scope, not implicit unfinished M2 work

### Stage 5 - Director Verification Bundle

Director C is not done when chat says the work is ready. Director C is done when these artifacts exist together:
- manifest ledger
- codegen prerequisite and integration evidence
- generated-output manifest for mandatory presets
- engine parity checklist
- backend capability matrix
- verification bundle with test logs and one live smoke result
- adoption decision note

Any missing artifact keeps the phase in progress even if partial code exists.

## Stopping Conditions

Stop and escalate to root when:
- the chosen manifest needs unsupported compute, storage-image, or mipmap behavior outside approved scope
- generated payloads cannot provide stable bindings or entry points
- M2 work starts masking failures in the current M1 app baseline
- a subordinate agent needs to edit outside the declared file or code ownership for its phase
- an agent cannot leave the required durable artifact for the next phase to consume

## Procedure Risks

- M2 can sprawl quickly if manifest discipline is weak.
- Backend gaps may surface late if the preset corpus is chosen for appeal instead of diagnostic value.
- Parallel work can create false negatives if M2 verification runs on a branch where M1 is not actually stable.

## Evaluation

Director C is operating correctly when:
- the manifest remains small and explicit
- every engine or backend change is traceable to a mandatory preset requirement
- M2 evidence can be reviewed independently from chat history
- follow-on corpus work starts from a new bounded packet instead of reopening the completed pinned-manifest gate
