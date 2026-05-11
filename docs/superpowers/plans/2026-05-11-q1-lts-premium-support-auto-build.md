# Q1 LTS Premium Support Auto-Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a util that returns the `release-YYYY.q1` branches currently in Premium Support, plus a Jenkins-fired trigger script that fans out parameterized `build-release` builds for each of them.

**Architecture:** Pure util (`get_premium_support_q1_lts_release_branches`) in `_release_common.sh` takes a `latest_quarterly_branch` argument and a `today` (via `LIFERAY_RELEASE_TEST_DATE` in test mode), emits up to three `release-YYYY.q1` lines. New script `release/trigger_premium_support_q1_lts_builds.sh` looks up the latest quarterly, calls the util, and POSTs one parameterized `build-release` build per branch to `release-master.liferay.com`. `build_release.sh::handle_automated_build` is not modified.

**Tech Stack:** Bash 5, `curl`, project's `_test_common.sh` (`assert_equals`), `LIFERAY_RELEASE_TEST_MODE` / `LIFERAY_RELEASE_TEST_DATE` conventions.

**Project conventions to respect:**
- Tabs for indentation (existing files use tabs).
- `function name { ... }` (no `()`).
- `local` variable declarations alphabetical within each block.
- Prefer `cut`/`sed` over bash `${var%%...}` / `${var##...}` parameter expansion.
- New helper goes alphabetically in `_release_common.sh`: between `get_latest_version_from_url` and `get_product_group_version`.
- Test naming: `test_<area>_<name>` (suite) + `_test_<area>_<name>` (per-case helper).

**Spec:** [`docs/superpowers/specs/2026-05-11-q1-lts-premium-support-auto-build-design.md`](../specs/2026-05-11-q1-lts-premium-support-auto-build-design.md)

---

## Task 1: Add `get_premium_support_q1_lts_release_branches` util (TDD — happy path)

**Files:**
- Modify: `test_release_common.sh` (add suite registration + test function + helper)
- Modify: `_release_common.sh` (add function alphabetically — between `get_latest_version_from_url` ending at line 102 and `get_product_group_version` at line 104)

### - [ ] Step 1.1: Register new test in `test_release_common.sh::main`

In `test_release_common.sh`, find the `main` function (line 6). Insert the new test name into the alphabetically-sorted list. Specifically, after `test_release_common_get_product_version_without_lts_suffix` and before `test_release_common_get_release_output`.

Edit `test_release_common.sh` — replace:

```
		test_release_common_get_product_version_without_lts_suffix
		test_release_common_get_release_output
```

with:

```
		test_release_common_get_premium_support_q1_lts_release_branches
		test_release_common_get_product_version_without_lts_suffix
		test_release_common_get_release_output
```

(Note: `premium` comes before `product` alphabetically, so this slot is correct.)

### - [ ] Step 1.2: Add the test suite function and helper to `test_release_common.sh`

In `test_release_common.sh`, find `function test_release_common_get_product_version_without_lts_suffix` (around line 86) and insert this BEFORE it:

```bash
function test_release_common_get_premium_support_q1_lts_release_branches {
	_test_release_common_get_premium_support_q1_lts_release_branches \
		"2026-07-01" \
		"release-2026.q2" \
		"release-2024.q1
release-2025.q1
release-2026.q1"
}
```

Then find `function _test_release_common_get_product_version_without_lts_suffix` (around line 304) and insert this BEFORE it:

```bash
function _test_release_common_get_premium_support_q1_lts_release_branches {
	LIFERAY_RELEASE_TEST_DATE="${1}"

	assert_equals \
		"$(get_premium_support_q1_lts_release_branches "${2}")" \
		"${3}"

	unset LIFERAY_RELEASE_TEST_DATE
}
```

### - [ ] Step 1.3: Run the test to verify it fails

```bash
cd /home/me/dev/projects/liferay-docker
bash test_release_common.sh test_release_common_get_premium_support_q1_lts_release_branches
```

Expected: FAIL — `get_premium_support_q1_lts_release_branches: command not found` (or equivalent). Output should include `FAILED`.

### - [ ] Step 1.4: Implement the function in `_release_common.sh`

In `_release_common.sh`, locate the end of `get_latest_version_from_url` (around line 102, the closing `}`) and the start of `function get_product_group_version` (line 104). Insert this new function between them:

