---
name: appstore-release
description: "Coordinate the KMReader App Store release workflow. Use when asked to prepare or run a KMReader App Store release across iOS, macOS, and tvOS: refresh docs and APP_STORE_CHANGELOG.txt, open and merge the release-copy PR, create or update App Store Connect versions, attach builds and submit for review, then run make minor and open/merge the next-version-cycle PR."
---

# KMReader App Store Release

Run the end-to-end KMReader App Store release workflow while keeping local release copy, App Store Connect metadata, submitted builds, and the next development version in sync.

## Required Inputs

- Release version, for example `4.10`.
- Build number to submit, for example `439`. If omitted, resolve the latest valid build per platform before attaching anything.
- Target platforms are always `IOS`, `MAC_OS`, and `TV_OS` unless the user explicitly narrows scope.

KMReader App Store app ID is `6755198424`. Confirm it with `asc apps list --name KMReader` before making remote changes.

## Related Local Skills

Before editing release copy, read and follow:

- `../changelog/SKILL.md` for `APP_STORE_CHANGELOG.txt`
- `../docs/SKILL.md` for `README.md`, `APP_STORE_DESCRIPTION.txt`, and `website/src/pages/index.tsx`
- `../testflight/SKILL.md` for distributing builds to TestFlight groups

Do not duplicate those instructions here. This skill owns ordering, GitHub PR handling, App Store Connect release actions, and the follow-up version-cycle PR.

## Guardrails

- Work from a clean or understood git state. Do not mix unrelated local changes into release PRs.
- Use `asc --help` for command shape when uncertain; CLI flags can drift.
- Do not use raw `xcodebuild`; this repo uses Makefile automation.
- Do not create duplicate App Store Connect versions. Reuse existing editable versions.
- Stop before submission if any platform build is not `VALID`, metadata is incomplete, content rights are missing, or encryption compliance is unresolved.
- Do not rely on `asc submit status --id`; App Store Connect can reject that lookup with a `GET_INSTANCE` limitation. Verify final state through `asc versions get/list` and review submission responses.
- Keep release notes user-facing. Exclude bump commits, CI, implementation details, file names, class names, and refactor-only work.
- Use `gh pr create --body-file` and `gh pr edit --body-file`; do not pass Markdown bodies inline.

## Phase 1: Refresh Release Copy

1. Inspect context:

```bash
git status --short --branch
git log --oneline --decorate -n 20
git tag --sort=-creatordate | head -20
```

2. Generate `APP_STORE_CHANGELOG.txt` from the latest tag to `HEAD`. Read full commit bodies, not only subjects.
3. Refresh `README.md`, `APP_STORE_DESCRIPTION.txt`, and `website/src/pages/index.tsx` from current important product capabilities.
4. Keep docs evergreen and concise. `APP_STORE_DESCRIPTION.txt` should be store-appropriate; `website/src/pages/index.tsx` should align with the same product priorities.
5. Validate release copy:

```bash
git diff --check
wc -c APP_STORE_DESCRIPTION.txt APP_STORE_CHANGELOG.txt
```

If validation needs stronger proof, run the smallest relevant repo command. Do not run repository-wide formatting just for release copy.

## Phase 2: PR And Merge Release Copy

Create a dedicated branch:

```bash
git switch -c "docs/refresh-${version//./}-store-copy"
git add README.md APP_STORE_DESCRIPTION.txt APP_STORE_CHANGELOG.txt website/src/pages/index.tsx
git commit -m "docs: refresh ${version} store copy"
git push -u origin "docs/refresh-${version//./}-store-copy"
```

Create the PR with a body file:

```bash
cat > /tmp/kmreader-release-copy-pr-body.md <<EOF
## Problem
The public documentation and App Store release copy need to match the ${version} release.

## Approach
Refresh README, App Store description, landing page copy, and App Store changelog from the current user-visible product changes.

## Validation
- [x] Reviewed latest-tag-to-HEAD commits
- [x] Ran git diff --check
EOF

gh pr create --title "docs: refresh ${version} store copy" --body-file /tmp/kmreader-release-copy-pr-body.md
gh pr view <PR_NUMBER> --json url,title,body,headRefName,baseRefName,state,statusCheckRollup
```

Merge when checks are acceptable or the user has explicitly authorized immediate release workflow completion:

```bash
gh pr merge <PR_NUMBER> --squash --delete-branch \
  --subject "docs: refresh ${version} store copy" \
  --body "Update README, App Store description, landing page copy, and App Store changelog for the ${version} release."

git fetch --prune origin
git switch main
git pull --ff-only origin main
git status --short --branch
```

Do not continue to App Store Connect metadata updates from an unmerged local-only release-copy branch unless the user explicitly wants that.

## Phase 3: Create Or Reuse ASC Versions

Confirm app and versions:

