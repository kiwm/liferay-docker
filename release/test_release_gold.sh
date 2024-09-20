#!/bin/bash

source ../_test_common.sh
source release_gold.sh --test
source _github.sh

function main {
	set_up

	test_invoke_github_api_post
	test_update_release_info_date

	tear_down
}

function set_up {
	export LIFERAY_COMMON_EXIT_CODE_OK=0
	export LIFERAY_COMMON_EXIT_CODE_SKIPPED=4
	export LIFERAY_RELEASE_REPOSITORY_OWNER="natocesarrego"
	export LIFERAY_RELEASE_VERSION="test-tag"
}

function tear_down {
	invoke_github_api_delete "liferay-portal-ee/git/refs/tags/${LIFERAY_RELEASE_VERSION}"

	unset LIFERAY_COMMON_EXIT_CODE_OK
	unset LIFERAY_COMMON_EXIT_CODE_SKIPPED
	unset LIFERAY_RELEASE_REPOSITORY_OWNER
	unset LIFERAY_RELEASE_VERSION
}

function test_invoke_github_api_post {
	local ref_data=$(
		cat <<- END
		{
			"message": "",
			"ref": "refs/tags/${LIFERAY_RELEASE_VERSION}",
			"sha": "d4e20d5ccbd8dd3ca5d9a9e03f80e293256b5560"
		}
		END
	)

	local tag_data=$(
		cat <<- END
		{
			"message": "",
			"object": "d4e20d5ccbd8dd3ca5d9a9e03f80e293256b5560",
			"tag": "${LIFERAY_RELEASE_VERSION}",
			"type": "commit"
		}
		END
	)

	assert_equals $(invoke_github_api_post "liferay-portal-ee/git/tags" "${tag_data}") "${LIFERAY_COMMON_EXIT_CODE_OK}" $(invoke_github_api_post "liferay-portal-ee/git/refs" "${ref_data}") "${LIFERAY_COMMON_EXIT_CODE_OK}"
}

function test_update_release_info_date {
	_test_update_release_info_date "2024.q2.11" "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	_test_update_release_info_date "2024.q2.12" "${LIFERAY_COMMON_EXIT_CODE_OK}"
	_test_update_release_info_date "2024.q3.0" "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	_test_update_release_info_date "7.3.10-u36" "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	_test_update_release_info_date "7.4.13-u101" "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	_test_update_release_info_date "7.4.3.125-ga125" "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
}

function _test_update_release_info_date {
	_PRODUCT_VERSION="${1}"

	echo -e "Running _test_update_release_info_date for ${_PRODUCT_VERSION}\n"

	update_release_info_date --test >/dev/null

	assert_equals "${?}" "${2}"
}

main