# Q1 LTS Premium Support Auto-Build — Design

**Date:** 2026-05-11
**Status:** Draft — awaiting review

## Context

The Release Quality Engineers want the `build-release` Jenkins job to fire automatically for every Q1 LTS release currently under active Premium Support, similar to the existing Monday-morning cron for the latest quarterly release introduced in LPD-61372.

Premium Support for a Q1 LTS release lasts 3 years from its general availability date. With the rolling 3-year window plus the typical February GA cadence for Q1, the in-support set at any time is at most three branches. For example, after `2026.q2` ships, the Q1 LTS releases in Premium Support are `2024.q1`, `2025.q1`, and `2026.q1`.

The build for the *latest* quarterly release is already automated; this design adds a second, independent automation for the older Q1 LTS branches.

## Goals

- Automatically trigger `build-release` for each Q1 LTS release currently in Premium Support, on the 1st of each month at 09:00 Europe/Madrid.
- Fill exactly these job parameters per trigger:
  - `CI_TEST_SUITE=portal-release-acceptance`
  - `LIFERAY_RELEASE_GIT_REF=release-YYYY.q1`
  - `RUN_SCANCODE_PIPELINE=true`
  - `TRIGGER_CI_TEST_SUITE=true`
- Skip any Q1 LTS branch that happens to be the *latest* quarterly release at the time of trigger (already covered by the existing Monday cron).
- Provide a reusable utility function in `_release_common.sh` for "Q1 LTS releases currently in Premium Support."
- Preserve all existing behavior for hotfix builds and the latest-quarterly automated build.

## Non-goals

- No Jenkinsfile / Jenkins pipeline definition lives in this repo; cron schedule placement is handled by Jenkins admins.
- No changes to hotfix building.
- No changes to `release/build_release.sh::handle_automated_build`.
- No probing of remote branch existence before triggering (pre-GA edge case is accepted; see Edge Cases).

## Architecture

Two units, both in this repo. Nothing else needs to change.

### Unit 1 — `get_premium_support_q1_lts_release_branches` in `_release_common.sh`

**Purpose:** Return the set of `release-YYYY.q1` branch names that should be auto-built this month.

**Inputs:** none (reads `date +%Y`, with `LIFERAY_RELEASE_TEST_DATE` honored when `LIFERAY_RELEASE_TEST_MODE=true`, matching the convention used in `release/_releases_json.sh::_is_supported_product_version`).

**Output:** zero or more newline-separated branch names, ordered oldest-to-newest, written to stdout. Exit code `${LIFERAY_COMMON_EXIT_CODE_OK}` on success, `${LIFERAY_COMMON_EXIT_CODE_BAD}` if date math fails.

**Algorithm:**

```
today = LIFERAY_RELEASE_TEST_DATE (if set) else `date +%Y-%m-%d`
year  = `date --date "${today}" +%Y`

latest_quarterly_version = get_latest_product_version "quarterly"
latest_quarterly_branch  = "release-$(get_product_group_version "${latest_quarterly_version}")"

for offset in 2 1 0:
    candidate = "release-$((year - offset)).q1"
    if candidate != latest_quarterly_branch:
        echo candidate
```

**Why "current year" and not exact GA-date arithmetic:** Q1 GAs in February each year and Premium Support lasts 3 years to the day, so the in-support set transitions on a specific February date each year. The new cron runs monthly on the 1st; pinning the window to calendar year is correct except for the January-before-Q1-GA case (see Edge Cases). The existing `release/_releases_json.sh::_is_supported_product_version` is precise to the day because it's used to tag a published JSON; this trigger does not need that precision and stays inside `_release_common.sh` without pulling release-pipeline-only helpers.

### Unit 2 — `release/trigger_premium_support_q1_lts_builds.sh`

**Purpose:** When invoked by Jenkins on the 1st of each month, fan out one parameterized `build-release` trigger per branch returned by Unit 1.

**Inputs:** environment variables `LIFERAY_RELEASE_JENKINS_USER`, `JENKINS_API_TOKEN`. Optional `LIFERAY_RELEASE_TEST_MODE` for dry-run.

**Output:** log lines per branch (`INFO Triggered build-release for release-YYYY.q1` or `ERROR Unable to trigger ...`).

**Exit code:** `OK` if every branch was triggered successfully; `BAD` if any branch failed. The script does **not** short-circuit on a failure — every branch gets attempted.

**Algorithm:**

```
sources: ../_liferay_common.sh, ../_release_common.sh

branches = get_premium_support_q1_lts_release_branches
exit_code = OK

for each branch:
    if LIFERAY_RELEASE_TEST_MODE=true:
        print "Would POST: branch=${branch} CI_TEST_SUITE=... RUN_SCANCODE_PIPELINE=... TRIGGER_CI_TEST_SUITE=..."
    else:
        http_response = curl POST https://release-master.liferay.com/job/build-release/buildWithParameters
            --data-urlencode CI_TEST_SUITE=portal-release-acceptance
            --data-urlencode LIFERAY_RELEASE_GIT_REF=${branch}
            --data-urlencode RUN_SCANCODE_PIPELINE=true
            --data-urlencode TRIGGER_CI_TEST_SUITE=true
            --user "${LIFERAY_RELEASE_JENKINS_USER}:${JENKINS_API_TOKEN}"
            --max-time 10
            --retry 3
            --fail
            --silent
            --request POST
            --write-out "%{http_code}"

        if http_response == 201:
            log INFO "Triggered build-release for ${branch}."
        else:
            log ERROR "Unable to trigger build-release for ${branch}."
            exit_code = BAD

exit exit_code
```