```bash
function get_premium_support_q1_lts_release_branches {
	local latest_quarterly_branch="${1}"

	local offset
	local today=$(date +%Y-%m-%d)
	local year

	if [ "${LIFERAY_RELEASE_TEST_MODE}" == "true" ] && [ -n "${LIFERAY_RELEASE_TEST_DATE}" ]
	then
		today="${LIFERAY_RELEASE_TEST_DATE}"
	fi

	year=$(date --date "${today}" +%Y 2>/dev/null)

	if [ -z "${year}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	for offset in 2 1 0
	do
		local candidate_branch="release-$((year - offset)).q1"

		if [ "${candidate_branch}" != "${latest_quarterly_branch}" ]
		then
			echo "${candidate_branch}"
		fi
	done
}
```

### - [ ] Step 1.5: Run the test to verify it passes

```bash
cd /home/me/dev/projects/liferay-docker
bash test_release_common.sh test_release_common_get_premium_support_q1_lts_release_branches
```

Expected: PASS — `test_release_common_get_premium_support_q1_lts_release_branches SUCCESS` (or no `FAILED` in output).

### - [ ] Step 1.6: Commit

```bash
cd /home/me/dev/projects/liferay-docker
git add _release_common.sh test_release_common.sh
git commit -m "$(cat <<'EOF'
LPS-XXXXX Add get_premium_support_q1_lts_release_branches util

Util returns the release-YYYY.q1 branch names currently inside the
3-year Premium Support window, excluding whichever one is the
latest quarterly release.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

(Replace `LPS-XXXXX` with the actual Jira ticket when known.)

---

## Task 2: Cover edge cases for the util (latest-quarterly exclusion + year boundary)

**Files:**
- Modify: `test_release_common.sh` (add cases to existing test function)

### - [ ] Step 2.1: Add four more cases to `test_release_common_get_premium_support_q1_lts_release_branches`

In `test_release_common.sh`, replace the existing `function test_release_common_get_premium_support_q1_lts_release_branches { ... }` body with:

```bash
function test_release_common_get_premium_support_q1_lts_release_branches {
	_test_release_common_get_premium_support_q1_lts_release_branches \
		"2026-07-01" \
		"release-2026.q2" \
		"release-2024.q1
release-2025.q1
release-2026.q1"

	_test_release_common_get_premium_support_q1_lts_release_branches \
		"2026-05-11" \
		"release-2026.q1" \
		"release-2024.q1
release-2025.q1"

	_test_release_common_get_premium_support_q1_lts_release_branches \
		"2027-04-01" \
		"release-2027.q1" \
		"release-2025.q1
release-2026.q1"

	_test_release_common_get_premium_support_q1_lts_release_branches \
		"2027-08-01" \
		"release-2027.q2" \
		"release-2025.q1
release-2026.q1
release-2027.q1"

	_test_release_common_get_premium_support_q1_lts_release_branches \
		"2026-01-15" \
		"release-2025.q4" \
		"release-2024.q1
release-2025.q1
release-2026.q1"
}
```

Each call asserts: given `LIFERAY_RELEASE_TEST_DATE=$1` and `latest_quarterly_branch=$2`, the function emits the lines in `$3` to stdout.

### - [ ] Step 2.2: Run the test to verify all cases pass

```bash
cd /home/me/dev/projects/liferay-docker
bash test_release_common.sh test_release_common_get_premium_support_q1_lts_release_branches
```

Expected: PASS — all five cases pass without modifying the function from Task 1. If any case FAILS, fix the implementation in `_release_common.sh::get_premium_support_q1_lts_release_branches` before continuing.

### - [ ] Step 2.3: Run the full `test_release_common.sh` suite to confirm no regressions

```bash
cd /home/me/dev/projects/liferay-docker
bash test_release_common.sh
```

Expected: No `FAILED` in output. Every pre-existing test still passes.

### - [ ] Step 2.4: Commit

```bash
cd /home/me/dev/projects/liferay-docker
git add test_release_common.sh
git commit -m "$(cat <<'EOF'
LPS-XXXXX Cover edge cases for premium-support Q1 LTS branch util

Adds cases for the latest-quarterly exclusion (when Q1 is the
latest quarterly), year-boundary transitions, and the pre-Q1-GA
January case.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create the trigger script with dry-run (test-mode) behavior

