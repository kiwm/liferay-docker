#!/bin/bash

source ../_release_common.sh

function add_file_to_hotfix {
	local file_name=$(transform_file_name "${1}")

	local file_dir=$(dirname "${file_name}")

	lc_log DEBUG "Copying ${1} into the hotfix binaries directory at ${file_dir}."

	mkdir --parents "${_BUILD_DIR}/hotfix/binaries/${file_dir}"

	cp "${_BUNDLES_DIR}/${1}" "${_BUILD_DIR}/hotfix/binaries/${file_dir}"
}

function add_hotfix_testing_code {
	if [ ! -n "${LIFERAY_RELEASE_HOTFIX_TEST_SHA}" ]
	then
		echo "The environment variable LIFERAY_RELEASE_HOTFIX_TEST_SHA is not set."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_cd "${_PROJECTS_DIR}"/liferay-portal-ee

	if (! git show "${LIFERAY_RELEASE_HOTFIX_TEST_SHA}" &>/dev/null)
	then
		echo "Running: git fetch upstream tag \"${LIFERAY_RELEASE_HOTFIX_TEST_TAG}\""

		git fetch -v upstream tag "${LIFERAY_RELEASE_HOTFIX_TEST_TAG}" || return 1
	fi

	echo "Running: git cherry-pick -n \"${LIFERAY_RELEASE_HOTFIX_TEST_SHA}\""

	git cherry-pick -n "${LIFERAY_RELEASE_HOTFIX_TEST_SHA}" || return 1
}

function add_portal_patcher_properties_jar {
	lc_cd "${_BUILD_DIR}"

	mkdir portal-patcher-properties

	lc_cd "${_BUILD_DIR}/portal-patcher-properties"

	touch manifest

	(
		echo "fixed.issues=${LIFERAY_RELEASE_FIXED_ISSUES}"
		echo "installed.patches=${_HOTFIX_NAME}"
	)  > patcher.properties

	jar cfm portal-patcher-properties.jar manifest patcher.properties

	if [ -e "${_BUNDLES_DIR}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib" ]
	then
		cp portal-patcher-properties.jar "${_BUNDLES_DIR}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib"
	else
		cp portal-patcher-properties.jar "${_BUNDLES_DIR}/tomcat/webapps/ROOT/WEB-INF/lib"
	fi
}

function add_portal_patcher_service_properties_jar {
	if ! is_7_3_release
	then
		lc_log INFO "Patch level verification is not needed for ${_PRODUCT_VERSION}."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	lc_cd "${_BUILD_DIR}"

	mkdir portal-patcher-service-properties

	lc_cd "${_BUILD_DIR}/portal-patcher-service-properties"

	touch manifest

	(
		echo "fixed.issues=${LIFERAY_RELEASE_FIXED_ISSUES}"
		echo "installed.patches=${_HOTFIX_NAME}"
	)  > patcher-service.properties

	jar cfm portal-patcher-service-properties.jar manifest patcher-service.properties

	if [ -e "${_BUNDLES_DIR}/tomcat/lib/ext" ]
	then
		cp portal-patcher-service-properties.jar "${_BUNDLES_DIR}/tomcat/lib/ext"
	fi
}

function calculate_checksums {
	if [ ! -e "${_BUILD_DIR}/hotfix/binaries" ]
	then
		echo "There are no hotfix binaries."

		return
	fi

	lc_cd "${_BUILD_DIR}/hotfix/binaries"

	find . -type f -print0 | while IFS= read -r -d '' file
	do
		sha256sum "${file}" >> ../checksums
	done
}

