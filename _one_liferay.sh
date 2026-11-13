#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/_liferay_common.sh"

function get_license_api_oauth2_access_token {
	if [ -z "${LIFERAY_DOCKER_LICENSE_API_OAUTH2_CLIENT_ID}" ] || [ -z "${LIFERAY_DOCKER_LICENSE_API_OAUTH2_CLIENT_SECRET}" ]
	then
		lc_log ERROR "Set the environment variables LIFERAY_DOCKER_LICENSE_API_OAUTH2_CLIENT_ID and LIFERAY_DOCKER_LICENSE_API_OAUTH2_CLIENT_SECRET." >&2

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local http_code_file=$(mktemp)

	local license_api_oauth2_access_token_response=$( \
		curl \
			--data "client_id=${LIFERAY_DOCKER_LICENSE_API_OAUTH2_CLIENT_ID}&client_secret=${LIFERAY_DOCKER_LICENSE_API_OAUTH2_CLIENT_SECRET}&grant_type=client_credentials" \
			--request POST \
			--retry 3 \
			--retry-delay 10 \
			--silent \
			--write-out "%output{${http_code_file}}%{http_code}" \
			"https://one.liferay.com/o/oauth2/token")

	local http_code=$(cat "${http_code_file}")

	rm --force "${http_code_file}"

	if [ "${http_code}" != "200" ]
	then
		lc_log ERROR "Unable to get the license API OAuth2 access token. HTTP response code was ${http_code}." >&2

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	echo "${license_api_oauth2_access_token_response}" | jq --raw-output ".access_token // empty"
}