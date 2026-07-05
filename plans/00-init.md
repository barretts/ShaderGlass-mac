# 00 Init

## Objective

Define the startup contract for the mac roadmap control plane.

This file is the first artifact to load before any director, feature, or implementation packet is released. Its job is to make root orchestration deterministic: load the router, boot the directors, and hand work to the saved plan set instead of reconstructing state from chat.

## Procedure

### Startup Sequence

Startup order:
1. load `plans/00-init.md`
2. load `plans/01-router.md`
3. load `plans/00-simon-root-orchestration.md`
4. load `plans/08-seven-feature-director-agent-register.md`
5. load the relevant director plan
6. load the relevant feature plan

Root orchestrator:
- `expert-orchestrator-simon`

Root responsibilities at startup:
- confirm the plan set is the active source of truth
- release the directors
- keep directors inside owned surfaces
- require named artifacts before any feature is promoted

### Startup Director Packet

Directors started by root:
1. `director-a-preset-and-interaction`
2. `director-b-capture-and-shipping`
3. `director-c-engine-inheritance`

Startup rule:
- directors start from their saved plan files
- directors may spawn bounded subordinate agents only after reading their owned feature plans
- no director may widen its charter during startup

### Startup Evidence

Startup is valid only when all of these are true:
- Simon is the named root orchestrator
- the three directors are named and mapped to features
- the seven-feature register exists
- each director has an explicit next release packet

## Stopping Conditions

Stop startup and re-route when:
- the router and root plan disagree about ownership
- a director lacks a saved plan artifact
- a feature has no named artifact or stop gate

## Procedure Risks

- Startup drift if the router or register changes without updating this file.
- Director sprawl if startup releases work before ownership is checked.

## Evaluation

Startup is correct when a new implementer can begin at this file and reach the right director and feature packet without chat history.