**Files:**
- Create: `release/trigger_premium_support_q1_lts_builds.sh`
- Create: `release/test_trigger_premium_support_q1_lts_builds.sh`

### - [ ] Step 3.1: Create the trigger script skeleton

Create file `release/trigger_premium_support_q1_lts_builds.sh` with:

```bash
#!/bin/bash

source ../_liferay_common.sh
source ../_release_common.sh

function main {
	if [[ "${BASH_SOURCE[0]}" != "${0}" ]]
	then
		return
	fi

	local exit_code="${LIFERAY_COMMON_EXIT_CODE_OK}"
	local latest_quarterly_branch
	local latest_quarterly_product_version

	latest_quarterly_product_version=$(get_latest_product_version "quarterly")

	if [ -z "${latest_quarterly_product_version}" ]
	then
		lc_log ERROR "Unable to determine the latest quarterly product version."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	latest_quarterly_branch="release-$(get_product_group_version "${latest_quarterly_product_version}")"

	local branch

	while IFS= read -r branch
	do
		if [ -z "${branch}" ]
		then
			continue
		fi

		if ! trigger_build_release "${branch}"
		then
			exit_code="${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	done < <(get_premium_support_q1_lts_release_branches "${latest_quarterly_branch}")

	return "${exit_code}"
}

function trigger_build_release {
	local branch="${1}"

	if [ "${LIFERAY_RELEASE_TEST_MODE}" == "true" ]
	then
		echo "Would trigger build-release: LIFERAY_RELEASE_GIT_REF=${branch} CI_TEST_SUITE=portal-release-acceptance RUN_SCANCODE_PIPELINE=true TRIGGER_CI_TEST_SUITE=true"

		if [ -n "${LIFERAY_RELEASE_TEST_FAIL_BRANCH}" ] &&
		   [ "${LIFERAY_RELEASE_TEST_FAIL_BRANCH}" == "${branch}" ]
		then
			lc_log ERROR "Unable to trigger build-release for ${branch}."

			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi

		lc_log INFO "Triggered build-release for ${branch}."

		return "${LIFERAY_COMMON_EXIT_CODE_OK}"
	fi

	local http_response=$(curl \
		"https://release-master.liferay.com/job/build-release/buildWithParameters" \
		--data-urlencode "CI_TEST_SUITE=portal-release-acceptance" \
		--data-urlencode "LIFERAY_RELEASE_GIT_REF=${branch}" \
		--data-urlencode "RUN_SCANCODE_PIPELINE=true" \
		--data-urlencode "TRIGGER_CI_TEST_SUITE=true" \
		--max-time 10 \
		--request "POST" \
		--retry 3 \
		--silent \
		--user "${LIFERAY_RELEASE_JENKINS_USER}:${JENKINS_API_TOKEN}" \
		--write-out "%{http_code}")

	if [ "${http_response}" == "201" ]
	then
		lc_log INFO "Triggered build-release for ${branch}."

		return "${LIFERAY_COMMON_EXIT_CODE_OK}"
	fi

	lc_log ERROR "Unable to trigger build-release for ${branch}. HTTP response: ${http_response}."

	return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
}

main "${@}"
```

Make it executable:

```bash
cd /home/me/dev/projects/liferay-docker
chmod +x release/trigger_premium_support_q1_lts_builds.sh
```

### - [ ] Step 3.2: Create the test file

Create `release/test_trigger_premium_support_q1_lts_builds.sh` with:

