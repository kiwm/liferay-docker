#!/bin/bash

source ../_liferay_common.sh
source _github.sh
source _jira.sh
source _product.sh
source _product_info_json.sh
source _promotion.sh
source _releases_json.sh

function check_supported_versions {
	local supported_version="$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2)"

	if [ -z $(grep "${supported_version}" "${_RELEASE_ROOT_DIR}"/supported-"${LIFERAY_RELEASE_PRODUCT_NAME}"-versions.txt) ]
	then
		lc_log ERROR "Unable to find ${supported_version} in supported-${LIFERAY_RELEASE_PRODUCT_NAME}-versions.txt."

		exit "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function check_usage {
	if [ -z "${LIFERAY_RELEASE_RC_BUILD_TIMESTAMP}" ] || [ -z "${LIFERAY_RELEASE_VERSION}" ]
	then
		print_help
	fi

	if [ -z "${LIFERAY_RELEASE_PRODUCT_NAME}" ]
	then
		LIFERAY_RELEASE_PRODUCT_NAME=dxp
	fi

	set_product_version "${LIFERAY_RELEASE_VERSION}" "${LIFERAY_RELEASE_RC_BUILD_TIMESTAMP}"

	lc_cd "$(dirname "$(readlink /proc/$$/fd/255 2>/dev/null)")"

	_RELEASE_ROOT_DIR="${PWD}"

	_PROMOTION_DIR="${_RELEASE_ROOT_DIR}/release-data/promotion/files"

	rm -fr "${_PROMOTION_DIR}"

	mkdir -p "${_PROMOTION_DIR}"

	lc_cd "${_PROMOTION_DIR}"

	LIFERAY_COMMON_LOG_DIR="${_PROMOTION_DIR%/*}"
}

