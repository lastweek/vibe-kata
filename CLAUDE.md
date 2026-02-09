# CLAUDE.md

## Project context
This repository is an infrastructure / systems project.
Correctness, performance, observability, and long-term maintainability are prioritized over short-term velocity.

Assume this code will evolve into production-quality software.

## Non-negotiable engineering principles
- All new functionality must include tests (unit or integration).
- Code should be written with testability in mind; refactor if necessary.
- Critical execution paths must have basic observability (logs, metrics).
- CI is assumed from day one; code must run deterministically in CI.
- Favor explicit behavior over implicit or “magic” behavior.

## Observability guidelines
- Add observability only where it provides actionable signal.
- Be explicit about the cost of observability (cardinality, frequency, hot paths).
- Prefer low-cardinality metrics by default.
- Logs should be structured and useful for debugging failures.
- Avoid adding metrics or logs on tight loops unless explicitly justified.

## Performance and systems considerations
- Prefer simple designs first; optimize only when bottlenecks are clear.
- Be conscious of allocation, memory lifetime, and data movement.
- Avoid unnecessary abstractions in hot paths.
- Document performance assumptions when they matter.

## Coding expectations
- Avoid global state unless explicitly justified.
- Errors should fail fast with clear, actionable messages.
- Prefer deterministic behavior over retries or hidden recovery.
- Keep interfaces minimal and intentional.
- Avoid premature generalization.

## Dependencies and tooling
- Prefer minimal dependencies.
- Justify heavyweight dependencies with clear benefits.
- Tooling should be automatable and CI-friendly.

## When requirements are ambiguous
When something is unclear:
1. State assumptions explicitly.
2. Choose the simplest correct design.
3. Leave clear TODOs with concrete follow-up actions.

## Tone and output expectations
- Prefer concise, precise explanations.
- Avoid restating the same idea in different words.
- If tradeoffs exist, state them explicitly.
