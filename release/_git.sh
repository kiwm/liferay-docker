#!/bin/bash

function cherry_pick_commits {
	local liferay_release_tickets_array

	IFS=',' read -ra liferay_release_tickets_array <<< "${LIFERAY_RELEASE_TICKETS}"

	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	git pull origin -q "${LIFERAY_RELEASE_GIT_REF}"

	local cherry_pick_all_commits="true"

	for liferay_release_ticket in "${liferay_release_tickets_array[@]}"
	do
		git checkout -q master

		local liferay_release_commits_sha

		read -r -d '' -a liferay_release_commits_sha < <(git log --grep="${liferay_release_ticket}" --pretty=format:%H --reverse)

		git checkout -q "${LIFERAY_RELEASE_GIT_REF}"

		for liferay_release_commit_sha in "${liferay_release_commits_sha[@]}"
		do
			git cherry-pick --strategy-option theirs "${liferay_release_commit_sha}" > /dev/null

			if [ $? -eq 0 ]
			then
				lc_log INFO "Cherry-pick of commit ${liferay_release_commit_sha} successful"
			else
				lc_log ERROR "Cherry-pick of commit ${liferay_release_commit_sha} failed"

				return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
			fi
		done
	done

	git push origin -q "${LIFERAY_RELEASE_GIT_REF}"
}

function clean_portal_repository {
	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	if [ -e "${_BUILD_DIR}"/built.sha ] &&
	   [ $(cat "${_BUILD_DIR}"/built.sha) == "${LIFERAY_RELEASE_GIT_REF}${LIFERAY_RELEASE_HOTFIX_TEST_SHA}" ]
	then
		lc_log INFO "${LIFERAY_RELEASE_GIT_REF} was already built in ${_BUILD_DIR}."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	git reset --hard && git clean -dfx
}

