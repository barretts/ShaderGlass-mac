# ShaderGlass Mac Plan Index

This directory is the execution artifact set for the seven-feature mac roadmap.

Read order:
1. `00-init.md`
2. `01-router.md`
3. `00-simon-root-orchestration.md`
4. `M1-SHADERGLASS-PLAYGROUND-ORCHESTRATION.md`
5. `08-seven-feature-director-agent-register.md`
6. the relevant director plan
7. the numbered feature plan

## Root Control Plane

- `00-init.md`
- `01-router.md`
- `00-simon-root-orchestration.md`
- `M1-SHADERGLASS-PLAYGROUND-ORCHESTRATION.md`
- `08-seven-feature-director-agent-register.md`

Root orchestrator:
- `expert-orchestrator-simon`

Directors:
- `director-a-preset-and-interaction` owns Features 1-3
- `director-b-capture-and-shipping` owns Features 4-6
- `director-c-engine-inheritance` owns Feature 7

Director release rule:
- root creates directors
- directors create only bounded feature agents
- feature agents return durable markdown, logs, screenshots, or manifest updates before a phase is considered advanced

## Feature Plans

1. `01-preset-deck.md`
2. `02-live-control-surface.md`
3. `03-before-after-magic.md`
4. `04-capture-picker-polish.md`
5. `05-export-moment.md`
6. `06-private-release-build.md`
7. `07-shader-inheritance-m2.md`
8. `07-m2-manifest-ledger.md`
9. `07-m2-codegen-prereqs.md`
10. `08-seven-feature-director-agent-register.md`
11. `00-init.md`
12. `01-router.md`

## Current Program State

- Feature 1: implemented baseline, preserve and extend carefully
- Feature 2: implemented baseline, preserve and extend carefully
- Feature 3: implemented and strongly verified, treat as preserved baseline unless a new cut is approved
- Feature 4: implemented baseline, preserve and regression-check against app changes
- Feature 5: implemented baseline, preserve export contract against compare and resize changes
- Feature 6: implemented baseline, keep release truthfulness and gate discipline
- Feature 7: planned, next step is manifest-first M2 scope control

## How To Use This Plan Set

- Start at `00-init.md` and `01-router.md` for startup loading and director routing.
- Then use `00-simon-root-orchestration.md` for ownership, gates, and release order.
- Use `08-seven-feature-director-agent-register.md` when root or a director needs a compact release matrix for all seven features.
- Use the director plans for agent-release rules and ownership boundaries.
- Use the numbered feature plans for concrete implementation, verification, and stop conditions.
- Treat each numbered feature plan as an intake packet for future implementation. If a feature plan does not state current truth, owned surfaces, next bounded action, and required artifacts, update that plan before editing code.
- If two features need the same file at the same time, stop and escalate back to root orchestration before editing.
- Treat `07-m2-manifest-ledger.md` and `07-m2-codegen-prereqs.md` as supporting artifacts for Feature 7, not as standalone milestone replacements.

## Planning Round Standard

The root planning pass is complete only when each feature markdown contains:
- a clear current-state statement
- an intake packet for the next implementer
- subordinate agent packets or an explicit reason no delegation is needed
- verification artifacts expected before claiming progress
- stop gates that prevent cross-director drift
