---
name: docs
description: Regenerate README.md, APP_STORE_DESCRIPTION.txt, and website/src/pages/index.tsx based on current important product features in the codebase.
---

# Docs

Regenerate key project docs from current product capabilities.

## When To Use

- The user asks to refresh project docs after feature changes.
- README and App Store description are outdated.
- Marketing landing content in `website/src/pages/index.tsx` needs alignment with current app features.

## Target Files

- `README.md`
- `APP_STORE_DESCRIPTION.txt`
- `website/src/pages/index.tsx`

## Scope Rules

- Reflect current important features only.
- Treat docs as a durable product overview, not a summary of every recent change.
- Do not add minor UX polish, small fixes, or short-lived release-specific details unless they change the core product positioning.
- Keep product-facing language clear and concise.
- Avoid low-level technical implementation details.
- Keep messaging consistent across all three files.
- Keep any supported-language claims aligned with the current app localization set.

## Inputs To Read First

- `AGENTS.md` (project capabilities and architecture summary) and `.agents/skills/repo-conventions/SKILL.md` (subsystem conventions)
- Current target files (to preserve structure where appropriate)
- Relevant feature modules under `KMReader/Features/` when needed

## Update Workflow

1. Collect current user-visible features from codebase and project docs.
2. Decide the most important feature set to present.
3. Filter out low-signal recent changes that belong in changelogs rather than evergreen docs.
4. Update all target files so wording and feature emphasis stay aligned.
5. Keep `README.md` as the most complete overview.
6. Keep `APP_STORE_DESCRIPTION.txt` concise and store-appropriate.
7. Keep `website/src/pages/index.tsx` aligned with the same feature priorities.

## Validation

- Ensure all three files mention the same core features.
- Remove stale or no-longer-available claims.
- Keep formatting clean and ready to publish.