function clone_repository {
	if [ -e "${_PROJECTS_DIR}/${1}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	mkdir -p "${_PROJECTS_DIR}"

	lc_cd "${_PROJECTS_DIR}"

	if [ -e "/home/me/dev/projects/${1}" ]
	then
		echo "Copying Git repository from /home/me/dev/projects/${1}."

		cp -a "/home/me/dev/projects/${1}" "${_PROJECTS_DIR}"
	elif [ -e "/opt/dev/projects/github/${1}" ]
	then
		echo "Copying Git repository from /opt/dev/projects/github/${1}."

		cp -a "/opt/dev/projects/github/${1}" "${_PROJECTS_DIR}"
	else
		git clone git@github.com:liferay/"${1}".git
	fi

	lc_cd "${1}"

	if (git remote get-url upstream &>/dev/null)
	then
		git remote set-url upstream git@github.com:liferay/"${1}".git
	else
		git remote add upstream git@github.com:liferay/"${1}".git
	fi

	if (! git remote get-url brianchandotcom &>/dev/null)
	then
		git remote add brianchandotcom git@github.com:brianchandotcom/"${1}".git
	fi

	git remote --verbose
}

function generate_release_notes {
	if [ "${LIFERAY_RELEASE_PRODUCT_NAME}" == "portal" ]
	then
		lc_log INFO "The product is set to \"portal.\""

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local ga_version=7.4.13-ga1

	if (! echo "${_PRODUCT_VERSION}" | grep -q "q")
	then
		ga_version=${_PRODUCT_VERSION%%-u*}-ga1
	fi

	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	git log "tags/${ga_version}..HEAD" --pretty=%s | \
		grep -E "^[A-Z][A-Z0-9]*-[0-9]*" | \
		sed -e "s/^\([A-Z][A-Z0-9]*-[0-9]*\).*/\\1/" | \
		sort | \
		uniq | \
		grep -v LRCI | \
		grep -v LRQA | \
		grep -v POSHI | \
		grep -v RELEASE | \
		paste -sd, > "${_BUILD_DIR}/release/release-notes.txt"
}

function set_git_sha {
	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	_GIT_SHA=$(git rev-parse HEAD)
	_GIT_SHA_SHORT=$(git rev-parse --short HEAD)
}

function update_portal_repository {
	trap 'return ${LIFERAY_COMMON_EXIT_CODE_BAD}' ERR

	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	local checkout_ref="${LIFERAY_RELEASE_GIT_REF}"

	if [ -e "${_BUILD_DIR}"/liferay-portal-ee.sha ] &&
	   [ $(cat "${_BUILD_DIR}"/liferay-portal-ee.sha) == "${LIFERAY_RELEASE_GIT_REF}" ]
	then
		lc_log INFO "${LIFERAY_RELEASE_GIT_REF} was already checked out in ${_PROJECTS_DIR}/liferay-portal-ee."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if (echo "${LIFERAY_RELEASE_GIT_REF}" | grep -q -E "^[[:alnum:]\.-]+/[0-9a-z]{40}$")
	then
		checkout_ref="${LIFERAY_RELEASE_GIT_REF#*/}"

		LIFERAY_RELEASE_GIT_REF="${LIFERAY_RELEASE_GIT_REF%/*}"
	elif (echo "${LIFERAY_RELEASE_GIT_REF}" | grep -qE "^[0-9a-f]{40}$")
	then
		lc_log INFO "Looking for a tag that matches Git SHA ${LIFERAY_RELEASE_GIT_REF}."

		LIFERAY_RELEASE_GIT_REF=$(git ls-remote upstream | grep "${LIFERAY_RELEASE_GIT_REF}" | grep refs/tags/fix-pack-fix- | head -n 1 | sed -e "s#.*/##")

		if [ -n "${LIFERAY_RELEASE_GIT_REF}" ]
		then
			lc_log INFO "Found tag ${LIFERAY_RELEASE_GIT_REF}."
		else
			lc_log ERROR "No tag found."

			return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
		fi
	fi

	if [ -n "$(git ls-remote upstream refs/tags/"${LIFERAY_RELEASE_GIT_REF}")" ]
	then
		lc_log INFO "${LIFERAY_RELEASE_GIT_REF} tag exists on remote."

		git fetch --force upstream tag "${LIFERAY_RELEASE_GIT_REF}"
	elif [ -n "$(git ls-remote brianchandotcom refs/heads/"${LIFERAY_RELEASE_GIT_REF}")" ]
	then
		echo "${LIFERAY_RELEASE_GIT_REF} branch exists on brianchandotcom's remote."

		git fetch --force --update-head-ok brianchandotcom "${LIFERAY_RELEASE_GIT_REF}:${LIFERAY_RELEASE_GIT_REF}"
	elif [ -n "$(git ls-remote upstream refs/heads/"${LIFERAY_RELEASE_GIT_REF}")" ]
	then
		echo "${LIFERAY_RELEASE_GIT_REF} branch exists on remote."

		git fetch --force --update-head-ok upstream "${LIFERAY_RELEASE_GIT_REF}:${LIFERAY_RELEASE_GIT_REF}"
	else
		lc_log ERROR "${LIFERAY_RELEASE_GIT_REF} does not exist."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	git reset --hard && git clean -dfx

	git checkout "${checkout_ref}"

	git status

	echo "${LIFERAY_RELEASE_GIT_REF}" > "${_BUILD_DIR}"/liferay-portal-ee.sha
}

function create_branch {
	local original_branch_name="master"

	if [ "${LIFERAY_RELEASE_SOFT}" == "true" ]
	then
		original_branch_name="${LIFERAY_RELEASE_GIT_PREV_REF}"
	fi

	local last_commit=$(curl \
		"https://api.github.com/repos/liferay/liferay-portal-ee/git/refs/heads/${original_branch_name}" \
		--fail \
		--header "Authorization: token ${LIFERAY_RELEASE_GITHUB_TOKEN}" \
		--max-time 10 \
		--retry 3 \
		--silent)

	if [ $? -gt 0 ]
	then
    	lc_log ERROR "Unable to get the last commit from the ${original_branch_name} branch"

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	local commits_interval_json=$(jq -n --arg ref "refs/heads/${LIFERAY_RELEASE_GIT_REF}" --arg last_commit_sha "$(echo "${last_commit}" | jq -r '.object.sha')" '{ref: $ref, sha: $last_commit_sha}')

	local http_response_code=$(curl \
		"https://api.github.com/repos/liferay/liferay-portal-ee/git/refs" \
		--data "${commits_interval_json}" \
		--fail \
		--header "Authorization: token ${LIFERAY_RELEASE_GITHUB_TOKEN}" \
		--max-time 10 \
		--output /dev/null \
		--request POST \
		--retry 3 \
		--silent \
		--write-out "%{response_code}")

	if [ $? -gt 0 ]
	then
    	lc_log ERROR "Unable to create the ${LIFERAY_RELEASE_GIT_REF} branch"

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	if [ "${http_response_code}" == "201" ]
	then
		lc_log INFO "${LIFERAY_RELEASE_GIT_REF} branch successful created"

		if [ "${LIFERAY_RELEASE_SOFT}" == "true" ]
		then
			cherry_pick_commits
		fi
	else
		lc_log ERROR "Unable to create the ${LIFERAY_RELEASE_GIT_REF} branch"

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function update_release_tool_repository {
	trap 'return ${LIFERAY_COMMON_EXIT_CODE_BAD}' ERR

	if [ "${LIFERAY_RELEASE_PRODUCT_NAME}" == "portal" ]
	then
		lc_log INFO "The product is set to \"portal.\""

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_cd "${_PROJECTS_DIR}"/liferay-release-tool-ee

	git reset --hard && git clean -dfx

	local release_tool_sha=$(lc_get_property "${_PROJECTS_DIR}"/liferay-portal-ee/release.properties "release.tool.sha")

	if [ ! -n "${release_tool_sha}" ]
	then
		lc_log ERROR "The property \"release.tool.sha\" is missing from liferay-portal-ee/release.properties."

		return 1
	fi

	if [ -e "${_BUILD_DIR}"/liferay-release-tool-ee.sha ] &&
	   [ $(cat "${_BUILD_DIR}"/liferay-release-tool-ee.sha) == "${release_tool_sha}" ]
	then
		lc_log INFO "${release_tool_sha} was already checked out in ${_PROJECTS_DIR}/liferay-release-tool-ee."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	git fetch --force --prune upstream

	git fetch --force --prune --tags upstream

	git checkout master

	git pull upstream master

	git checkout "${release_tool_sha}"

	echo "${release_tool_sha}" > "${_BUILD_DIR}"/liferay-release-tool-ee.sha
}