```bash
asc apps list --name KMReader --pretty
asc versions list --app 6755198424 --version "$version" --platform IOS,MAC_OS,TV_OS --pretty
```

For each missing platform version:

```bash
asc versions create --app 6755198424 --version "$version" --platform IOS --pretty
asc versions create --app 6755198424 --version "$version" --platform MAC_OS --pretty
asc versions create --app 6755198424 --version "$version" --platform TV_OS --pretty
```

Record the version IDs in a platform map. The version state should be `PREPARE_FOR_SUBMISSION` before metadata/build changes.

## Phase 4: Sync ASC Metadata

For each platform version, update `en-US` localization with local files:

```bash
description=$(cat APP_STORE_DESCRIPTION.txt)
whats_new=$(cat APP_STORE_CHANGELOG.txt)

asc localizations update --version "$ios_version_id" --locale en-US \
  --description "$description" \
  --whats-new "$whats_new" \
  --pretty
```

Repeat for `MAC_OS` and `TV_OS` version IDs.

After update, download or list localizations and compare fields against local files. ASC may trim the final trailing newline; that is acceptable. Preserve unrelated metadata such as keywords, support URL, and marketing URL.

If the user says description must remain unchanged, update only `whatsNew`.

## Phase 5: Attach Builds

Find and validate build IDs:

```bash
asc builds list --app 6755198424 --version "$version" --build-number "$build_number" --processing-state all --pretty
```

Map one build ID per platform. Confirm:

- `processingState` is `VALID`.
- Encryption compliance is resolved, usually `usesNonExemptEncryption=false`.
- The build belongs to the requested release version/build number.

Attach each build:

```bash
asc versions attach-build --version-id "$ios_version_id" --build "$ios_build_id" --pretty
asc versions attach-build --version-id "$macos_version_id" --build "$macos_build_id" --pretty
asc versions attach-build --version-id "$tvos_version_id" --build "$tvos_build_id" --pretty
```

Then verify:

```bash
asc versions get --version-id "$ios_version_id" --include-build --pretty
asc versions get --version-id "$macos_version_id" --include-build --pretty
asc versions get --version-id "$tvos_version_id" --include-build --pretty
```

## Phase 6: Submit For Review

For each platform:

```bash
submission_id=$(asc review submissions-create --app 6755198424 --platform IOS --pretty \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("id") or data["data"]["id"])')

asc review items-add --submission "$submission_id" --item-type appStoreVersions --item-id "$ios_version_id" --pretty
asc review submissions-submit --id "$submission_id" --confirm --pretty
```

Repeat for `MAC_OS` and `TV_OS`.

Final verification:

```bash
asc versions list --app 6755198424 --version "$version" --platform IOS,MAC_OS,TV_OS --pretty
asc versions get --version-id "$ios_version_id" --include-build --pretty
asc versions get --version-id "$macos_version_id" --include-build --pretty
asc versions get --version-id "$tvos_version_id" --include-build --pretty
```

All three versions should be `WAITING_FOR_REVIEW`. Report platform, version ID, build ID, and submission ID.

## Phase 7: Start Next Version Cycle

After the release submissions are verified, start the next development version from clean `main`.

```bash
git status --short --branch
git switch -c "release/bump-${next_version}"
make minor
git status --short --branch
```

`make minor` must own the version mutation. Do not edit `MARKETING_VERSION` or `CURRENT_PROJECT_VERSION` manually.

Verify the generated commit and version delta:

```bash
git log --oneline --decorate -n 3
git diff --stat HEAD~1..HEAD
```

Push, open, and merge the version-cycle PR:

```bash
git push -u origin "release/bump-${next_version}"

cat > /tmp/kmreader-next-version-pr-body.md <<EOF
## Problem
The ${version} App Store release has been submitted, so main should move to the next development version.

## Approach
Run make minor to bump MARKETING_VERSION and CURRENT_PROJECT_VERSION through the repository release script.

## Validation
- [x] Ran make minor
- [x] Verified version file diff
EOF

gh pr create --title "chore: bump version to ${next_version}" --body-file /tmp/kmreader-next-version-pr-body.md
gh pr view <PR_NUMBER> --json url,title,body,headRefName,baseRefName,state,statusCheckRollup

gh pr merge <PR_NUMBER> --squash --delete-branch \
  --subject "chore: bump version to ${next_version}" \
  --body "Bump marketing version to ${next_version} and advance the build number for the next development cycle."

git fetch --prune origin
git switch main
git pull --ff-only origin main
git status --short --branch
```

## Final Report

Report:

- Release-copy PR URL and merge status.
- ASC version IDs by platform.
- Build IDs by platform.
- Review submission IDs by platform.
- Final ASC state by platform.
- Next-version PR URL and merge status.
- Current local branch, `HEAD`, and whether the worktree is clean.
