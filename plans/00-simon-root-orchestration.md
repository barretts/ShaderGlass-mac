# Simon Root Orchestration

## Objective

Run the ShaderGlass mac roadmap as a bounded multi-agent program instead of a flat backlog. Simon owns the root scheduler, three directors own the feature bands, and each director may create short-lived agents only when concurrency materially improves throughput or risk reduction.

This file is the root control plane for:
- `plans/00-init.md`
- `plans/01-router.md`
- `plans/M1-SHADERGLASS-PLAYGROUND-ORCHESTRATION.md`
- `plans/08-seven-feature-director-agent-register.md`
- `plans/director-a-preset-and-interaction.md`
- `plans/director-b-capture-and-shipping.md`
- `plans/director-c-engine-inheritance.md`
- `plans/01-preset-deck.md` through `plans/07-shader-inheritance-m2.md`

## Procedure

### Stage 0 - Root Gate

Root orchestrator: `expert-orchestrator-simon`

Root responsibilities:
- maintain the execution order
- protect disjoint write ownership
- release directors only when their prerequisites are satisfied
- collapse or expand the agent tree only when parallel work is actually independent
- require durable verification artifacts after each feature cut
- stop implementation and replan when a dependency crosses director boundaries

Root artifacts:
- `plans/00-init.md`
- `plans/01-router.md`
- `plans/00-simon-root-orchestration.md`
- `plans/M1-SHADERGLASS-PLAYGROUND-ORCHESTRATION.md`
- `plans/08-seven-feature-director-agent-register.md`

### Stage 1 - Director Creation

Root creates exactly three directors for this roadmap:

1. `director-a-preset-and-interaction`
   - owns `plans/director-a-preset-and-interaction.md`
   - owns Features 1, 2, and 3
2. `director-b-capture-and-shipping`
   - owns `plans/director-b-capture-and-shipping.md`
   - owns Features 4, 5, and 6
3. `director-c-engine-inheritance`
   - owns `plans/director-c-engine-inheritance.md`
   - owns Feature 7
   - reports M2 milestone impact back to root without taking over milestone sequencing

Each director may create agents only for bounded, disjoint tasks. Directors do not keep idle agents alive.

Director bootstrap contract:
- root gives each director one owned file cluster
- root names the current truth of the feature set so directors do not regress implemented work into speculative redesign
- each director must express its own subordinate agent roster before implementation work starts
- each director must stop at the first cross-director ownership collision and report it back to root

### Stage 1.1 - Current Release Packets

Root releases the current planning round with three director packets:

1. Director A packet
   - owned files:
     - `plans/director-a-preset-and-interaction.md`
     - `plans/01-preset-deck.md`
     - `plans/02-live-control-surface.md`
     - `plans/03-before-after-magic.md`
   - current truth:
     - Features 1-3 are implemented baselines
     - the work is preservation, regression control, and bounded follow-on implementation
   - required outputs:
     - one director execution artifact
     - three feature execution packets
     - one agent-release table for each feature
2. Director B packet
   - owned files:
     - `plans/director-b-capture-and-shipping.md`
     - `plans/04-capture-picker-polish.md`
     - `plans/05-export-moment.md`
     - `plans/06-private-release-build.md`
   - current truth:
     - Features 4-6 are implemented baselines
     - the work is preservation, evidence refresh, and truthful shipping
   - required outputs:
     - one director execution artifact
     - three feature execution packets
     - one evidence table for each feature
3. Director C packet
   - owned files:
     - `plans/director-c-engine-inheritance.md`
     - `plans/07-shader-inheritance-m2.md`
     - `plans/07-m2-manifest-ledger.md`
     - `plans/07-m2-codegen-prereqs.md`
   - current truth:
     - Feature 7 is active bounded M2 work
     - generator proof exists, but generator-to-runtime closure is incomplete
   - required outputs:
     - one director execution artifact
     - one feature execution packet
     - one phase-release table and one blocker ledger

### Stage 2 - Director Agent Rules

Directors may create agents when one of these is true:
- two or more feature sections can be refined independently
- verification design is separable from implementation sequencing
- a dependency audit can proceed in parallel with file-touch planning
- a layer seam needs inspection while UI or policy work proceeds separately

Directors should create agents with one of these ownership shapes:
- one file cluster
- one feature slice
- one verification surface
- one dependency or risk audit

Every agent report must include:
- exact files inspected or expected to change
- unresolved blockers
- assumptions that need root confirmation
- the narrowest safe next action

### Stage 3 - Feature Execution Order

1. Feature 1: Preset Deck
2. Feature 2: Live Control Surface
3. Feature 4: Capture Picker Polish
4. Feature 3: Before/After Magic
5. Feature 5: Export Moment
6. Feature 6: Private Release Build
7. Feature 7: Shader Inheritance M2

Reasoning:
- Feature 1 establishes stable preset identity.
- Feature 2 depends on preset identity for per-preset state.
- Feature 4 stabilizes the live capture entry path before compare and export polish.
- Feature 3 and Feature 5 both depend on predictable render-target lifetime.
- Feature 6 matters after the user path is stable enough to ship privately.
- Feature 7 is a bounded M2 expansion only after M1 usability and release discipline are real.

