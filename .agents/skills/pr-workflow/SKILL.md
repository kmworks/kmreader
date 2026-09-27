---
name: pr-workflow
description: Create and merge KMReader GitHub pull requests. Use when asked to open a PR, push local changes for review, or merge an existing PR — including composing the squash merge message.
---

# KMReader PR Workflow

Conventions for opening and merging PRs in this repo. Release-copy and version-cycle PRs follow `../appstore-release/SKILL.md` instead.

## Ground Rules

- All git-facing text is English: commits, PR titles and bodies, review comments.
- Conventional-commit titles with a scope: `fix(reader): ...`, `feat(browse): ...`, `refactor(offline): ...`.
- All changes land via PR.
- A `make bump` commit rides inside the feature/fix PR — that is the normal delivery flow, not a separate PR. Skip it only when the user says so.
- Validate before opening: `make format`, then `make build` (all platforms). When localization keys changed, also `make localize` and fill translations per `../localization/SKILL.md`.

## Open a PR

1. Sync and branch:

```bash
git fetch origin
git switch -c <type>/<short-topic> origin/main
```

Name the branch after the title scope, e.g. `fix/reader-end-page-cover`.

2. Commit and `git push -u origin <branch>`. Intermediate commits may be work-in-progress; only the squash message lands on main.
3. Write the body to a file and create the PR with `gh pr create --body-file`; never pass a Markdown body inline:

```bash
cat > /tmp/kmreader-pr-body.md <<'EOF'
...
EOF
gh pr create --title "<conventional title>" --body-file /tmp/kmreader-pr-body.md
```

4. Body sections by change type:
   - fix: `## Problem` (add `## Root cause` when non-obvious) → `## Fix` → `## Validation`
   - feat / refactor: `## What` → `## Why` → `## Validation`
   - Validation lists the commands actually run and their results (`make build` per platform, simulator or manual checks). There are no XCTest targets in this repo; state how behavior was verified.
   - End with `Includes \`make bump\` to build NNN.` when a bump commit is included.
5. Link issues deliberately: `Closes #N` only when merging completes the whole issue; otherwise `Part of #N`.
6. Open ready for review; pass `--draft` only when the user asks. Report the PR URL.

## Merge a PR

1. Gate on green CI and a clean merge state:

```bash
gh pr checks <N>
gh pr view <N> --json mergeable,mergeStateStatus
```

iOS / macOS / tvOS checks must all pass and the state must be `CLEAN`. When checks are red, fix and push again; merge red only on explicit user instruction.

2. Squash merge with a freshly composed message — never the auto-generated commit list. Write the body as a self-contained summary of the merged change: what user-visible behavior changed and why, plus side effects worth knowing later (removed localization keys, migrations, follow-ups). `../changelog/SKILL.md` generates App Store notes from main's commit bodies (`%s` + `%b` between the latest tag and HEAD), so this message is the changelog source material: behavior first, file/class names only when they aid understanding. The PR discussion stays on GitHub; the commit must stand alone.

3. Merge and clean up. Like PR creation, the body goes through a file — never inline a Markdown body into `--body`:

```bash
cat > /tmp/kmreader-merge-body.md <<'EOF'
<summary from step 2>
EOF
gh pr merge <N> --squash --delete-branch \
  --subject "<conventional title> (#N)" \
  --body-file /tmp/kmreader-merge-body.md

git fetch --prune origin
git switch main
git pull --ff-only origin main
```

4. Done when: main contains the squash commit with the new message, and both remote and local feature branches are gone.
