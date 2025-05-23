#!/bin/bash

function commit_to_branch_and_send_pull_request {
	git add "${1}"

	git commit --message "${2}"

	local repository_name=$(echo "${5}" | cut -d '/' -f 2)

	git push --force "git@github.com:liferay-release/${repository_name}.git" "${3}"

	gh pr create \
		--base "${4}" \
		--body "Created by liferay-docker/release/release_gold.sh." \
		--head "liferay-release:${3}" \
		--repo "${5}" \
		--title "${6}"

	if [ "${?}" -ne 0 ]
	then
		return 1
	fi
}

function is_early_product_version_than {
	local product_version_1=$(echo "${ACTUAL_PRODUCT_VERSION}" | sed -e "s/-lts//")
	local product_version_1_quarter
	local product_version_1_suffix

	IFS='.' read -r product_version_1_year product_version_1_quarter product_version_1_suffix <<< "${product_version_1}"

	product_version_1_quarter=$(echo "${product_version_1_quarter}" | sed -e "s/q//")

	local product_version_2=$(echo "${1}" | sed -e "s/-lts//")
	local product_version_2_quarter
	local product_version_2_suffix

	IFS='.' read -r product_version_2_year product_version_2_quarter product_version_2_suffix <<< "${product_version_2}"

	product_version_2_quarter=$(echo "${product_version_2_quarter}" | sed -e "s/q//")

	if [ "${product_version_1_year}" -lt "${product_version_2_year}" ]
	then
		return 0
	elif [ "${product_version_1_year}" -gt "${product_version_2_year}" ]
	then
		return 1
	fi

	if [ "${product_version_1_quarter}" -lt "${product_version_2_quarter}" ]
	then
		return 0
	elif [ "${product_version_1_quarter}" -gt "${product_version_2_quarter}" ]
	then
		return 1
	fi

	if [ "${product_version_1_suffix}" -lt "${product_version_2_suffix}" ]
	then
		return 0
	elif [ "${product_version_1_suffix}" -gt "${product_version_2_suffix}" ]
	then
		return 1
	fi

	return 1
}

function is_quarterly_release {
	if [[ "${1}" == *q* ]]
	then
		return 0
	fi

	return 1
}

function prepare_branch_to_commit_from_master {
	lc_cd "${1}"

	git checkout master

	git fetch "git@github.com:kiwm/${2}.git" master

	git reset --hard FETCH_HEAD

	git checkout -b "${3}"

	git push "git@github.com:liferay-release/${2}.git" "${3}" --force

	if [ "$(git rev-parse --abbrev-ref HEAD)" != "${3}" ]
	then
		return 1
	fi
}

function set_actual_product_version {
	ACTUAL_PRODUCT_VERSION="${1}"
}