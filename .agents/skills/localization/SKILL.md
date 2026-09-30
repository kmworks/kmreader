---
name: localization
description: Use when updating KMReader translations in Localizable.xcstrings after code changes. Covers build/localize refresh, missing key discovery, context lookup, and deterministic updates through misc/translate.py.
---

# KMReader Localization

Maintain and complete KMReader translations in `KMReader/Localizable.xcstrings`.

## When To Use

- The user asks to fill missing translations.
- New localized strings were introduced and need all supported languages.
- The user mentions `misc/translate.py`, `make localize`, or missing localization entries.

## Standard Workflow

Hard requirement:

- `make localize` must be preceded by a full `make build` for the current code state.
- Without that build, extracted localized strings data may be stale, and `Localizable.xcstrings` will not be updated correctly.

Default order:

1. Run a full `make build` once to refresh extracted strings data.
2. Sync extracted strings data into `Localizable.xcstrings`.
3. Fill missing translations.

Only skip the build step when it is already confirmed that the current code changes have been through a full `make build`. If that is not explicitly confirmed, run `make build` before `make localize`.

```bash
make build
make localize
```

## Missing Translation Check

```bash
./misc/translate.py list
```

- This lists keys with missing languages.
- If output is `No missing translations found.`, no translation update is needed.

## Per-Key Process

1. Understand key meaning and UI context.
2. Locate usage in code when needed to avoid semantic drift.
3. Prepare all target languages first, then write once.

```bash
rg -n "String\\(localized: \"<KEY>\"\\)|\"<KEY>\"" KMReader Shared KMReaderWidgets
```

Current supported target languages:

- `de`, `en`, `es`, `fr`, `it`, `ja`, `ko`, `ru`, `zh-Hans`, `zh-Hant`

## Deterministic Update Command

Always write all target languages in one command to avoid partial updates.
Run `./misc/translate.py update` commands sequentially.
Do not run multiple `update` commands in parallel against the same `KMReader/Localizable.xcstrings` file, because each invocation rewrites the file and concurrent writes can corrupt the JSON.
Parallelism is only safe for read-only steps such as `rg` or `./misc/translate.py list`.

```bash
./misc/translate.py update "<KEY>" \
  --de "<German>" \
  --en "<English>" \
  --es "<Spanish>" \
  --fr "<French>" \
  --it "<Italian>" \
  --ja "<Japanese>" \
  --ko "<Korean>" \
  --ru "<Russian>" \
  --zh-hans "<Simplified Chinese>" \
  --zh-hant "<Traditional Chinese>"
```

If `Localizable.xcstrings` becomes invalid JSON at any point, restore it to a known-good state first, rerun `make localize`, and then repeat the missing-key updates sequentially.

## Quality Rules

- Preserve placeholders and format markers exactly: `%@`, `%d`, `%lld`, `%f`, `%1$@`, `\\n`.
- Keep tone consistent with product domains (Reader, Series, Read List, Offline Sync).
- Do not modify entries where `shouldTranslate == false`.
- Do not rewrite unrelated keys; only update requested or missing ones.

## Final Verification

```bash
./misc/translate.py list
```

If missing items remain, continue until the list is empty.