The POST shape mirrors `release/_ci.sh::trigger_ci_test_suite` (curl flags, retry, max-time, auth) so the codebase stays consistent.

## Data Flow

```
Jenkins cron (Madrid 09:00 on day 1)
        │
        ▼
trigger_premium_support_q1_lts_builds.sh
        │
        ├─► get_premium_support_q1_lts_release_branches
        │         │
        │         ├─► date +%Y  (or LIFERAY_RELEASE_TEST_DATE)
        │         └─► get_latest_product_version "quarterly"
        │                 └─► releases.liferay.com/dxp/   (HTML scrape)
        │
        ▼ (per branch)
POST release-master.liferay.com/job/build-release/buildWithParameters
        │
        ▼
build-release Jenkins job runs normally (existing behavior, unchanged)
```

## Testing

### Unit tests for `get_premium_support_q1_lts_release_branches`

Added to `test_release_common.sh`. Each case sets `LIFERAY_RELEASE_TEST_MODE=true` and `LIFERAY_RELEASE_TEST_DATE`, mocks `get_latest_product_version` (stub the HTML response via `LIFERAY_RELEASE_TEST_MODE` and `test-dependencies/`, mirroring the pattern at `_release_common.sh::download_product_version_list_html`), and asserts stdout.

| Today | Latest quarterly | Expected stdout (one per line) |
|---|---|---|
| 2026-05-11 | `2026.q1.5` | `release-2024.q1`, `release-2025.q1` |
| 2026-07-01 | `2026.q2.0` | `release-2024.q1`, `release-2025.q1`, `release-2026.q1` |
| 2027-04-01 | `2027.q1.2` | `release-2025.q1`, `release-2026.q1` |
| 2027-08-01 | `2027.q2.0` | `release-2025.q1`, `release-2026.q1`, `release-2027.q1` |
| 2026-01-15 | `2025.q4.7` | `release-2024.q1`, `release-2025.q1`, `release-2026.q1` |

### Unit tests for `trigger_premium_support_q1_lts_builds.sh`

New file `release/test_trigger_premium_support_q1_lts_builds.sh` (matching the project naming pattern `test_<script>.sh`). Uses `LIFERAY_RELEASE_TEST_MODE=true` so the script prints planned POSTs instead of hitting Jenkins.

**Cases:**

1. Date `2026-05-11`, latest quarterly `2026.q1.5` → script prints exactly 2 dry-run POSTs for `release-2024.q1` and `release-2025.q1` with the 4 expected form parameters. Exit code `OK`.
2. Date `2026-07-01`, latest quarterly `2026.q2.0` → script prints exactly 3 dry-run POSTs. Exit code `OK`.
3. Simulated failure on one branch (set via a test-mode env var like `LIFERAY_RELEASE_TEST_FAIL_BRANCH=release-2025.q1`) → script still prints planned POSTs for the other branches, exit code `BAD`.

### Existing tests preserved

`release/test_build_release.sh` (`test_build_release_handle_automated_build`, `test_build_release_not_handle_automated_build`) must continue to pass without modification — `handle_automated_build` is not changed.

## Edge Cases

| Case | Behavior |
|---|---|
| Latest quarterly is a Q1 (between Q1 GA and Q2 GA) | That year's `release-YYYY.q1` is excluded; only 2 branches triggered that month. |
| Latest quarterly is `7.4.x` legacy | `get_latest_product_version "quarterly"` regex only matches `YYYY.qN` versions, so the exclusion check never accidentally matches a 7.4 branch. |
| January, before Q1 of `current_year` has GA'd (e.g., `2027-01-01`, no `release-2027.q1` branch yet) | Util still emits `release-2027.q1`; the resulting POST succeeds but the build-release job fails when it cannot resolve the branch. Acceptable for this story — one expected failure per January. |
| `date --date` failure (malformed `LIFERAY_RELEASE_TEST_DATE`) | Util logs error and returns `LIFERAY_COMMON_EXIT_CODE_BAD`. |
| One Jenkins POST fails (transient network error, 5xx) | Retried 3 times by curl. If still failing, error logged for that branch, script continues to the next branch, final exit code is `BAD`. |

## Out of Scope

- **Jenkins job configuration.** A Jenkins admin must add a new job (or new cron trigger on an existing job) at `0 9 1 * * Europe/Madrid` that runs `trigger_premium_support_q1_lts_builds.sh`. This is not committed to this repo.
- **Pre-flight branch existence check.** Not added — see edge case above.
- **Hotfix build automation.** Not changed.
- **Refactor of `handle_automated_build`.** The existing latest-quarterly Monday cron logic is untouched.

## Files

**Modified:**
- `_release_common.sh` — add `get_premium_support_q1_lts_release_branches`.
- `test_release_common.sh` — add `test_release_common_get_premium_support_q1_lts_release_branches` and register it.

**New:**
- `release/trigger_premium_support_q1_lts_builds.sh`
- `release/test_trigger_premium_support_q1_lts_builds.sh`

**Untouched:**
- `release/build_release.sh`
- `release/_ci.sh`
- `release/_hotfix.sh`
- `bundles.yml`