function compare_jars {
	local jar1=${_BUNDLES_DIR}/"${1}"
	local jar2=${_RELEASE_DIR}/"${1}"

	lc_log DEBUG "Comparing JAR contents for ${1}."
	lc_log DEBUG "    Built JAR:     ${jar1}"
	lc_log DEBUG "    Reference JAR: ${jar2}"

	function compare_property_in_packaged_file {
		local jar1="${1}"
		local jar2="${2}"
		local packaged_file="${3}"
		local property="${4}"

		local value1=$(unzip -p "${jar1}" "${packaged_file}" | sed --null-data --regexp-extended "s@\r?\n @@g" | grep --word-regexp "${property}")
		local value2=$(unzip -p "${jar2}" "${packaged_file}" | sed --null-data --regexp-extended "s@\r?\n @@g" | grep --word-regexp "${property}")

		lc_log DEBUG "Comparing property ${property} inside ${packaged_file}:"
		lc_log DEBUG "    Built JAR:     ${value1:-<empty>}"
		lc_log DEBUG "    Reference JAR: ${value2:-<empty>}"

		if [ "${value1}" == "${value2}" ]
		then
			return 0
		fi

		return 1
	}

	function describe_jar {
		unzip -v "${1}" | \
			#
			# Remove 0 byte files
			#
			grep --invert-match 00000000 | \
			#
			# Remove generated files
			#
			grep --invert-match "META-INF/resources/aui/aui_deprecated.css" | \
			grep --invert-match "META-INF/resources/language.json" | \
			grep --invert-match "__liferay__/index.js" | \
			grep --invert-match "_jsp.class" | \
			grep --invert-match "_jsp.java" | \
			grep --invert-match "_jsp\$[^/]\+\.class" | \
			grep --invert-match "index.js.map" | \
			grep --invert-match "pom.properties" | \
			grep --invert-match "previous-compilation-data.bin" | \
			grep --invert-match "source-classes-mapping.txt" | \
			#
			# Remove headers and footers
			#
			grep "Defl:N" | \
			#
			# TODO Decide what to do with osgi/modules/com.liferay.sharepoint.soap.repository.jar
			#
			grep --invert-match "ws.jar" | \
			#
			# TODO Include portal-impl.jar when the util-*jars changed
			#
			grep --invert-match "com/liferay/portal/deploy/dependencies/" | \
			#
			# TODO Modify "ant all" to not update this file every time
			#
			grep --invert-match "META-INF/system.packages.extra.mf" | \
			#
			# Print only the relevant fields: uncompressed size, compression method, checksum, and name
			#
			awk '{print $1, $2, $7, $8}'
	}

	local jar_descriptions=$( (
		describe_jar "${jar1}"
		describe_jar "${jar2}"
	) | sort | uniq --count)

	if [ $(echo "${jar_descriptions}" | grep --count "Defl:N") -eq 0 ]
	then
		lc_log ERROR "The JARs have no files."

		exit 2
	fi

	jar_descriptions=$(echo "${jar_descriptions}" | awk '($1 == 1) && ($3 == "Defl:N") { print $5 }' | uniq)

	local verbose_log=""

	if [ -n "${jar_descriptions}" ]
	then
		lc_log DEBUG "Entries that differ inside ${1} before filtering:"
		lc_log DEBUG "$(echo "${jar_descriptions}" | sed "s/^/    /")"

		if (echo "${jar_descriptions}" | grep --quiet "META-INF/MANIFEST.MF")
		then
			if (compare_property_in_packaged_file "${jar1}" "${jar2}" "META-INF/MANIFEST.MF" "Export-Package")
			then
				lc_log DEBUG "Excluding META-INF/MANIFEST.MF from ${1} because Export-Package matches in both JARs."

				jar_descriptions=$(echo "${jar_descriptions}" | sed "/META-INF\/MANIFEST.MF/d")
			else
				lc_log DEBUG "Keeping META-INF/MANIFEST.MF in ${1} because Export-Package differs (full dump deferred until JAR is confirmed added)."

				verbose_log+="
Built MANIFEST.MF (first 80 lines):
$(unzip -p "${jar1}" META-INF/MANIFEST.MF | head --lines=80 | sed "s/^/    /")
Reference MANIFEST.MF (first 80 lines):
$(unzip -p "${jar2}" META-INF/MANIFEST.MF | head --lines=80 | sed "s/^/    /")
"
			fi
		fi

		local new_jar_descriptions=""

		if (echo "${jar_descriptions}" | grep --quiet ".class")
		then
			mkdir --parents "${_BUILD_DIR}/tmp/jar1" "${_BUILD_DIR}/tmp/jar2"

			while IFS= read -r line
			do
				if (echo "$(basename ${line})" | grep --quiet ".class")
				then
					local class_file_name=$(basename "${line}")

					unzip -p "${jar1}" "${line}" > "${_BUILD_DIR}/tmp/jar1/${class_file_name}"

					javap -c -private -verbose "${_BUILD_DIR}/tmp/jar1/${class_file_name}" | tail --lines=+4 > \
						"${_BUILD_DIR}/tmp/jar1/${class_file_name}.txt"

					unzip -p "${jar2}" "${line}" > "${_BUILD_DIR}/tmp/jar2/${class_file_name}" 2>/dev/null

					javap -c -private -verbose "${_BUILD_DIR}/tmp/jar2/${class_file_name}" 2>/dev/null | tail --lines=+4 > \
						"${_BUILD_DIR}/tmp/jar2/${class_file_name}.txt"

					local diff_result=$(diff \
						"${_BUILD_DIR}/tmp/jar1/${class_file_name}.txt" \
						"${_BUILD_DIR}/tmp/jar2/${class_file_name}.txt")

					if [ -n "${diff_result}" ]
					then
						lc_log DEBUG "Class ${line} in ${1} has javap differences (full diff deferred until JAR is confirmed added)."

						verbose_log+="
Class ${line} javap diff (first 40 lines):
$(echo "${diff_result}" | head --lines=40 | sed "s/^/    /")
"

						new_jar_descriptions+="${line}"$'\n'
					else
						lc_log DEBUG "Class ${line} in ${1} is byte-different but javap output matches; ignoring."
					fi
				else
					lc_log DEBUG "Non-class entry ${line} in ${1} differs and has no content-aware filter; will mark JAR as changed."

					new_jar_descriptions+="${line}"$'\n'
				fi
			done <<< "${jar_descriptions}"

			rm --force --recursive "${_BUILD_DIR}/tmp/jar1" "${_BUILD_DIR}/tmp/jar2"
		else
			new_jar_descriptions="${jar_descriptions}"
		fi

		if [[ "${1}" == *"portal.tools.db.schema.importer.jar" ]]
		then
			while IFS= read -r line
			do
				if [ -n "${line}" ] && [[ "${line}" != *"kernel"* ]]
				then
					lc_log INFO "Changes in ${1}: "
					lc_log INFO "${new_jar_descriptions}" | sed "s/^/    /"
					lc_log INFO ""

					if [ -n "${verbose_log}" ]
					then
						lc_log DEBUG "Deep-dive details for ${1} (shown because the JAR is being added):"
						lc_log DEBUG "${verbose_log}"
					fi

					return 0
				fi
			done <<< "${new_jar_descriptions}"

			return 1
		fi

		if [ -n "${new_jar_descriptions}" ]
		then
			lc_log INFO "Changes in ${1}: "
			lc_log INFO "${new_jar_descriptions}" | sed "s/^/    /"
			lc_log INFO ""

			if [ -n "${verbose_log}" ]
			then
				lc_log DEBUG "Deep-dive details for ${1} (shown because the JAR is being added):"
				lc_log DEBUG "${verbose_log}"
			fi

			return 0
		fi
	fi

	lc_log DEBUG "No meaningful changes detected inside ${1}."

	return 1
}

