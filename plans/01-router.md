# 01 Router

## Objective

Route work from root orchestration into the right director, then into bounded subordinate agents, using the saved plan set as the routing table.

Simon is the root orchestrator. Directors are the first-level teammates. Directors may create their own teammates as bounded feature agents inside their owned surfaces.

## Procedure

### Root Routing Table

Root orchestrator:
- `expert-orchestrator-simon`

Director routes:
- `director-a-preset-and-interaction`
  - owns Features 1, 2, 3
  - saved plans:
    - `plans/director-a-preset-and-interaction.md`
    - `plans/01-preset-deck.md`
    - `plans/02-live-control-surface.md`
    - `plans/03-before-after-magic.md`
- `director-b-capture-and-shipping`
  - owns Features 4, 5, 6
  - saved plans:
    - `plans/director-b-capture-and-shipping.md`
    - `plans/04-capture-picker-polish.md`
    - `plans/05-export-moment.md`
    - `plans/06-private-release-build.md`
- `director-c-engine-inheritance`
  - owns Feature 7
  - saved plans:
    - `plans/director-c-engine-inheritance.md`
    - `plans/07-shader-inheritance-m2.md`
    - `plans/07-m2-manifest-ledger.md`
    - `plans/07-m2-codegen-prereqs.md`

### Director Teammate Rule

Each director may spawn subordinate teammates under these rules:
- one teammate per bounded feature slice, verification surface, or dependency audit
- one owned file cluster or one explicit behavior surface
- one named artifact to return
- one stop gate that forces handback instead of drift

Allowed teammate shapes:
- regression agent
- polish agent
- persistence agent
- verification agent
- codegen agent
- engine agent
- backend agent
- release or gate audit agent

### Startup Release Packets

Initial packets root should release:
1. Director A
   - first teammate:
     - `preset-regression-agent`
   - packet:
     - preserve preset identity and restore semantics
2. Director B
   - first teammate:
     - `capture-regression-agent`
   - packet:
     - preserve live-entry correctness and evidence freshness
3. Director C
   - first teammates:
     - `m2-codegen-agent`
     - `m2-engine-agent` only after codegen artifacts are current
   - packet:
     - close the active M2 runtime gap on the manifest-selected preset set

### Routing Priority

Current root priority:
1. Feature 7 active implementation
2. Feature 1 through Feature 6 preservation mode
3. shipping truth only after current artifacts exist on the same SHA

### Routing Decision Rules

Send work to Director A when:
- the change is preset, parameter, or compare behavior

Send work to Director B when:
- the change is capture, export, release, signing, or evidence truth

Send work to Director C when:
- the change is upstream inheritance, ShaderGen, shared-engine behavior, or Metal backend capability for Feature 7

Escalate back to root when:
- a write surface overlaps directors
- a feature contract must widen
- required evidence cannot be produced

## Stopping Conditions

Stop routing when:
- two directors need the same files at the same time
- a director tries to absorb another director's ownership
- a teammate packet has no artifact or stop gate

## Procedure Risks

- False concurrency if directors spawn teammates into overlapping surfaces.
- Weak routing if current feature status is not refreshed in the register.

## Evaluation

Routing is correct when root can pick the right director and the director can pick the next teammate from saved files alone.
