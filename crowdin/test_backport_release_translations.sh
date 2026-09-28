#!/bin/bash

source ../_liferay_common.sh
source ../_test_common.sh
source ./backport_release_translations.sh

function main {
	set_up

	if [[ "${#}" -eq 1 ]]
	then
		"${1}"
	else
		test_backport_release_translations_export_master_translations
		test_backport_release_translations_not_export_master_translations
		test_backport_release_translations_set_supported_release_branches
	fi

	tear_down
}

function set_up {
	common_set_up

	export _CROWDIN_DIR=${PWD}
	export _PROJECTS_DIR=$(mktemp --directory)
	export _RELEASE_ROOT_DIR="${PWD}/../release"
}

function tear_down {
	common_tear_down

	lc_cd "${_CROWDIN_DIR}"

	rm --force --recursive "${_PROJECTS_DIR}"

	unset LIFERAY_RELEASE_TEST_DATE
	unset _CROWDIN_DIR
	unset _PROJECTS_DIR
	unset _RELEASE_ROOT_DIR
}

function test_backport_release_translations_export_master_translations {
	_test_backport_release_translations_export_master_translations \
		"modules/apps/portal-language/portal-language-lang/src/main/resources/content" \
		"Language"
	_test_backport_release_translations_export_master_translations \
		"modules/apps/test/app.bnd-localization" \
		"bundle"
}

function test_backport_release_translations_not_export_master_translations {
	local translation_dir="modules/apps/portal-language/portal-language-lang/src/main/resources/content"

	_set_up_translation_files "Copia antiga" "${translation_dir}" "Language"

	export_master_translations "release-test" &> /dev/null

	merge_and_commit_translations "LPD-105062 Backport Translations" &> /dev/null

	assert_equals "$(git log --format="%s" --max-count=1)" "Release branch"
}

function test_backport_release_translations_set_supported_release_branches {
	_set_up_release_branches

	_test_backport_release_translations_set_supported_release_branches "2028-02-18" "release-2025.q1"
	_test_backport_release_translations_set_supported_release_branches "2028-02-19" ""
}

function _set_up_release_branches {
	rm --force --recursive "${_PROJECTS_DIR}/liferay-portal-ee"

	git init --bare --quiet "${_PROJECTS_DIR}/upstream.git"

	mkdir "${_PROJECTS_DIR}/liferay-portal-ee"

	lc_cd "${_PROJECTS_DIR}/liferay-portal-ee"

	git init --quiet

	git config user.email "test@test.com"

	git config user.name "Test"

	echo "release.info.version=7.4.13" > release.properties

	git add release.properties

	git commit --message "Release branch" --quiet

	git remote add upstream "${_PROJECTS_DIR}/upstream.git"

	local release_branch

	for release_branch in release-2023.q4 release-2024.q2.10 release-2025.q1 release-2025.q2
	do
		git push --quiet upstream "HEAD:refs/heads/${release_branch}"
	done
}

function _set_up_translation_files {
	local master_copy_translation=${1}
	local translation_dir=${2}
	local translation_file_prefix=${3}

	rm --force --recursive "${_PROJECTS_DIR}/liferay-portal-ee"

	mkdir --parents "${_PROJECTS_DIR}/liferay-portal-ee/${translation_dir}"

	lc_cd "${_PROJECTS_DIR}/liferay-portal-ee"

	git init --quiet

	git config user.email "test@test.com"

	git config user.name "Test"

	echo "\
key-already=Already
key-automatic-copy=Automatic Copy
key-copy=Copy
key-english-changed=New English
key-master-only=Master Only" > "${translation_dir}/${translation_file_prefix}.properties"

	echo "\
key-already=Ja
key-automatic-copy=Automatic Copy (Automatic Copy)
key-copy=${master_copy_translation}
key-english-changed=Ingles novo
key-master-only=Somente master" > "${translation_dir}/${translation_file_prefix}_pt_BR.properties"

	git add "${translation_dir}"

	git commit --message "Master" --quiet

	git update-ref refs/remotes/upstream/master HEAD

	echo "\
key-already=Already
key-automatic-copy=Automatic Copy
key-branch-only=Branch Only
key-copy=Copy
key-english-changed=Old English" > "${translation_dir}/${translation_file_prefix}.properties"

	echo "\
key-already=Ja
key-automatic-copy=Copia automatica
key-branch-only=Somente branch
key-copy=Copia antiga
key-english-changed=Ingles antigo" > "${translation_dir}/${translation_file_prefix}_pt_BR.properties"

	git add "${translation_dir}"

	git commit --message "Release branch" --quiet
}

function _test_backport_release_translations_export_master_translations {
	local translation_dir=${1}
	local translation_file_prefix=${2}

	_set_up_translation_files "Copia nova" "${translation_dir}" "${translation_file_prefix}"

	export_master_translations "release-test" &> /dev/null

	merge_and_commit_translations "LPD-105062 Backport Translations" &> /dev/null

	echo "\
key-already=Ja
key-automatic-copy=Copia automatica
key-branch-only=Somente branch
key-copy=Copia nova
key-english-changed=Ingles antigo" > "${_PROJECTS_DIR}/expected.properties"

	assert_equals \
		"${translation_dir}/${translation_file_prefix}_pt_BR.properties" \
		"${_PROJECTS_DIR}/expected.properties"

	rm --force "${_PROJECTS_DIR}/expected.properties"
}

function _test_backport_release_translations_set_supported_release_branches {
	LIFERAY_RELEASE_TEST_DATE=${1}

	set_supported_release_branches &> /dev/null

	assert_equals "${_SUPPORTED_RELEASE_BRANCHES[*]}" "${2}"
}

main "${@}"