function commit_to_branch_and_send_pull_request {
	git add "${1}"

	git commit --message "${2}"

	git push --force origin "${3}"

	gh pr create \
		--body "Created by the Release team automation." \
		--head "liferay-release:${3}" \
		--repo "${4}" \
		--title "${2}"

	if [ "${?}" -ne 0 ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function main {
	check_usage

	check_supported_versions

	init_gcs

	lc_time_run promote_packages

	lc_time_run tag_release

	promote_boms xanadu

	if [[ ! $(echo "${_PRODUCT_VERSION}" | grep "q") ]] &&
	   [[ ! $(echo "${_PRODUCT_VERSION}" | grep "7.4") ]]
	then
		lc_log INFO "Do not update product_info.json for quarterly and 7.4 releases."

		lc_time_run generate_product_info_json

		lc_time_run upload_product_info_json
	fi

	lc_time_run generate_releases_json

	lc_time_run test_boms

	#lc_time_run prepare_next_release_branch

	#lc_time_run upload_to_docker_hub

	lc_time_run add_patcher_project_version

	lc_time_run reference_new_releases
}

function reference_new_releases {
	prepare_branch_to_commit_from_master "${_PROJECTS_DIR}/liferay-jenkins-ee/commands" "new_releases_branch"

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to prepare the next release references branch."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	if [[ "${_PRODUCT_VERSION}" != *q* ]]
	then
		lc_log INFO "Skipping the update ont he references on the liferay-jenkings-ee repository."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if [[ "${_PRODUCT_VERSION}" == release-* ]]
	then
		local previous_quarterly_release_branch_name="$(grep "extraapps.app.server.versions" "build.properties" | tail -1 | sed "s/.*\[\(.*\)\].*/\1/")"

		sed \
			-i "s/^		${previous_quarterly_release_branch_name}$/		${previous_quarterly_release_branch_name},\\\\/" \
			"build.properties"

		sed \
			-i "/${previous_quarterly_release_branch_name},/a\		${_PRODUCT_VERSION}" \
			"build.properties"

		sed \
			-i "/extraapps.app.server.versions\[${previous_quarterly_release_branch_name}\]=/a \	extraapps.app.server.versions[${_PRODUCT_VERSION}]=tomcat8" \
			"build.properties"

		sed \
			-i "/extraapps.database.versions\[${previous_quarterly_release_branch_name}\]=/a \	extraapps.database.versions[${_PRODUCT_VERSION}]=mysql57" \
			"build.properties"

		sed \
			-i "/faces.alloy.branch.name\[${previous_quarterly_release_branch_name}\]=/a \	faces.alloy.branch.name[${_PRODUCT_VERSION}]=master" \
			"build.properties"

		sed \
			-i "/faces.bridge.impl.branch.name\[${previous_quarterly_release_branch_name}\]=/a \	faces.bridge.impl.branch.name[${_PRODUCT_VERSION}]=4.x" \
			"build.properties"

		sed \
			-i "/faces.portal.branch.name\[${previous_quarterly_release_branch_name}\]=/a \	faces.portal.branch.name[${_PRODUCT_VERSION}]=4.x" \
			"build.properties"

		sed \
			-i "/faces.showcase.branch.name\[${previous_quarterly_release_branch_name}\]=/a \	faces.showcase.branch.name[${_PRODUCT_VERSION}]=3.x" \
			"build.properties"

		sed \
			-i "/jenkins.repository\[${previous_quarterly_release_branch_name}\]=/a \	jenkins.repository[${_PRODUCT_VERSION}]=liferay-jenkins-ee" \
			 "build.properties"

		sed \
			-i "/plugins.build.properties\[app.server.parent.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	plugins.build.properties[app.server.parent.dir][${_PRODUCT_VERSION}]=\${portal.dir[7.0.x]}/bundles" \
			"build.properties"

		sed \
			-i "/plugins.build.properties\[liferay.home\]\[${previous_quarterly_release_branch_name}\]=/a \	plugins.build.properties[liferay.home][${_PRODUCT_VERSION}]=\${portal.dir[7.0.x]}/bundles" \
			"build.properties"

		sed \
			-i "/plugins.dir\[${previous_quarterly_release_branch_name}\]=/a \	plugins.dir[${_PRODUCT_VERSION}]=/opt/dev/projects/github/liferay-plugins-7.0.x" \
			"build.properties"

		sed \
			-i "/plugins.repository\[${previous_quarterly_release_branch_name}\]=/a \	plugins.repository[${_PRODUCT_VERSION}]=liferay-plugins-ee" \
			"build.properties"

		sed \
			-i "/plugins.war.zip.url\[${previous_quarterly_release_branch_name}\]=/a \	plugins.war.zip.url[${_PRODUCT_VERSION}]=http://release-1/1/userContent/liferay-release-tool/7413/plugins.war.latest.zip" \
			"build.properties"

		sed \
			-i "/portal.app.server.properties\[app.server.parent.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.app.server.properties[app.server.parent.dir][${_PRODUCT_VERSION}]=\${portal.dir[${_PRODUCT_VERSION}]}/bundles" \
			"build.properties"

		sed \
			-i "/portal.branch.name\[${previous_quarterly_release_branch_name}\]=master/a \	portal.branch.name[${_PRODUCT_VERSION}]=master" \
			"build.properties"

		sed \
			-i "/portal.build.properties\[liferay.home\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.build.properties[liferay.home][${_PRODUCT_VERSION}]=\${portal.dir[${_PRODUCT_VERSION}]}/bundles" \
			"build.properties"

		sed \
			-i "/portal.build.properties\[release.versions.test.other.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.build.properties[release.versions.test.other.dir][${_PRODUCT_VERSION}]=\${portal.dir[7.0.x]}" \
			"build.properties"

		sed \
			-i "/portal.dir\[${previous_quarterly_release_branch_name}\]=/a \	portal.dir[${_PRODUCT_VERSION}]=/opt/dev/projects/github/liferay-portal-ee" \
			"build.properties"

		sed \
			-i "/portal.lcs.license.url\[${previous_quarterly_release_branch_name}\]=/a \	portal.lcs.license.url[${_PRODUCT_VERSION}]=\${private.property[portal.lcs.license.url]}" \
			"build.properties"

		sed \
			-i "/portal.license.url\[${previous_quarterly_release_branch_name}\]=/a \	portal.license.url[${_PRODUCT_VERSION}]=http://www.liferay.com/licenses/license-portaldevelopment-developer-cluster-7.0de-liferaycom.xml" \
			"build.properties"

		sed \
			-i "/portal.release.properties\[lp.plugins.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.release.properties[lp.plugins.dir][${_PRODUCT_VERSION}]=\${plugins.dir[7.0.x]}" \
			"build.properties"

		sed \
			-i "/portal.repository\[${previous_quarterly_release_branch_name}\]=/a \	portal.repository[${_PRODUCT_VERSION}]=liferay-portal-ee" \
			"build.properties"

		sed \
			-i "/portal.test.properties\[browser.chrome.docker.image\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.test.properties[browser.chrome.docker.image][${_PRODUCT_VERSION}]=liferay/liferay-ci-environment:chrome-100_1.0.2" \
			"build.properties"

		sed \
			-i "/portal.test.properties\[portal.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.test.properties[portal.dir][${_PRODUCT_VERSION}]=\${portal.dir[${_PRODUCT_VERSION}]}" \
			"build.properties"

		sed \
			-i "/portal.test.properties\[test.batch.run.type\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.test.properties[test.batch.run.type][${_PRODUCT_VERSION}]=sequential" \
			"build.properties"

		sed \
			-i "/portal.test.properties\[testray.product.version.name\]\[${previous_quarterly_release_branch_name}\]=/a \	portal.test.properties[testray.product.version.name][${_PRODUCT_VERSION}]=${_PRODUCT_VERSION}" \
			"build.properties"

		sed \
			-i "/private.modules.excludes\[${previous_quarterly_release_branch_name}\]=/a \	private.modules.excludes[${_PRODUCT_VERSION}]=\${private.modules.excludes[master]}" \
			"build.properties"

		sed \
			-i "/release.tool.build.properties\[bundles.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	release.tool.build.properties[bundles.dir][${_PRODUCT_VERSION}]=\${portal.dir[${_PRODUCT_VERSION}]}/bundles" \
			"build.properties"

		sed \
			-i "/release.tool.build.properties\[portal.dir\]\[${previous_quarterly_release_branch_name}\]=/a \	release.tool.build.properties[portal.dir][${_PRODUCT_VERSION}]=\${portal.dir[${_PRODUCT_VERSION}]}" \
			"build.properties"

		sed \
			-i "/release.tool.dir\[${previous_quarterly_release_branch_name}\]=/a \	release.tool.dir[${_PRODUCT_VERSION}]=/opt/dev/projects/github/liferay-release-tool-ee" \
			"build.properties"

		sed \
			-i "/release.tool.repository\[${previous_quarterly_release_branch_name}\]=/a \	release.tool.repository[${_PRODUCT_VERSION}]=liferay-release-tool-ee" \
			"build.properties"
	else
		local base_url="http://mirrors.lax.liferay.com/releases.liferay.com"

		local previous_product_version="$(grep "portal.latest.bundle.version\[master\]=" "build.properties" | cut -d "=" -f 2)"

		for component in osgi sql tools
		do
			sed \
				-i "/portal.${component}.zip.url\[${previous_product_version}\]=/a \	\portal.${component}.zip.url[${_PRODUCT_VERSION}]=${base_url}/${LIFERAY_RELEASE_PRODUCT_NAME}/${_PRODUCT_VERSION}/liferay-${LIFERAY_RELEASE_PRODUCT_NAME}-${component}-${_PRODUCT_VERSION}-${LIFERAY_RELEASE_RC_BUILD_TIMESTAMP}.zip" \
				"build.properties"
		done

		sed \
			-i "/plugins.war.zip.url\[${previous_product_version}\]=/a \	\plugins.war.zip.url[${_PRODUCT_VERSION}]=http://release-1/1/userContent/liferay-release-tool/7413/plugins.war.latest.zip" \
			"build.properties"

		sed \
			-i "/portal.bundle.tomcat\[${previous_product_version}\]=/a \		\portal.bundle.tomcat[${_PRODUCT_VERSION}]=${base_url}/${LIFERAY_RELEASE_PRODUCT_NAME}/${_PRODUCT_VERSION}/liferay-${LIFERAY_RELEASE_PRODUCT_NAME}-tomcat-${_PRODUCT_VERSION}-${LIFERAY_RELEASE_RC_BUILD_TIMESTAMP}.7z" \
			"build.properties"

		sed \
			-i "/portal.license.url\[${previous_product_version}\]=/a \	\portal.license.url[${_PRODUCT_VERSION}]=http://www.liferay.com/licenses/license-portaldevelopment-developer-cluster-7.0de-liferaycom.xml" \
			"build.properties"

		sed \
			-i "/portal.version.latest\[${previous_product_version}\]=/a \	\portal.version.latest\[${_PRODUCT_VERSION}\]=${_PRODUCT_VERSION}" \
			"build.properties"

		sed \
			-i "/portal.war.url\[${previous_product_version}\]=/a \	\portal.war.url\[${_PRODUCT_VERSION}\]=${base_url}/${LIFERAY_RELEASE_PRODUCT_NAME}/${_PRODUCT_VERSION}/liferay-${LIFERAY_RELEASE_PRODUCT_NAME}-${_PRODUCT_VERSION}-${LIFERAY_RELEASE_RC_BUILD_TIMESTAMP}.war" \
			"build.properties"

		sed \
			-i "/portal.latest.bundle.version\[${previous_product_version}\]=/a \	\portal.latest.bundle.version\[${_PRODUCT_VERSION}\]=${_PRODUCT_VERSION}" \
			"build.properties"

		sed \
			-i "s/portal.latest.bundle.version\[master\]=${previous_product_version}/portal.latest.bundle.version\[master\]=${_PRODUCT_VERSION}/" \
			"build.properties"


		local previous_quarterly_release_branch_name="$(grep "portal.latest.bundle.version" "build.properties" | tail -1 | sed "s/.*\[\(.*\)\].*/\1/")"

		local quarterly_release_branch_name="release-$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2)"

		if [ "${quarterly_release_branch_name}" == "${previous_quarterly_release_branch_name}" ]
		then
			sed \
				-i "s/portal.latest.bundle.version\[${quarterly_release_branch_name}\]=${previous_product_version}/portal.latest.bundle.version\[${quarterly_release_branch_name}\]=${_PRODUCT_VERSION}/" \
				"build.properties"

			sed \
				-i "s/portal.version.latest\[${quarterly_release_branch_name}\]=${previous_product_version}/portal.version.latest\[${quarterly_release_branch_name}\]=${_PRODUCT_VERSION}/" \
				"build.properties"
		else
			sed \
				-i "/portal.latest.bundle.version\[${previous_quarterly_release_branch_name}\]=/a \	\portal.latest.bundle.version\[${quarterly_release_branch_name}\]=${_PRODUCT_VERSION}" \
				"build.properties"

			sed \
				-i "/portal.version.latest\[${previous_quarterly_release_branch_name}\]=/a \	\portal.version.latest\[${quarterly_release_branch_name}\]=${_PRODUCT_VERSION}" \
				"build.properties"
		fi
	fi

	local ticket_key="$(\
		create_jira_ticket \
			"60a3f462391e56006e6b661b" \
			"Release Tester" \
			"Task" \
			"LRCI" \
			"Add release references for ${_PRODUCT_VERSION}" \
			"customfield_10001" "04c03e90-c5a7-4fda-82f6-65746fe08b83")"

	commit_to_branch_and_send_pull_request \
		"${_PROJECTS_DIR}/liferay-jenkins-ee/commands/build.properties" \
		"${ticket_key} Add release references for ${_PRODUCT_VERSION}" \
		"new_releases_branch" \
		"pyoo47/liferay-jenkins-ee"

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to send the next release references."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	else
		lc_log INFO "The pull request with next release references was sent successfully."
	fi

	local pull_request_url="$(\
		gh pr view liferay-release:new_releases_branch \
		--repo pyoo47/liferay-jenkins-ee \
		--json url \
		-q ".url")"

	add_comment_jira_ticket "Related pull request: ${pull_request_url}" "${ticket_key}"
}

function prepare_branch_to_commit_from_master {
	lc_cd "${1}"

	git fetch upstream master

	git checkout master

	git reset --hard upstream/master

	git push --delete origin "${2}"

	git branch --delete --force "${2}"

	git checkout -b "${2}"

	git push origin "${2}" --force

	if [ "$(git rev-parse --abbrev-ref HEAD)" != "${2}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

function prepare_next_release_branch {
	if [[ "${_PRODUCT_VERSION}" != *q* ]]
	then
		lc_log INFO "Skipping the preparation of the next release branch."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	rm -fr releases.json

	LIFERAY_COMMON_DOWNLOAD_SKIP_CACHE="true" lc_download "https://releases.liferay.com/releases.json" releases.json

	local product_group_version="$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2)"

	local latest_quarterly_product_version="$(\
		jq -r ".[] | \
			select(.productGroupVersion == \"${product_group_version}\" and .promoted == \"true\") | \
			.targetPlatformVersion" releases.json)"

	rm -fr releases.json

	if [ "${_PRODUCT_VERSION}" != "${latest_quarterly_product_version}" ]
	then
		lc_log INFO "The ${_PRODUCT_VERSION} version is not the latest quartely release. Skipping the preparation of the next release branch."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_cd "${BASE_DIR}/liferay-portal-ee"

	local quarterly_release_branch_name="release-${product_group_version}"

	git branch --delete "${quarterly_release_branch_name}" &> /dev/null

	git fetch --no-tags upstream "${quarterly_release_branch_name}":"${quarterly_release_branch_name}" &> /dev/null

	git checkout "${quarterly_release_branch_name}" &> /dev/null

	local next_project_version_suffix="$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 3)"

	next_project_version_suffix=$((next_project_version_suffix + 1))

	sed -e "s/${product_group_version^^}\.[0-9]*/${product_group_version^^}\.${next_project_version_suffix}/" -i "${BASE_DIR}/liferay-portal-ee/release.properties"

	git add "${BASE_DIR}/liferay-portal-ee/release.properties"

	git commit -m "Prepare ${quarterly_release_branch_name}."

	git push upstream "${quarterly_release_branch_name}"

	if [ "${?}" -ne 0 ]
	then
		lc_log ERROR "Unable to prepare the next release branch."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	else
		lc_log INFO "The next release branch was prepared successfully."
	fi
}

function print_help {
	echo "Usage: LIFERAY_RELEASE_RC_BUILD_TIMESTAMP=<timestamp> LIFERAY_RELEASE_VERSION=<version> ${0}"
	echo ""
	echo "The script reads the following environment variables:"
	echo ""
	echo "    LIFERAY_RELEASE_GCS_TOKEN (optional): *.json file containing the token to authenticate with Google Cloud Storage"
	echo "    LIFERAY_RELEASE_GITHUB_PAT (optional): GitHub personal access token used to tag releases"
	echo "    LIFERAY_RELEASE_NEXUS_REPOSITORY_PASSWORD (optional): Nexus user's password"
	echo "    LIFERAY_RELEASE_NEXUS_REPOSITORY_USER (optional): Nexus user with the right to upload BOM files"
	echo "    LIFERAY_RELEASE_PATCHER_PORTAL_EMAIL_ADDRESS: Email address to the release team's Liferay Patcher user"
	echo "    LIFERAY_RELEASE_PATCHER_PORTAL_PASSWORD: Password to the release team's Liferay Patcher user"
	echo "    LIFERAY_RELEASE_PRODUCT_NAME (optional): Set to \"portal\" for CE. The default is \"DXP\"."
	echo "    LIFERAY_RELEASE_RC_BUILD_TIMESTAMP: Timestamp of the build to publish"
	echo "    LIFERAY_RELEASE_REPOSITORY_OWNER (optional): Set to \"EnterpriseReleaseHU\" for development. The default is \"liferay\"."
	echo "    LIFERAY_RELEASE_VERSION: DXP or portal version of the release to publish"
	echo ""
	echo "Example: LIFERAY_RELEASE_RC_BUILD_TIMESTAMP=1695892964 LIFERAY_RELEASE_VERSION=2023.q3.0 ${0}"

	exit "${LIFERAY_COMMON_EXIT_CODE_HELP}"
}

function tag_release {
	if [ -z "${LIFERAY_RELEASE_GITHUB_PAT}" ]
	then
		lc_log INFO "Set the environment variable \"LIFERAY_RELEASE_GITHUB_PAT\"."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local release_properties_file=$(lc_download "https://releases.liferay.com/${LIFERAY_RELEASE_PRODUCT_NAME}/${_PRODUCT_VERSION}/release.properties")

	if [ $? -ne 0 ]
	then
		lc_log ERROR "Unable to download release.properties."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local git_hash=$(lc_get_property "${release_properties_file}" git.hash.liferay-portal-ee)

	if [ -z "${git_hash}" ]
	then
		lc_log ERROR "Unable to get property \"git.hash.liferay-portal-ee.\""

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local repository=liferay-portal-ee

	if [ "${LIFERAY_RELEASE_PRODUCT_NAME}" == "portal" ]
	then
		repository=liferay-portal
	fi

	local tag_data=$(
		cat <<- END
		{
			"message": "",
			"object": "${git_hash}",
			"tag": "${_PRODUCT_VERSION}",
			"type": "commit"
		}
		END
	)

	if [ $(invoke_github_api_post "${repository}/git/tags" "${tag_data}") -eq "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	local ref_data=$(
		cat <<- END
		{
			"message": "",
			"ref": "refs/tags/${_PRODUCT_VERSION}",
			"sha": "${git_hash}"
		}
		END
	)

	if [ $(invoke_github_api_post "${repository}/git/refs" "${ref_data}") -eq "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}" ]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi
}

function test_boms {
	if [[ "${_PRODUCT_VERSION}" == 7.4.*-u* ]]
	then
		lc_log INFO "Skipping test BOMs for ${_PRODUCT_VERSION}."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	rm -f "${HOME}/.liferay/workspace/releases.json"

	mkdir -p "temp_dir_test_boms"

	lc_cd "temp_dir_test_boms"

	if [[ "${_PRODUCT_VERSION}" == *q* ]]
	then
		blade init -v "${LIFERAY_RELEASE_PRODUCT_NAME}-${_PRODUCT_VERSION}"
	else
		local product_group_version=$(echo "${_PRODUCT_VERSION}" | cut -d '.' -f 1,2)
		local product_version_suffix=$(echo "${_PRODUCT_VERSION}" | cut -d '-' -f 2)

		blade init -v "${LIFERAY_RELEASE_PRODUCT_NAME}-${product_group_version}-${product_version_suffix}"
	fi

	export LIFERAY_RELEASES_MIRRORS="https://releases.liferay.com"

	sed -i "s/version: \"10.1.0\"/version: \"10.1.2\"/" "temp_dir_test_boms/settings.gradle"

	for module in api mvc-portlet
	do
		blade create -t "${module}" "test-${module}"

		local build_result=$(blade gw build)

		if [[ "${build_result}" == *"BUILD SUCCESSFUL"* ]]
		then
			lc_log INFO "The BOMs for the module ${module} were successfully tested."
		else
			lc_log ERROR "The BOMs for the module ${module} were incorrectly generated."

			break
		fi
	done

	lc_cd ".."

	pgrep --full --list-name temp_dir_test_boms | awk '{print $1}' | xargs --no-run-if-empty kill -9

	rm -fr "temp_dir_test_boms"

	if [[ "${build_result}" != *"BUILD SUCCESSFUL"* ]]
	then
		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi
}

main