### Stage 4 - Director Tree

```text
root: expert-orchestrator-simon
├── director-a-preset-and-interaction
│   ├── feature-1: preset deck
│   ├── feature-2: live control surface
│   └── feature-3: before/after magic
├── director-b-capture-and-shipping
│   ├── feature-4: capture picker polish
│   ├── feature-5: export moment
│   └── feature-6: private release build
└── director-c-engine-inheritance
    └── feature-7: shader inheritance m2
```

Root agent policy:
- root may release a director only when upstream dependencies for that director are green
- directors may create short-lived agents only inside their owned file and behavior surface
- root closes idle directors or agents once their artifact is merged or their gate is blocked

### Stage 4.1 - Director To Agent Release Packets

Every director-issued agent packet must include:
- owned files
- one feature or one verification surface
- current truth of that feature
- required artifact shape
- explicit stop gate

Root rejects a director packet when:
- the write set overlaps another active agent
- the packet asks an agent to redesign an implemented baseline without a root-approved reason
- the packet has no verification artifact requirement
- the packet has no stop condition

### Stage 5 - Status Matrix

Current feature status for orchestration:

| Feature | Owner | Status | Next gate |
| --- | --- | --- | --- |
| 1 Preset Deck | Director A | implemented | preserve as baseline |
| 2 Live Control Surface | Director A | implemented | preserve as baseline |
| 3 Before/After Magic | Director A | implemented and strongly verified | preserve compare baseline and extend only by explicit cut |
| 4 Capture Picker Polish | Director B | implemented | preserve as baseline |
| 5 Export Moment | Director B | implemented | validate against compare seam if needed |
| 6 Private Release Build | Director B | implemented | keep release contract honest |
| 7 Shader Inheritance M2 | Director C | planned | manifest-first entry gate |

### Stage 5.1 - Current Delegation Round

Root-created directors for the current planning pass:
- Director A: refresh Feature 1-3 plans into preservation/regression execution packets
- Director B: refresh Feature 4-6 plans into preservation/shipping execution packets
- Director C: refresh Feature 7 plans into manifest-first M2 execution packets

Expected outputs from this round:
- one root control-plane update
- one seven-feature director and agent register
- three director execution artifacts
- seven feature plans with explicit agent rosters, verification artifacts, and stop gates

### Stage 6 - Verification Loop

After each feature lands, root requires these checks unless the feature is docs-only:

```sh
backend/build_test.sh
capture/build_test.sh
app/build.sh selftest
```

When `core/` or shared engine surfaces move, add:

```sh
core/build_core.sh
```

For live-path features, also require machine-level smoke verification on a Screen Recording-granted Mac.

### Stage 6.1 - Planning Round Acceptance

The planning round is acceptable only when each feature markdown includes:
- current truth of the feature
- intake packet for the next implementer
- subordinate agent roster with owned surfaces
- implementation stages or preservation loop
- required verification artifacts
- explicit stop gates and escalation conditions

Root rejects a feature plan when it reads like backlog prose instead of an execution packet.

The planning round is not operationally complete until `plans/08-seven-feature-director-agent-register.md` can answer all of these without reopening chat history:
- which director owns each feature
- which agent packet should be released first
- which artifact is required before promotion
- which stop gate forces escalation

### Stage 7 - Handoff Rules

Root may hand off work from one director to another only when:
- ownership changed because a dependency moved layers
- a blocker sits outside the current director's scope
- the receiving director has the narrower correctness surface

Examples:
- if compare cut 2 needs a real engine or backend seam, Director A hands the seam task to Director C while keeping compare UX ownership
- if private release smoke exposes TCC or signing drift, Director B owns the fix and reports the impact back to root

## Stopping Conditions

Root stops the planning pass when all of these are true:
- every feature has a saved markdown plan
- every feature plan exposes an intake packet and subordinate agent packet shape
- each plan names file touchpoints, dependencies, implementation stages, verification, and stop gates
- the three directors have explicit ownership and agent-release rules
- the execution order is defined and justified
- current feature status and next gates are visible in one place

Root stops implementation and replans when:
- two directors need the same write surface at the same time
- a feature breaks the render-thread invariant
- signing, TCC identity, or backend constraints invalidate later phases
- a feature depends on a seam that is still only aspirational, not wired in code

## Procedure Risks

- Too many agents can add review overhead without increasing throughput.
- Feature ordering can drift if M2 work starts before M1 usability stays green.
- Compare, export, and release work can hide backend or signing assumptions that must be surfaced early.
- Director ownership can blur if UI work starts performing engine-seam design locally instead of escalating it.

## Evaluation

The control-plane artifact is correct when:
- the plan set under `plans/` is complete and readable in isolation
- a new implementer can follow the execution order without reconstructing dependencies from chat history
- each director can start work from owned files without ambiguous boundaries
- root can tell, at a glance, which features are planned, implemented, or blocked on a lower-layer seam
- each director can create a subordinate agent packet without inventing missing ownership or artifact rules