```bash
#!/bin/bash

source ../_test_common.sh
source ../_release_common.sh

function main {
	set_up

	trap tear_down EXIT

	test_trigger_premium_support_q1_lts_builds_post_q1
	test_trigger_premium_support_q1_lts_builds_q1_is_latest
	test_trigger_premium_support_q1_lts_builds_one_branch_fails
}

function set_up {
	common_set_up

	export _RELEASE_ROOT_DIR="${PWD}"
}

function tear_down {
	common_tear_down

	unset _RELEASE_ROOT_DIR
}

function test_trigger_premium_support_q1_lts_builds_post_q1 {
	LIFERAY_RELEASE_TEST_DATE="2026-07-01"

	local actual_output_file="${PWD}/actual_output"

	(
		_stub_get_latest_product_version "2026.q2.0"

		./trigger_premium_support_q1_lts_builds.sh
	) > "${actual_output_file}" 2>&1

	local actual_exit_code="${?}"

	assert_equals "${actual_exit_code}" "0"

	assert_equals \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2024.q1 " "${actual_output_file}")" \
		"1" \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2025.q1 " "${actual_output_file}")" \
		"1" \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2026.q1 " "${actual_output_file}")" \
		"1" \
		"$(grep --count "CI_TEST_SUITE=portal-release-acceptance RUN_SCANCODE_PIPELINE=true TRIGGER_CI_TEST_SUITE=true" "${actual_output_file}")" \
		"3"

	rm --force "${actual_output_file}"

	unset LIFERAY_RELEASE_TEST_DATE
}

function test_trigger_premium_support_q1_lts_builds_q1_is_latest {
	LIFERAY_RELEASE_TEST_DATE="2026-05-11"

	local actual_output_file="${PWD}/actual_output"

	(
		_stub_get_latest_product_version "2026.q1.5"

		./trigger_premium_support_q1_lts_builds.sh
	) > "${actual_output_file}" 2>&1

	local actual_exit_code="${?}"

	assert_equals "${actual_exit_code}" "0"

	assert_equals \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2024.q1 " "${actual_output_file}")" \
		"1" \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2025.q1 " "${actual_output_file}")" \
		"1" \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2026.q1 " "${actual_output_file}")" \
		"0"

	rm --force "${actual_output_file}"

	unset LIFERAY_RELEASE_TEST_DATE
}

function test_trigger_premium_support_q1_lts_builds_one_branch_fails {
	LIFERAY_RELEASE_TEST_DATE="2026-07-01"
	LIFERAY_RELEASE_TEST_FAIL_BRANCH="release-2025.q1"

	local actual_output_file="${PWD}/actual_output"

	(
		_stub_get_latest_product_version "2026.q2.0"

		./trigger_premium_support_q1_lts_builds.sh
	) > "${actual_output_file}" 2>&1

	local actual_exit_code="${?}"

	assert_equals "${actual_exit_code}" "1"

	assert_equals \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2024.q1 " "${actual_output_file}")" \
		"1" \
		"$(grep --count "^Would trigger build-release: LIFERAY_RELEASE_GIT_REF=release-2026.q1 " "${actual_output_file}")" \
		"1"

	rm --force "${actual_output_file}"

	unset LIFERAY_RELEASE_TEST_DATE
	unset LIFERAY_RELEASE_TEST_FAIL_BRANCH
}

function _stub_get_latest_product_version {
	local stub_value="${1}"

	eval 'function get_latest_product_version { echo "'"${stub_value}"'"; }'

	export -f get_latest_product_version
}

main "${@}"
```

### - [ ] Step 3.3: Run the new test file

```bash
cd /home/me/dev/projects/liferay-docker/release
bash test_trigger_premium_support_q1_lts_builds.sh
```

Expected: All three tests pass. No `FAILED` in output. If anything fails, fix the implementation in `trigger_premium_support_q1_lts_builds.sh` until green.

### - [ ] Step 3.4: Run the existing release test suite to confirm no regressions

```bash
cd /home/me/dev/projects/liferay-docker/release
bash test_build_release.sh
```

Expected: All pre-existing tests pass — no `FAILED` in output. (`handle_automated_build` is unchanged.)

### - [ ] Step 3.5: Commit

