#!/bin/bash

source ../_liferay_common.sh
source ../_test_common.sh
source ./build_premium_support_lts_releases.sh

function main {
	set_up

	test_build_premium_support_lts_releases_process_premium_support_lts_release_branches

	tear_down
}

function set_up {
	common_set_up

	export _RELEASE_ROOT_DIR="${PWD}"

	export LIFERAY_RELEASE_TEST_DATE="2025-06-01"
}

function tear_down {
	common_tear_down

	unset LIFERAY_RELEASE_TEST_DATE
	unset _RELEASE_ROOT_DIR
}

function test_build_premium_support_lts_releases_process_premium_support_lts_release_branches {
	_test_build_premium_support_lts_releases_process_premium_support_lts_release_branches \
		"$(echo -e 'release-2023.q1\nrelease-2024.q1\nrelease-2025.q1')"

	LIFERAY_RELEASE_TEST_DATE="2026-06-01"

	sed --in-place "s/2025.q2.8/2026.q1.9/g" "test-dependencies/actual/dxp.html"
	sed --in-place "s/2025.q2.8/2026.q1.9/g" "test-dependencies/actual/release-candidates.html"

	_test_build_premium_support_lts_releases_process_premium_support_lts_release_branches \
		"$(echo -e 'release-2024.q1\nrelease-2025.q1')"

	sed --in-place "s/2026.q1.9/2025.q2.8/g" "test-dependencies/actual/dxp.html"
	sed --in-place "s/2026.q1.9/2025.q2.9/g" "test-dependencies/actual/release-candidates.html"

	_test_build_premium_support_lts_releases_process_premium_support_lts_release_branches \
		"$(echo -e 'release-2024.q1\nrelease-2025.q1\nrelease-2026.q1')"

	sed --in-place "s/2025.q2.9/2025.q2.8/g" "test-dependencies/actual/release-candidates.html"
}

function _test_build_premium_support_lts_releases_process_premium_support_lts_release_branches {
	local triggered_branches=$(process_premium_support_lts_release_branches 2>/dev/null | grep "^release-")

	assert_equals \
		"${triggered_branches}" "${1}"
}

main "${@}"
