# Feature 6 - Private Release Build

## Objective

Preserve the implemented private-release pipeline as a truthful shipping gate: produce a signed, packaged, and documented ShaderGlass app artifact for direct tester distribution, while making no false claims about notarization, branch health, or public-distribution readiness.

This is a release-truth feature, not a public launch pipeline and not a place to hide branch regressions behind old artifacts.

Root placement:
- owner: `director-b-capture-and-shipping`
- root sequence position: Feature 6 follows current Feature 4 and Feature 5 evidence
- shipping may proceed only on what the branch can currently prove

## Procedure

### Stage 0 - Preserved Shipping Contract

The baseline to preserve is already implemented:
- `release/private-build.sh` exists
- release mode requires explicit signing rather than silent ad-hoc fallback
- release artifacts include manifest material and durable logs
- the private-release path already distinguishes itself from notarized public shipping

The shipping contract remains:
- `app/build.sh` is still the app build and selftest entry point
- repo test scripts remain branch gates unless explicitly retired
- release mode requires a usable signing identity
- git metadata remains required for artifact naming and provenance
- packaging runs locally and does not rely on network-only infrastructure
- release notes and manifests must describe the current branch truth, not the last known green state

### Stage 1 - File Touchpoints

Primary files:
- `release/private-build.sh`
- `app/build.sh`
- `dist/manifest.json`
- `dist/checksums.txt`
- `dist/release-notes.txt`

Secondary files that can force reevaluation without changing ownership:
- `app/Info.plist`
- `app/ShaderGlass.entitlements`
- `RUNNING.md`
- any test/build script named in the branch gate set

### Stage 2 - Ownership Boundaries And Agent Roster

Director: `director-b-capture-and-shipping`

Director B owns:
- whether the branch is eligible for private packaging
- whether logs, manifest, and release notes tell the truth about current gates
- whether Feature 4 and Feature 5 evidence are current enough to support shipping

Director B does not own:
- public notarization rollout
- remote distribution infra
- redefining core app quality gates outside the bounded private-release contract

Subordinate agents:
- `release-runner-agent`: verify the top-level script still drives the whole bounded flow.
- `signing-truth-agent`: verify identity use, strict-fail behavior, and recorded signing diagnostics.
- `gate-audit-agent`: verify that each branch gate runs, logs to a durable file, and is represented honestly in the manifest.
- `distribution-agent`: verify artifact naming, checksums, notes, and tester-facing caveats.
- `release-qa-agent`: verify unzip, inspect, launch, and packaged-app parity with the verified build.

Required outputs from subordinate agents:
- one gate report
- one log or manifest reference
- one explicit blocker when shipping truth cannot be maintained

### Stage 2A - Intake Packet For Future Work

Before any release implementation or verification pass, assemble a Feature 6 intake packet with:
- branch SHA and working tree cleanliness state
- touched files within release/build/signing surface
- current Feature 4 evidence status:
  - current
  - stale
  - blocked
- current Feature 5 evidence status:
  - current
  - stale
  - blocked
- machine prerequisites:
  - signing identity present
  - codesign available
  - `spctl` runnable
  - all required branch gates runnable
- last known release artifact set and why it is or is not valid for this SHA

Decision from the intake packet:
- `preserve-only`: no release-relevant touchpoint moved and upstream evidence is still current
- `verify-only`: release-relevant touchpoint moved but packaging truth should still hold
- `bounded-fix`: branch truth, logging, signing, or artifact parity is currently broken

### Stage 3 - Implementation Stages

1. preserve release entrypoint:
   - keep `release/private-build.sh` as the one-command bounded flow
   - keep dirty-worktree rejection and provenance requirements intact
2. preserve gate truth:
   - keep branch gates current and recorded
   - keep Feature 4 and Feature 5 evidence attached to the exact branch state under review
3. preserve signing truth:
   - keep strict signing identity requirements
   - keep codesign and `spctl` results captured exactly as observed
4. preserve packaging truth:
   - keep zip, manifest, checksums, and release notes aligned to the built artifact
   - keep artifact naming tied to version and git SHA
5. preserve scope discipline:
   - keep notarization explicitly out of scope
   - keep remote distribution infra out of scope

### Stage 3A - Agent Release Packets

`release-runner-agent`
- files: `release/private-build.sh`, `app/build.sh`
- task: verify the top-level bounded flow still builds, gates, signs, and packages in the documented order
- must return:
  - release-run log reference
  - exact failed stage, if any

`signing-truth-agent`
- files: signing configuration, bundle metadata, release script hooks
- task: verify strict signing requirements and capture codesign/`spctl` truth as observed
- must return:
  - signing identity note
  - codesign result
  - `spctl` result or blocker

`gate-audit-agent`
- files: `.logs/` outputs, manifest fields, gate references
- task: map every claimed gate to a current artifact on the same SHA
- must return:
  - gate ledger with pass/fail/blocked state
  - manifest/log mismatch note when present

`distribution-agent`
- files: `dist/manifest.json`, `dist/checksums.txt`, `dist/release-notes.txt`
- task: verify artifact naming, SHA parity, and tester-facing caveats
- must return:
  - artifact parity note
  - checksum verification note
  - release-notes truth note

`release-qa-agent`
- files: packaged app artifacts
- task: verify unzip, inspect, and packaged-app parity against manifest claims
- must return:
  - packaged-app inspection note
  - blocker if local trust/install limitations prevent a meaningful check

