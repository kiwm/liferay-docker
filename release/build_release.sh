#!/bin/bash

source ../_liferay_common.sh
source ./_bom.sh
source ./_ci.sh
source ./_git.sh
source ./_hotfix.sh
source ./_jdk.sh
source ./_package.sh
source ./_patcher.sh
source ./_product.sh
source ./_publishing.sh

function check_usage {

	#
	# TODO Remove once all systems are using LIFERAY_RELEASE_GIT_REF instead of LIFERAY_RELEASE_GIT_SHA
	#

	if [ -z "${LIFERAY_RELEASE_GIT_REF}" ]
	then
		LIFERAY_RELEASE_GIT_REF=${LIFERAY_RELEASE_GIT_SHA}
	fi

	if [ -z "${LIFERAY_RELEASE_GIT_REF}" ]
	then
		print_help
	fi

	_BUILD_TIMESTAMP=$(date +%s)

	if [ -z "${LIFERAY_RELEASE_HOTFIX_ID}" ]
	then
		LIFERAY_RELEASE_HOTFIX_ID=${_BUILD_TIMESTAMP}
	fi

	if [ -z "${LIFERAY_RELEASE_PRODUCT_NAME}" ]
	then
		LIFERAY_RELEASE_PRODUCT_NAME=dxp
	fi

	_RELEASE_TOOL_DIR=$(dirname "$(readlink /proc/$$/fd/255 2>/dev/null)")

	lc_cd "${_RELEASE_TOOL_DIR}"

	mkdir -p release-data

	lc_cd release-data

	_RELEASE_ROOT_DIR="${PWD}"

	_BUILD_DIR="${_RELEASE_ROOT_DIR}/build"
	_BUILDER_SHA=$(git rev-parse HEAD)
	_BUNDLES_DIR="/opt/dev/projects/github/bundles"
	_PROJECTS_DIR="/opt/dev/projects/github"
	_RELEASES_DIR="${_RELEASE_ROOT_DIR}/releases"
	_TEST_RELEASE_DIR="${_RELEASE_ROOT_DIR}/test_release"

	if [ ! -d "${_PROJECTS_DIR}" ]
	then
		_BUNDLES_DIR="${_RELEASE_ROOT_DIR}/dev/projects/bundles"
		_PROJECTS_DIR="${_RELEASE_ROOT_DIR}/dev/projects"
	fi

	LIFERAY_COMMON_LOG_DIR="${_BUILD_DIR}"
}

function main {
	export ANT_OPTS="-Xmx10G"

	print_variables

	check_usage

	lc_cd "$(dirname "${_RELEASE_TOOL_DIR}")"

	LIFERAY_DOCKER_RELEASE_CANDIDATE="true" LIFERAY_DOCKER_IMAGE_FILTER="2025.q2.2-1750899891" ./build_all_images.sh
}

function print_help {
	echo "Usage: LIFERAY_RELEASE_GIT_REF=<git sha> ${0}"
	echo ""
	echo "The script reads the following environment variables:"
	echo ""
	echo "    LIFERAY_RELEASE_GCS_TOKEN (optional): *.json file containing the token to authenticate with Google Cloud Storage"
	echo "    LIFERAY_RELEASE_GIT_REF: Git SHA to build from"
	echo "    LIFERAY_RELEASE_HOTFIX_BUILD_ID (optional): Build ID on Patcher"
	echo "    LIFERAY_RELEASE_HOTFIX_FIXED_ISSUES (optional): Comma delimited list of fixed issues in the hotfix"
	echo "    LIFERAY_RELEASE_HOTFIX_ID (optional): Hotfix ID"
	echo "    LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_FILE (optional): *.pem file containing the hotfix signing key"
	echo "    LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_PASSWORD (optional): Password to unlock the hotfix signing key"
	echo "    LIFERAY_RELEASE_HOTFIX_TEST_SHA (optional): Git commit to cherry pick to build a test hotfix"
	echo "    LIFERAY_RELEASE_HOTFIX_TEST_TAG (optional): Tag name of the hotfix testing code in the liferay-portal-ee repository"
	echo "    LIFERAY_RELEASE_OUTPUT (optional): Set this to \"hotfix\" to build a hotfix instead of a release"
	echo "    LIFERAY_RELEASE_PATCHER_REQUEST_KEY (optional): Request key from Patcher that is used to report back statuses to Patcher"
	echo "    LIFERAY_RELEASE_PATCHER_USER_ID (optional): User ID of the patcher user who started the build"
	echo "    LIFERAY_RELEASE_PRODUCT_NAME (optional): Set to \"portal\" for CE. The default is \"DXP\"."
	echo "    LIFERAY_RELEASE_UPLOAD (optional): Set this to \"true\" to upload artifacts"
	echo ""
	echo "Example: LIFERAY_RELEASE_GIT_REF=release-2023.q3 ${0}"

	exit "${LIFERAY_COMMON_EXIT_CODE_HELP}"
}

function print_variables {
	echo "To reproduce this build locally, execute the following command in liferay-docker/release:"

	local environment=$(set | \
		grep --invert-match "LIFERAY_RELEASE_GCS_TOKEN" | \
		grep --invert-match "LIFERAY_RELEASE_HOTFIX_SIGNATURE" | \
		grep --invert-match "LIFERAY_RELEASE_PATCHER_REQUEST_KEY" | \
		grep --invert-match "LIFERAY_RELEASE_UPLOAD" | \
		grep --regexp "^LIFERAY_RELEASE" | \
		tr "\n" " ")

	echo "${environment}./build_release.sh"
	echo ""
}

main