---
name: testflight
description: Distribute KMReader builds to TestFlight groups via the asc CLI. Use when asked to add a build to TestFlight groups, check which groups a build is in, or submit a build for Beta App Review.
---

# TestFlight

Distribute uploaded KMReader builds to TestFlight groups with the `asc` CLI.

## Groups

KMReader App Store app ID is `6755198424`. List groups to get current names and IDs:

```bash
asc testflight groups list --app 6755198424 --pretty
```

- Internal groups receive new builds automatically; no action needed.
- External groups require a Beta App Review submission per build before testers see it.

## Add A Build To Groups

```bash
asc builds add-groups --build-id "$build_id" \
  --group "$group_id_1,$group_id_2" \
  --submit --confirm --pretty
```

- `--group` takes comma-separated group IDs or names; one call can cover multiple groups.
- `--submit --confirm` submits the build for Beta App Review, which external groups require before testers see the build. Omit it only for internal-only distribution.
- Build selection alternatives to `--build-id`: `--app 6755198424 --latest`, or `--app 6755198424 --build-number 607 --platform IOS`.
- Each platform has its own build ID; repeat per platform (iOS/macOS/tvOS).
- The command stops without sending the request when ASC state (processing, expiry, encryption, beta review) does not prove readiness — read the error, fix the state, retry.

## Verify

```bash
asc builds groups list --build-id "$build_id" --pretty
```

External testers see the build only after Beta App Review approves it (usually within hours).
