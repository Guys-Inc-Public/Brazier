---
session: 2026-09-28-repository-seeded
repo: Guys-Inc-Public/Brazier
branch: main
driver: CJ, with Claude Code
outcome: merged
---

# Repository seeded

## Intent
Turn the study of 2026-09-28 into a repository the build can start from: brief, architecture, decisions, relay reference, the mark, and the record of the marks rejected on the way.

## What was done
- Study written as a Claude artifact, with two boards drawn under Branding-Standards' new board standard (its PR #19).
- Five rounds of marks; CJ chose the Curl and the name Brazier. Mark shipped to Branding-Standards (PR #20, ADR 0019: a mark may be soft).
- This repository: README on the brand, MIT, brand plugin enabled, `docs/` shelves seeded, `design/mark-rounds/` archive, `scripts/check.py` and a CI workflow.

## What was learned
- Four rounds of hard-edged marks were rejected for sharpness; a companion to another product's flame wants a soft flame in our tones.
- The study's two drawings were the first boards; chips need `labelAt` when a cable's longest run crosses a part.

## Open
- Trademark and App Store name check for Brazier.
- Milestone 1: the relay under `relay/`, deployed for the estate; then the Grafana contact point.
- Verify Grafana 13 JWT audience handling and the alerting API paths by curl before any app code.
