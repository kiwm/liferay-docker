#!/bin/bash

source _liferay_common.sh

function _invoke_jira_api {

	local http_response=$(curl \
		"${1}" \
		--data "${2}" \
		--fail \
		--header "Accept: application/json" \
		--header "Content-Type: application/json" \
		--max-time 10 \
		--request "POST" \
		--retry 3 \
		--silent \
		--user "${LIFERAY_RELEASE_JIRA_USER}:${LIFERAY_RELEASE_JIRA_TOKEN}")

	if [ "$(echo "${http_response}" | jq --exit-status '.id?')" != "null" ]
	then
		echo "${http_response}" | jq --raw-output '.key'

		return "${LIFERAY_COMMON_EXIT_CODE_OK}"	
	fi

	echo "${LIFERAY_COMMON_EXIT_CODE_BAD}"
}