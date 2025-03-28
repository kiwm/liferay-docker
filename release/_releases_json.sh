#!/bin/bash

function generate_releases_json {
	if [ "${1}" = "regenerate" ]
	then
		_process_product dxp
		_process_product portal
	else
		_process_new_product

		if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
		then
			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi
	fi

	_promote_product_versions dxp
	_promote_product_versions portal

	_merge_json_snippets

	_upload_releases_json
}

function _merge_json_snippets {
	if (! jq -s add $(ls ./*.json | sort -r) > releases.json)
	then
		lc_log ERROR "Detected invalid JSON."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function _process_new_product {
	if [[ $(echo "${_PRODUCT_VERSION}" | grep "7.4") ]] &&
	   [[ $(echo "${_PRODUCT_VERSION}" | cut -d 'u' -f 2) -gt 112 ]]
	then
		lc_log INFO "${_PRODUCT_VERSION} should not be added to releases.json."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local releases_json="${_PROMOTION_DIR}/0000-00-00-releases.json"

	if [ ! -f "${releases_json}" ]
	then
		lc_log INFO "Downloading https://releases.liferay.com/releases.json to ${releases_json}."

		LIFERAY_COMMON_DOWNLOAD_SKIP_CACHE="true" lc_download https://releases.liferay.com/releases.json "${releases_json}"
	fi

	if (grep "${_PRODUCT_VERSION}" "${releases_json}")
	then
		lc_log INFO "The version ${_PRODUCT_VERSION} is already in releases.json."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local product_group_version="$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2)"

	jq "map(
			if .product == \"${LIFERAY_RELEASE_PRODUCT_NAME}\" and .productGroupVersion == \"${product_group_version}\"
			then
				.promoted = \"false\"
			else
				.
			end
		)" "${releases_json}" > temp_file.json && mv temp_file.json "${releases_json}"

	_process_product_version "${LIFERAY_RELEASE_PRODUCT_NAME}" "${_PRODUCT_VERSION}"
}

function _process_product {
	local product_name="${1}"

	local release_directory_url="https://releases.liferay.com/${product_name}"

	lc_log INFO "Generating product version list from ${release_directory_url}."

	local directory_html=$(lc_curl "${release_directory_url}/")

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to download the product version list."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	for product_version in  $(echo -en "${directory_html}" | \
		grep -E -o "(20[0-9]+\.q[0-9]\.[0-9]+(-lts)?|7\.[0-9]+\.[0-9]+[a-z0-9\.-]+)/" | \
		tr -d "/" | \
		uniq)
	do
		if [[ $(echo "${product_version}" | grep "7.4") ]] && [[ $(echo "${product_version}" | cut -d 'u' -f 2) -gt 112 ]]
		then
			continue
		fi

		_process_product_version "${product_name}" "${product_version}"
	done
}

function _process_product_version {
	local product_name=${1}
	local product_version=${2}

	lc_log INFO "Processing ${product_name} ${product_version}."

	local release_properties_file

	#
	# Define release_properties_file in a separate line to capture the exit code.
	#

	release_properties_file=$(lc_download "https://releases.liferay.com/${product_name}/${product_version}/release.properties")

	local exit_code=${?}

	if [ "${exit_code}" == "${LIFERAY_COMMON_EXIT_CODE_MISSING_RESOURCE}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	elif [ "${exit_code}" == "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local release_date=$(lc_get_property "${release_properties_file}" release.date)

	if [ -z "${release_date}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	tee "${release_date}-${product_name}-${product_version}.json" <<- END
	[
	    {
	        "product": "${product_name}",
	        "productGroupVersion": "$(echo "${product_version}" | sed -r "s@(^[0-9]+\.[0-9a-z]+)\..*@\1@")",
	        "productVersion": "$(lc_get_property "${release_properties_file}" liferay.product.version)",
	        "promoted": "false",
	        "releaseKey": "$(echo "${product_name}-${product_version}" | sed "s/\([0-9]\+\)\.\([0-9]\+\)\.[0-9]\+\(-\|[^0-9]\)/\1.\2\3/g" | sed -e "s/portal-7\.4\.[0-9]*-ga/portal-7.4-ga/")",
	        "targetPlatformVersion": "$(lc_get_property "${release_properties_file}" target.platform.version)",
	        "url": "https://releases-cdn.liferay.com/${product_name}/${product_version}"
	    }
	]
	END
}

function _promote_product_versions {
	local product_name=${1}

	while read -r group_version || [ -n "${group_version}" ]
	do
		# shellcheck disable=SC2010
		last_version=$(ls | grep "${product_name}-${group_version}" | tail -n 1 2>/dev/null)

		if [ -n "${last_version}" ]
		then
			lc_log INFO "Promoting ${last_version}."

			sed -i 's/"promoted": "false"/"promoted": "true"/' "${last_version}"
		else
			lc_log INFO "No product version found to promote for ${product_name}-${group_version}."
		fi
	done < "${_RELEASE_ROOT_DIR}/supported-${product_name}-versions.txt"
}

function _upload_releases_json {
	ssh root@lrdcom-vm-1 "exit" &> /dev/null

	if [ "${?}" -eq 0 ]
	then
		lc_log INFO "Backing up to /www/releases.liferay.com/releases.json.BACKUP."

		ssh root@lrdcom-vm-1 cp -f "/www/releases.liferay.com/releases.json" "/www/releases.liferay.com/releases.json.BACKUP"

		lc_log INFO "Uploading ${_PROMOTION_DIR}/releases.json to /www/releases.liferay.com/releases.json."

		scp "${_PROMOTION_DIR}/releases.json" "root@lrdcom-vm-1:/www/releases.liferay.com/releases.json.upload"

		ssh root@lrdcom-vm-1 mv -f "/www/releases.liferay.com/releases.json.upload" "/www/releases.liferay.com/releases.json"
	fi

	lc_log INFO "Backing up to gs://liferay-releases/releases.json.BACKUP."

	gsutil cp "gs://liferay-releases/releases.json" "gs://liferay-releases/releases.json.BACKUP"

	lc_log INFO "Uploading ${_PROMOTION_DIR}/releases.json to gs://liferay-releases/releases.json."

	gsutil cp "${_PROMOTION_DIR}/releases.json" "gs://liferay-releases/releases.json.upload"

	gsutil mv "gs://liferay-releases/releases.json.upload" "gs://liferay-releases/releases.json"
}