function copy_release_info_date {
	local build_date=$(unzip -p "${_RELEASE_DIR}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib/portal-impl.jar" META-INF/MANIFEST.MF | grep "Liferay-Portal-Build-Date:")

	build_date=${build_date#Liferay-Portal-Build-Date: }

	lc_cd "${_PROJECTS_DIR}/liferay-portal-ee"

	sed \
		--expression "s/release.info.date=.*/release.info.date=$(date -d "${build_date}" +"%B %d, %Y")/" \
		--in-place \
		release.properties
}

function create_documentation {
	function write {
		echo -en "${1}" >> "${_BUILD_DIR}/hotfix/hotfix.json"
		echo -en "${1}"
	}

	function writeln {
		write "${1}\n"
	}

	local first_line=true

	writeln "{"
	writeln "    \"build\": {"
	writeln "        \"builder-revision\": \"${_BUILDER_SHA}\"",
	writeln "        \"date\": \"$(date)\","
	writeln "        \"git-revision\": \"${_GIT_SHA}\","
	writeln "        \"id\": \"${LIFERAY_RELEASE_HOTFIX_BUILD_ID}\""
	writeln "    },"
	writeln "    \"fixed-issues\": ["

	if [ -n "${LIFERAY_RELEASE_HOTFIX_FIXED_ISSUES}" ]
	then
		echo "${LIFERAY_RELEASE_HOTFIX_FIXED_ISSUES}" | tr ',' '\n' | while read -r line
		do
			if [ "${first_line}" = true ]
			then
				first_line=false

				write "        "
			else
				write ","
			fi

			write "\"${line}\""
		done

		writeln ""
	fi

	writeln "    ],"
	writeln "    \"patch\": {"
	writeln "        \"id\": \"${LIFERAY_RELEASE_HOTFIX_ID}\""
	writeln "    },"
	writeln "    \"requirement\": {"
	writeln "        \"patching-tool-version\": \"4000\","
	writeln "        \"product-version\": \"${_PRODUCT_VERSION}\""
	writeln "    },"
	writeln "    \"added\" :["

	first_line=true

	if [ -e "${_BUILD_DIR}"/hotfix/checksums ]
	then
		while read -r line
		do
			local checksum=${line%% *}
			local file=${line##* ./}
			if [ "${first_line}" = true ]
			then
				first_line=false
			else
				writeln ","
			fi

			writeln "        {"
			writeln "            \"path\": \"${file}\","
			writeln "            \"checksum\": \"${checksum}\""
			write "        }"
		done < "${_BUILD_DIR}"/hotfix/checksums

		writeln ""
	fi

	writeln "    ],"
	writeln "    \"removed\" :["

	if [ -e "${_BUILD_DIR}"/hotfix/removed_files ]
	then
		first_line=true

		while read -r file
		do
			if [ "${first_line}" = true ]
			then
				first_line=false
			else
				writeln ","
			fi

			writeln "        {"
			writeln "            \"path\": \"${file}\""
			write "        }"
		done < "${_BUILD_DIR}"/hotfix/removed_files

		writeln ""
	fi

	writeln "    ]"
	writeln "}"
}

function create_hotfix {
	rm --force --recursive "${_BUILD_DIR}"/hotfix

	mkdir --parents "${_BUILD_DIR}"/hotfix

	lc_log INFO "Creating hotfix by diffing the built bundle against the reference release."
	lc_log INFO "    Built bundles directory:    ${_BUNDLES_DIR}"
	lc_log INFO "    Reference release directory: ${_RELEASE_DIR}"

	local diff_output=$(diff --brief --recursive "${_BUNDLES_DIR}" "${_RELEASE_DIR}" | grep --invert-match /work/Catalina)

	local diff_count=$(echo "${diff_output}" | grep --count . || true)

	lc_log INFO "diff --brief found ${diff_count} differing entries (after stripping work/Catalina)."

	echo "${diff_output}"

	echo "${diff_output}" | while read -r change
	do
		if [ -z "${change}" ]
		then
			continue
		fi

		if (echo "${change}" | grep "^Only in ${_RELEASE_DIR}" &>/dev/null)
		then
			local removed_file=${change#Only in }

			removed_file=$(echo "${removed_file}" | sed --expression "s#: #/#" | sed --expression "s#${_RELEASE_DIR}##")
			removed_file=${removed_file#/}

			lc_log DEBUG "Detected entry only in reference release: ${removed_file}"

			if [ ! -f "${_RELEASE_DIR}/${removed_file}" ]
			then
				lc_log DEBUG "Skipping ${removed_file} because it is not a regular file."

				continue
			fi

			if in_hotfix_scope "${removed_file}"
			then
				lc_log INFO "Recording removal of ${removed_file} in the hotfix."

				transform_file_name "${removed_file}" >> "${_BUILD_DIR}"/hotfix/removed_files
			else
				lc_log DEBUG "Skipping removed ${removed_file} because it is outside the hotfix scope."
			fi
		elif (echo "${change}" | grep "^Only in ${_BUNDLES_DIR}" &>/dev/null)
		then
			local new_file=${change#Only in }

			new_file=$(echo "${new_file}" | sed --expression "s#: #/#" | sed --expression "s#${_BUNDLES_DIR}##")
			new_file=${new_file#/}

			lc_log DEBUG "Detected entry only in built bundle: ${new_file}"

			if [ ! -f "${_BUNDLES_DIR}/${new_file}" ]
			then
				lc_log DEBUG "Skipping ${new_file} because it is not a regular file."

				continue
			fi

			if in_hotfix_scope "${new_file}"
			then
				lc_log INFO "Adding new file ${new_file} to the hotfix."

				add_file_to_hotfix "${new_file}"
			else
				lc_log DEBUG "Skipping new ${new_file} because it is outside the hotfix scope."
			fi
		else
			local changed_file=${change#Files }

			changed_file=${changed_file%% *}
			changed_file=$(echo "${changed_file}" | sed --expression "s#${_BUNDLES_DIR}##")
			changed_file=${changed_file#/}

			lc_log DEBUG "Detected changed entry: ${changed_file}"

			if [ ! -f "${_BUNDLES_DIR}/${changed_file}" ]
			then
				lc_log DEBUG "Skipping ${changed_file} because it is not a regular file."

				continue
			fi

			if in_hotfix_scope "${changed_file}"
			then
				if (echo "${changed_file}" | grep --quiet ".[jw]ar$")
				then
					manage_jar "${changed_file}"
				else
					lc_log INFO "Adding changed non-JAR file ${changed_file} to the hotfix (no content-aware filter applies)."

					add_file_to_hotfix "${changed_file}"
				fi
			else
				lc_log DEBUG "Skipping changed ${changed_file} because it is outside the hotfix scope."
			fi
		fi
	done

	if [ -d "${_BUILD_DIR}/hotfix/binaries" ]
	then
		local added_count=$(find "${_BUILD_DIR}/hotfix/binaries" -type f | wc --lines)

		lc_log INFO "Hotfix now contains ${added_count} added/changed files."
	else
		lc_log INFO "Hotfix has no added/changed files."
	fi

	if [ -f "${_BUILD_DIR}/hotfix/removed_files" ]
	then
		local removed_count=$(wc --lines < "${_BUILD_DIR}/hotfix/removed_files")

		lc_log INFO "Hotfix records ${removed_count} removed files."
	fi

	rm --force --recursive "${_RELEASE_DIR}"
}

function in_hotfix_scope {
	if (echo "${1}" | grep --quiet "^glowroot/plugins")
	then
		return 0
	fi

	if (echo "${1}" | grep --quiet "^osgi/") && (! echo "${1}" | grep --quiet "^osgi/state")
	then
		return 0
	fi

	if (echo "${1}" | grep --quiet "^tomcat/lib/ext") && is_7_3_release
	then
		return 0
	fi

	if (echo "${1}" | grep --quiet "^tomcat/webapps/ROOT")
	then
		return 0
	fi

	if (echo "${1}" | grep --quiet "^tools")
	then
		return 0
	fi

	return 1
}

function manage_jar {
	lc_log INFO "Analyzing changed JAR ${1}."

	if (compare_jars "${1}")
	then
		lc_log INFO "Adding modified JAR ${1} to the hotfix."

		add_file_to_hotfix "${1}"
	else
		lc_log INFO "Skipping JAR ${1} because compare_jars found no meaningful changes."
	fi
}

function package_hotfix {
	lc_cd "${_BUILD_DIR}"/hotfix

	rm --force "../${_HOTFIX_FILE_NAME}" checksums removed_files

	zip -r "../${_HOTFIX_FILE_NAME}" ./*

	lc_cd "${_BUILD_DIR}"

	rm --force --recursive hotfix
}

function prepare_release_dir {
	trap 'return ${LIFERAY_COMMON_EXIT_CODE_BAD}' ERR

	_RELEASE_DIR="${_RELEASES_DIR}/${_PRODUCT_VERSION}"

	local release7z

	if [ -e "${_TEST_RELEASE_DIR}" ] && [ $(find "${_TEST_RELEASE_DIR}" -type f -printf "%f\n" | wc --lines) -eq 1 ]
	then
		lc_cd "${_TEST_RELEASE_DIR}"

		local release_file=$(find . -type f -printf "%f\n")

		_RELEASE_DIR="${_RELEASES_DIR}/${release_file%%.7z}"

		release7z="${_TEST_RELEASE_DIR}/${release_file}"
	fi

	if [ -e "${_RELEASE_DIR}" ]
	then
		if [ ! -e "${_RELEASE_DIR}/tomcat" ]
		then
			echo "Removing ${_RELEASE_DIR} because it does not have a Tomcat directory."

			rm --force --recursive "${_RELEASE_DIR}"
		else
			echo "${_RELEASE_DIR} is already available."

			return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
		fi
	fi

	rm --force --recursive "${_RELEASE_DIR}.tmp"

	mkdir --parents "${_RELEASE_DIR}.tmp"

	lc_cd "${_RELEASE_DIR}.tmp"

	if [ -n "${release7z}" ]
	then
		7z x "${release7z}"
	else
		lc_download "https://releases-cdn.liferay.com/dxp/${_PRODUCT_VERSION}/$(lc_curl "https://releases-cdn.liferay.com/dxp/${_PRODUCT_VERSION}/.lfrrelease-tomcat-bundle")" liferay-dxp.7z

		7z x ./liferay-dxp.7z

		rm --force ./liferay-dxp.7z
	fi

	shopt -s dotglob

	mv liferay-dxp/* .

	shopt -u dotglob

	rm --force --recursive liferay-dxp

	mv "${_RELEASE_DIR}.tmp" "${_RELEASE_DIR}"
}

function set_hotfix_name {
	_HOTFIX_FILE_NAME=liferay-dxp-${_PRODUCT_VERSION}-hotfix-"${LIFERAY_RELEASE_HOTFIX_ID}".zip
	_HOTFIX_NAME=hotfix-"${LIFERAY_RELEASE_HOTFIX_ID}"
}

function sign_hotfix {
	lc_cd "${_BUILD_DIR}"/hotfix

	if [ ! -n "${LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_FILE}" ]
	then
		lc_log INFO "Set the environment variable LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_FILE."

		return "${LIFERAY_COMMON_EXIT_CODE_SKIPPED}"
	fi

	if [ ! -e "${LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_FILE}" ]
	then
		lc_log ERROR "The environment variable LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_FILE does not point to a valid file."

		return "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	openssl dgst -passin env:LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_PASSWORD -out hotfix.sign -sha256 -sign "${LIFERAY_RELEASE_HOTFIX_SIGNATURE_KEY_FILE}" hotfix.json
}

function transform_file_name {
	local file_name=$(echo "${1}" | sed --expression "s#osgi/#OSGI_BASE_PATH/#")

	file_name=$(echo "${file_name}" | sed --expression "s#tomcat/webapps/ROOT#WAR_PATH#")

	if is_7_3_release
	then
		file_name=$(echo "${file_name}" | sed --expression "s#tomcat/lib/ext#GLOBAL_LIB_PATH#")
	fi

	echo "${file_name}"
}