### Stage 4 - Dependency Gates

Release review is mandatory when any of these change:
- `release/private-build.sh`
- `app/build.sh`
- signing configuration or bundle metadata
- branch gates that Feature 6 depends on
- app or compare changes that can invalidate Feature 4 or Feature 5 verification

Gate rules:
1. do not treat historical logs as current branch evidence when app, compare, or export code changed
2. block packaging when Feature 4 live-entry evidence or Feature 5 export evidence is stale after relevant branch changes
3. block packaging when a required gate is missing, skipped, or cannot run honestly on the current machine
4. record `spctl` truth exactly as observed, even when the result is a bounded private-release failure

Dependencies on other features:
- depends on Feature 4 for current live-entry evidence
- depends on Feature 5 for current export evidence
- depends on root branch ordering so shipping review does not outrun product truth

### Stage 5 - Deliverables

Required release deliverables:
- packaged artifact under `dist/`
- `dist/manifest.json`
- `dist/checksums.txt`
- `dist/release-notes.txt`
- durable `.logs/` references for every branch gate and signing check
- explicit statement of current branch status for Features 4, 5, and 6

Manifest/report deliverables must include:
- app version
- git SHA
- build date
- bundle id
- minimum macOS version
- signing identity
- artifact filename
- artifact SHA-256
- gate results and log paths
- Feature 4 and Feature 5 evidence status
- `spctl` result
- notarization status: not performed

Implementation packet output for future delegated work:
- issue statement:
  - which branch change or failed gate threatened private-release truth
- bounded change list:
  - exact Director B-owned release files allowed for implementation
- verification bundle:
  - which gates were rerun on this SHA
  - which artifact parity checks passed
  - which upstream feature proofs were refreshed or found stale
- shipping decision:
  - blocked
  - packaging truth restored but upstream evidence stale
  - eligible for private-release review

### Stage 6 - Verification Artifacts

Primary release run:

```sh
release/private-build.sh
```

Required artifact-backed checks:
- the artifact name includes version and git SHA
- `dist/manifest.json` references the same `git rev-parse HEAD` used for the build
- `shasum -a 256 -c dist/checksums.txt` passes
- `codesign --verify --verbose=2` passes on the packaged app
- packaged-app verification matches the manifest and signing notes
- if `spctl` fails, that failure is recorded as observed and not softened in chat or notes

Branch gate set to preserve unless root changes it explicitly:
1. `core/build_core.sh`
2. `backend/build_test.sh`
3. `capture/build_test.sh`
4. `demo/build.sh`
5. `spike/build.sh`
6. `app/build.sh selftest`

Artifact expectations:
- one current private-build log under `.logs/`
- one manifest matching the built artifact name and git SHA
- one checksum verification note
- one packaged-app signing verification note
- one explicit note recording whether `spctl` passed or failed on the current machine

Preferred evidence bundle names for delegated work:
- `feature-6-intake.md`
- `feature-6-gate-ledger.md`
- `feature-6-signing-note.md`
- `feature-6-distribution-note.md`

If these are not created as files, the same packet structure must still be reflected in the returned notes or plan update.

## Stopping Conditions

This feature remains acceptable only when all of the following are still true:
- One release command builds the app, runs gates, signs, packages, and emits release metadata.
- Dirty worktrees are rejected by default.
- Release mode cannot silently fall back to ad-hoc signing.
- The zip artifact, manifest, checksums, and release notes exist in `dist/`.
- Codesign verification results are captured.
- `spctl` status is captured honestly, including failure when applicable.
- The packaged app can be unzipped and inspected as the same build that the manifest describes.

Stop and replan when any of the following becomes true:
- release truth depends on network credentials, notarization credentials, or remote infra outside this milestone
- required gates cannot run on the target machine or current branch with no bounded workaround
- Feature 4 or Feature 5 evidence is stale, missing, or contradicted by current branch changes
- versioning, signing, or packaged-app parity cannot be sourced from the actual built artifact
- release notes would need to make a claim the current logs and manifest cannot support
- the only available evidence is historical output from an older branch state

Delegation stop gates:
- stop `release-runner-agent` if the branch cannot produce a single authoritative release-run log for the current SHA
- stop `signing-truth-agent` if signing validation would rely on a different identity than the intended branch artifact
- stop `gate-audit-agent` if any claimed gate has no literal artifact backing
- stop `distribution-agent` if manifest, checksums, and packaged artifact do not describe the same build output
- stop the whole Feature 6 pass if either Feature 4 or Feature 5 remains stale after release-relevant branch churn

## Procedure Risks

- Self-signed or privately signed apps are not equivalent to notarized public releases.
- Release scripts that accept dirty worktrees produce artifacts with weak provenance.
- Gate coverage may be uneven across machines with different Metal or permission states.
- Signing may succeed locally but still produce an artifact that another tester must manually trust.
- Historical green logs can create a false shipping signal if branch-sensitive features were not revalidated.

## Evaluation

This plan is healthy when:
- private release remains a truthful statement about the current branch, not just about the release script
- each accepted shipping claim points to a log, manifest field, checksum, or packaged-artifact check
- shipping stops immediately when live-entry, export, signing, or gate evidence stops being believable

## Open Risks To Carry Forward

- Notarization remains a separate follow-on milestone and should not be conflated with private release readiness.
- A future CI-oriented release path may need a machine-readable manifest schema version once this private flow stabilizes.
