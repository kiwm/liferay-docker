#!/bin/bash

source ../_test_common.sh
source _git.sh
source _liferay_common.sh

function main {
	set_up

	if [ $? -eq "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	test_generate_release_notes

	tear_down
}

function set_up {
	export LIFERAY_RELEASE_PRODUCT_NAME="dxp"
	export _PRODUCT_VERSION="2024.q2.0"

	export _RELEASE_ROOT_DIR="${PWD}"

	export _PROJECTS_DIR="${_RELEASE_ROOT_DIR}"/../..

	if [ ! -d "${_PROJECTS_DIR}/liferay-portal-ee" ]
	then
		echo "The directory ${_PROJECTS_DIR}/liferay-portal-ee does not exist."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	export _BUILD_DIR="${_PROJECTS_DIR}/liferay-portal-ee"

	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	git checkout master &> /dev/null

	git fetch upstream --no-tags &> /dev/null

	git merge upstream/master &> /dev/null

	mkdir -p "${_PROJECTS_DIR}/liferay-portal-ee/release"
}

function tear_down {
	unset LIFERAY_RELEASE_PRODUCT_NAME
	unset _BUILD_DIR
	unset _PRODUCT_VERSION
	unset _RELEASE_ROOT_DIR

	rm -r "${_PROJECTS_DIR}/liferay-portal-ee/release"

	unset _PROJECTS_DIR
}

function test_generate_release_notes {
	generate_release_notes

	assert_equals \
		$(grep -q "\-," release/release-notes.txt; echo "${?}") \
		"${LIFERAY_COMMON_EXIT_CODE_BAD}" \
		$(grep -q "LPD-27038" release/release-notes.txt; echo "${?}") \
		"${LIFERAY_COMMON_EXIT_CODE_OK}"
}

main