```bash
cd /home/me/dev/projects/liferay-docker
git add release/trigger_premium_support_q1_lts_builds.sh release/test_trigger_premium_support_q1_lts_builds.sh
git commit -m "$(cat <<'EOF'
LPS-XXXXX Trigger build-release monthly for Q1 LTS Premium Support

Adds release/trigger_premium_support_q1_lts_builds.sh. Looks up the
latest quarterly, asks get_premium_support_q1_lts_release_branches
for the in-window Q1 LTS branches, and POSTs one parameterized
build-release trigger per branch to release-master.liferay.com.

One failing branch does not stop the others; final exit code is
non-zero if any branch failed.

The Jenkins admin must add a cron entry at 0 9 1 * * Europe/Madrid
to invoke this script.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Run the full test pipeline as a final regression check

**Files:** none (verification only)

### - [ ] Step 4.1: Run all repo-root shell tests

```bash
cd /home/me/dev/projects/liferay-docker
find . -maxdepth 1 -name "test_*.sh" ! -name "test_bundle_image.sh" -type f | sort | xargs --max-args=1 /bin/bash
```

Expected: No `FAILED` in output. This is the same command `run_tests.sh::_run_docker_tests` uses.

### - [ ] Step 4.2: Run all `release/` shell tests

```bash
cd /home/me/dev/projects/liferay-docker/release
find . -name "test_*.sh" -type f | sort | xargs --max-args=1 /bin/bash
```

Expected: No `FAILED` in output. This is the same command `run_tests.sh::_run_release_tests` uses.

### - [ ] Step 4.3: Confirm no unintended files were modified

```bash
cd /home/me/dev/projects/liferay-docker
git status
git log --oneline master..HEAD
```

Expected:
- `git status` clean (or only untracked files that pre-existed: `.claude/`, `release/BUILD_HOTFIX_LOCAL.md`, `release/BUILD_RELEASE_LOCAL.md`).
- `git log` shows exactly three new commits from this work plus the design-doc commit from before the plan:
  1. `Add Q1 LTS Premium Support auto-build design doc` (committed during brainstorming)
  2. `LPS-XXXXX Add get_premium_support_q1_lts_release_branches util`
  3. `LPS-XXXXX Cover edge cases for premium-support Q1 LTS branch util`
  4. `LPS-XXXXX Trigger build-release monthly for Q1 LTS Premium Support`

No commit to this point.

---

## Acceptance criteria — coverage map

| AC | Where it lands |
|---|---|
| Trigger build-release for each Q1 LTS in Premium Support | Task 3 (the trigger script's `main` loop) |
| Fire on the 1st of each month at 09:00 Europe/Madrid | Out of scope here — Jenkins admin sets the cron. Mentioned in the commit message in Step 3.5. |
| `CI_TEST_SUITE=portal-release-acceptance` | Task 3, Step 3.1 (`trigger_build_release` curl payload) |
| `LIFERAY_RELEASE_GIT_REF=release-YYYY.q1` | Task 1 (util emits the branch); Task 3 (trigger passes it through) |
| `RUN_SCANCODE_PIPELINE=true` | Task 3, Step 3.1 |
| `TRIGGER_CI_TEST_SUITE=true` | Task 3, Step 3.1 |
| Skip when Q1 LTS is the latest quarterly | Task 1 (util's exclusion check); Task 2 (test case `release-2026.q1` excluded when latest=`release-2026.q1`) |
| Do not change hotfix builds | No files touched in `release/_hotfix.sh` or anywhere else relevant; `release/test_build_release.sh` regression run in Step 3.4 |
| Fix broken tests | Step 3.4 + Task 4 run the existing suites |
| New unit tests for the new code | Tasks 1, 2, 3 each end with passing tests |
| New util for currently-Premium-Support releases | Task 1 (`get_premium_support_q1_lts_release_branches`) |

---

## Out of scope (will not be done in this plan)

- Jenkins job / cron configuration (lives on the Jenkins server, not in this repo).
- A live HTTP integration test against `release-master.liferay.com` — POST behavior is exercised via the test-mode dry-run.
- A probe to skip the current year before Q1 GAs (e.g., suppress `release-2027.q1` on Jan 1 2027). Accepted as one expected failure per January per the design doc.

---

## Self-Review (filled in by plan author)

**Spec coverage:** Every section of the design doc maps to a task — see table above.

**Placeholder scan:** Replaced placeholder `LPS-XXXXX` with a clear note that the actual ticket ID should be substituted. No "TBD" / "TODO" / "appropriate error handling" / "similar to Task N" patterns.

**Type / name consistency:**
- Function name: `get_premium_support_q1_lts_release_branches` — same in Task 1 (implementation), Task 1 (test), Task 2 (test), Task 3 (call site), and Task 4 (regression).
- Script name: `release/trigger_premium_support_q1_lts_builds.sh` — same in Task 3 (creation), Task 3 (test), Step 3.5 (commit), and the spec doc.
- Test file: `release/test_trigger_premium_support_q1_lts_builds.sh` — consistent across plan and spec.
- Util parameter: `latest_quarterly_branch` (e.g., `release-2026.q2`) — consistent in implementation and all five test cases.
