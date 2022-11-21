#!/bin/sh
#
# Utility tools for building configure/packages by AntPickax
#
# Copyright 2022 Yahoo Japan Corporation.
#
# AntPickax provides utility tools for supporting autotools
# builds.
#
# These tools retrieve the necessary information from the
# repository and appropriately set the setting values of
# configure, Makefile, spec,etc file and so on.
# These tools were recreated to reduce the number of fixes and
# reduce the workload of developers when there is a change in
# the project configuration.
# 
# For the full copyright and license information, please view
# the license file that was distributed with this source code.
#
# AUTHOR:   Takeshi Nakatani
# CREATE:   Fri, Feb 24 2022
# REVISION:
#

#==============================================================
# Build helper for PHP Extension on Github Actions
#==============================================================
#
# Instead of pipefail(for shells not support "set -o pipefail")
#
PIPEFAILURE_FILE="/tmp/.pipefailure.$(od -An -tu4 -N4 /dev/random | tr -d ' \n')"

#
# For shellcheck
#
if locale -a | grep -q -i '^[[:space:]]*C.utf8[[:space:]]*$'; then
	LANG=$(locale -a | grep -i '^[[:space:]]*C.utf8[[:space:]]*$' | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' | tr -d '\n')
	LC_ALL="${LANG}"
	export LANG
	export LC_ALL
elif locale -a | grep -q -i '^[[:space:]]*en_US.utf8[[:space:]]*$'; then
	LANG=$(locale -a | grep -i '^[[:space:]]*en_US.utf8[[:space:]]*$' | sed -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' | tr -d '\n')
	LC_ALL="${LANG}"
	export LANG
	export LC_ALL
fi

#==============================================================
# Common variables
#==============================================================
PRGNAME=$(basename "$0")
SCRIPTDIR=$(dirname "$0")
SCRIPTDIR=$(cd "${SCRIPTDIR}" || exit 1; pwd)
SRCTOP=$(cd "${SCRIPTDIR}"/.. || exit 1; pwd)

#
# Message variables
#
IN_GHAGROUP_AREA=0

#
# Variables with default values
#
CI_OSTYPE=""
CI_PHPTYPE=""

CI_PHPEXTTYPE_VARS_FILE="${SCRIPTDIR}/phpexttypevars.sh"
CI_BUILD_NUMBER=1
CI_DEVELOPER_FULLNAME=""
CI_DEVELOPER_EMAIL=""
CI_FORCE_PUBLISH=""
CI_USE_PACKAGECLOUD_REPO=1
CI_PACKAGECLOUD_TOKEN=""
CI_PACKAGECLOUD_OWNER="antpickax"
CI_PACKAGECLOUD_PUBLISH_REPO="current"
CI_PACKAGECLOUD_DOWNLOAD_REPO="stable"
#
CI_IN_SCHEDULE_PROCESS=0
CI_PUBLISH_TAG_NAME=""
CI_DO_PUBLISH=0

#==============================================================
# Utility functions and variables for messaging
#==============================================================
#
# Utilities for message
#
if [ -t 1 ] || { [ -n "${CI}" ] && [ "${CI}" = "true" ]; }; then
	CBLD=$(printf '\033[1m')
	CREV=$(printf '\033[7m')
	CRED=$(printf '\033[31m')
	CYEL=$(printf '\033[33m')
	CGRN=$(printf '\033[32m')
	CDEF=$(printf '\033[0m')
else
	CBLD=""
	CREV=""
	CRED=""
	CYEL=""
	CGRN=""
	CDEF=""
fi
if [ -n "${CI}" ] && [ "${CI}" = "true" ]; then
	GHAGRP_START="::group::"
	GHAGRP_END="::endgroup::"
else
	GHAGRP_START=""
	GHAGRP_END=""
fi

PRNGROUPEND()
{
	if [ -n "${IN_GHAGROUP_AREA}" ] && [ "${IN_GHAGROUP_AREA}" -eq 1 ]; then
		if [ -n "${GHAGRP_END}" ]; then
			echo "${GHAGRP_END}"
		fi
	fi
	IN_GHAGROUP_AREA=0
}
PRNTITLE()
{
	PRNGROUPEND
	echo "${GHAGRP_START}${CBLD}${CGRN}${CREV}[TITLE]${CDEF} ${CGRN}$*${CDEF}"
	IN_GHAGROUP_AREA=1
}
PRNINFO()
{
	echo "${CBLD}${CREV}[INFO]${CDEF} $*"
}
PRNWARN()
{
	echo "${CBLD}${CYEL}${CREV}[WARNING]${CDEF} ${CYEL}$*${CDEF}"
}
PRNERR()
{
	echo "${CBLD}${CRED}${CREV}[ERROR]${CDEF} ${CRED}$*${CDEF}"
	PRNGROUPEND
}
PRNSUCCESS()
{
	echo "${CBLD}${CGRN}${CREV}[SUCCEED]${CDEF} ${CGRN}$*${CDEF}"
	PRNGROUPEND
}
PRNFAILURE()
{
	echo "${CBLD}${CRED}${CREV}[FAILURE]${CDEF} ${CRED}$*${CDEF}"
	PRNGROUPEND
}
RUNCMD()
{
	PRNINFO "Run \"$*\""
	if ! /bin/sh -c "$*"; then
		PRNERR "Failed to run \"$*\""
		return 1
	fi
	return 0
}

#----------------------------------------------------------
# Helper for container on Github Actions
#----------------------------------------------------------
func_usage()
{
	echo ""
	echo "Usage: $1 [options...]"
	echo ""
	echo "  Required option:"
	echo "    --help(-h)                                             print help"
	echo "    --ostype(-os)                             <os:version> specify os and version as like \"ubuntu:jammy\""
	echo "    --phptype(-php)                           <phpXX>      specify PHP and version as like \"PHP8.1\"/\"PHP8\"/\"8.1\"/\"8\""
	echo ""
	echo "  Option:"
	echo "    --phpexttype-vars-file(-f)                <file path>  specify the file that describes the package list to be installed before build(default is phpexttypevars.sh)"
	echo "    --force-publish(-p)                                    force the release package to be uploaded. normally the package is uploaded only when it is tagged(determined from GITHUB_REF/GITHUB_EVENT_NAME)."
	echo "    --not-publish(-np)                                     do not force publish the release package."
	echo "    --build-number(-num)                      <number>     build number for packaging(default 1)"
	echo "    --developer-fullname(-devname)            <string>     specify developer name for debian and ubuntu packaging(default is null, it is specified in configure.ac)"
	echo "    --developer-email(-devmail)               <string>     specify developer e-mail for debian and ubuntu packaging(default is null, it is specified in configure.ac)"
	echo ""
	echo "  Option for packagecloud.io:"
	echo "    --use-packagecloudio-repo(-usepc)                      use packagecloud.io repository(default), exclusive -notpc option"
	echo "    --not-use-packagecloudio-repo(-notpc)                  not use packagecloud.io repository, exclusive -usepc option"
	echo "    --packagecloudio-token(-pctoken)          <token>      packagecloud.io token for uploading(specify when uploading)"
	echo "    --packagecloudio-owner(-pcowner)          <owner>      owner name of uploading destination to packagecloud.io, this is part of the repository path(default is antpickax)"
	echo "    --packagecloudio-publish-repo(-pcprepo)   <repository> repository name of uploading destination to packagecloud.io, this is part of the repository path(default is current)"
	echo "    --packagecloudio-download-repo(-pcdlrepo) <repository> repository name of installing packages in packagecloud.io, this is part of the repository path(default is stable)"
	echo ""
	echo "  Environments:"
	echo "    ENV_PHPEXTTYPE_VARS_FILE                  the file that describes the package list                  ( same as option '--phpexttype-vars-file(-f)' )"
	echo "    ENV_BUILD_NUMBER                          build number                                              ( same as option '--build-number(-num)' )"
	echo "    ENV_DEVELOPER_FULLNAME                    developer name                                            ( same as option '--developer-fullname(-devname)' )"
	echo "    ENV_DEVELOPER_EMAIL                       developer e-mail                                          ( same as option '--developer-email(-devmail)' )"
	echo "    ENV_FORCE_PUBLISH                         force the release package to be uploaded: true/false      ( same as option '--force-publish(-p)' and '--not-publish(-np)' )"
	echo "    ENV_USE_PACKAGECLOUD_REPO                 use packagecloud.io repository: true/false                ( same as option '--use-packagecloudio-repo(-usepc)' and '--not-use-packagecloudio-repo(-notpc)' )"
	echo "    ENV_PACKAGECLOUD_TOKEN                    packagecloud.io token                                     ( same as option '--packagecloudio-token(-pctoken)' )"
	echo "    ENV_PACKAGECLOUD_OWNER                    owner name for uploading to packagecloud.io               ( same as option '--packagecloudio-owner(-pcowner)' )"
	echo "    ENV_PACKAGECLOUD_PUBLISH_REPO             repository name of uploading to packagecloud.io           ( same as option '--packagecloudio-publish-repo(-pcprepo)' )"
	echo "    ENV_PACKAGECLOUD_DOWNLOAD_REPO            repository name of installing packages in packagecloud.io ( same as option '--packagecloudio-download-repo(-pcdlrepo)' )"
	echo "    GITHUB_REF                                use internally for release tag"
	echo "    GITHUB_EVENT_NAME                         use internally for checking schedule processing"
	echo ""
	echo "  Note:"
	echo "    Environment variables and options have the same parameter items."
	echo "    If both are specified, the option takes precedence."
	echo "    Environment variables are set from Github Actions Secrets, etc."
	echo "    GITHUB_REF and GITHUB_EVENT_NAME environments are used internally."
	echo ""
}

#==============================================================
# Default execution functions and variables
#==============================================================
#
# Execution flag ( default is for PHP Extension )
#
RUN_PRE_CONFIG=1
RUN_CONFIG=1
RUN_PRE_CLEANUP=1
RUN_CLEANUP=1
RUN_POST_CLEANUP=0
RUN_CPPCHECK=1
RUN_SHELLCHECK=1
RUN_CHECK_OTHER=0
RUN_PRE_BUILD=0
RUN_BUILD=1
RUN_POST_BUILD=0
RUN_PRE_TEST=0
RUN_TEST=1
RUN_POST_TEST=0
RUN_PRE_PACKAGE=0
RUN_PACKAGE=1
RUN_POST_PACKAGE=0
RUN_PUBLISH_PACKAGE=1

#
# Before configuration
#
run_pre_configuration()
{
	if ! /bin/sh -c "${SWITCH_PHP_COMMAND} phpize"; then
		PRNERR "Failed to run \"phpize\" before configration."
		return 1
	fi
	return 0
}

#
# Configuration
#
run_configuration()
{
	if ! /bin/sh -c "${SWITCH_PHP_COMMAND} ./configure"; then
		PRNERR "Failed to run \"configure\"."
		return 1
	fi
	return 0
}

#
# Before Cleanup
#
run_pre_cleanup()
{
	if [ -n "${PRE_CLEANUP_FILES_DIRS}" ]; then
		# shellcheck disable=SC2086
		rm -rf ${_CLEANUP_FILES_DIRS}
	else
		PRNINFO "Nothing to cleanup files or directories."
	fi
	return 0
}

#
# Cleanup
#
run_cleanup()
{
	if ! /bin/sh -c "${SWITCH_PHP_COMMAND} make clean"; then
		PRNWARN "Failed to run \"make clean\", but continue because this command is failed if there is no Makefile."
	fi
	return 0
}

#
# After Cleanup
#
run_post_cleanup()
{
	PRNWARN "Not implement process after cleanup."
	return 0
}

#
# Check before building : CppCheck
#
run_cppcheck()
{
	#
	# Targets
	#
	if [ -z "${CPPCHECK_TARGET}" ]; then
		PRNERR "Failed to run \"cppcheck\", target files/dirs is not specified."
		return 1
	fi

	CPPCHECK_ENABLE_OPT=""
	for _one_opt in ${CPPCHECK_ENABLE_VALUES}; do
		if [ -n "${_one_opt}" ]; then
			if [ -z "${CPPCHECK_ENABLE_OPT}" ]; then
				CPPCHECK_ENABLE_OPT="--enable="
			else
				CPPCHECK_ENABLE_OPT="${CPPCHECK_ENABLE_OPT},"
			fi
			CPPCHECK_ENABLE_OPT="${CPPCHECK_ENABLE_OPT}${_one_opt}"
		fi
	done

	CPPCHECK_IGNORE_OPT=""
	for _one_opt in ${CPPCHECK_IGNORE_VALUES}; do
		if [ -n "${_one_opt}" ]; then
			CPPCHECK_IGNORE_OPT="${CPPCHECK_IGNORE_OPT} --suppress=${_one_opt}"
		fi
	done

	CPPCHECK_BUILD_DIR_OPT=""
	if [ -n "${CPPCHECK_BUILD_DIR}" ]; then
		rm -rf "${CPPCHECK_BUILD_DIR}"
		if ! mkdir -p "${CPPCHECK_BUILD_DIR}"; then
			PRNERR "Failed to run \"cppcheck\", could not create ${CPPCHECK_BUILD_DIR} directory."
			return 1
		fi
		CPPCHECK_BUILD_DIR_OPT="--cppcheck-build-dir=${CPPCHECK_BUILD_DIR}"
	fi

	if ! /bin/sh -c "cppcheck ${CPPCHECK_BASE_OPT} ${CPPCHECK_ENABLE_OPT} ${CPPCHECK_IGNORE_OPT} ${CPPCHECK_BUILD_DIR_OPT} ${CPPCHECK_TARGET}"; then
		PRNERR "Failed to run \"cppcheck\"."
		return 1
	fi
	return 0
}

#
# Check before building : ShellCheck
#
run_shellcheck()
{
	#
	# Targets
	#
	if [ -z "${SHELLCHECK_TARGET_DIRS}" ]; then
		PRNERR "Failed to run \"shellcheck\", target files/dirs is not specified."
		return 1
	fi

	SHELLCHECK_TARGET_DIRS_OPT=""
	for _one_dir in ${SHELLCHECK_TARGET_DIRS}; do
		if [ -z "${SHELLCHECK_TARGET_DIRS_OPT}" ]; then
			SHELLCHECK_TARGET_DIRS_OPT="${_one_dir}"
		else
			SHELLCHECK_TARGET_DIRS_OPT="${SHELLCHECK_TARGET_DIRS_OPT} ${_one_dir}"
		fi
	done

	#
	# Exclude options
	#
	SHELLCHECK_IGN_OPT=""
	for _one_opt in ${SHELLCHECK_IGN}; do
		if [ -n "${_one_opt}" ]; then
			if [ -z "${SHELLCHECK_IGN_OPT}" ]; then
				SHELLCHECK_IGN_OPT="--exclude="
			else
				SHELLCHECK_IGN_OPT="${SHELLCHECK_IGN_OPT},"
			fi
			SHELLCHECK_IGN_OPT="${SHELLCHECK_IGN_OPT}${_one_opt}"
		fi
	done

	SHELLCHECK_INCLUDE_IGN_OPT="${SHELLCHECK_IGN_OPT}"
	for _one_opt in ${SHELLCHECK_INCLUDE_IGN}; do
		if [ -n "${_one_opt}" ]; then
			if [ -z "${SHELLCHECK_INCLUDE_IGN_OPT}" ]; then
				SHELLCHECK_INCLUDE_IGN_OPT="--exclude="
			else
				SHELLCHECK_INCLUDE_IGN_OPT="${SHELLCHECK_INCLUDE_IGN_OPT},"
			fi
			SHELLCHECK_INCLUDE_IGN_OPT="${SHELLCHECK_INCLUDE_IGN_OPT}${_one_opt}"
		fi
	done

	#
	# Target file selection
	#
	# [NOTE]
	# SHELLCHECK_FILES_NO_SH		: Script files with file extension not ".sh" but with "#!<shell command>"
	# SHELLCHECK_FILES_SH			: Script files with file extension ".sh" and "#!<shell command>"
	# SHELLCHECK_FILES_INCLUDE_SH	: Files included in script files with file extension ".sh" but without "#!<shell command>"
	#
	SHELLCHECK_EXCEPT_PATHS_CMD="| grep -v '\.sh.' | grep -v '\.log' | grep -v '\.git/'"
	for _one_path in ${SHELLCHECK_EXCEPT_PATHS}; do
		SHELLCHECK_EXCEPT_PATHS_CMD="${SHELLCHECK_EXCEPT_PATHS_CMD} | grep -v '${_one_path}'"
	done

	SHELLCHECK_FILES_NO_SH="$(/bin/sh -c      "grep -ril '^\#!/bin/sh' ${SHELLCHECK_TARGET_DIRS} | grep -v '\.sh' ${SHELLCHECK_EXCEPT_PATHS_CMD} | tr '\n' ' '")"
	SHELLCHECK_FILES_SH="$(/bin/sh -c         "grep -ril '^\#!/bin/sh' ${SHELLCHECK_TARGET_DIRS} | grep '\.sh'    ${SHELLCHECK_EXCEPT_PATHS_CMD} | tr '\n' ' '")"
	SHELLCHECK_FILES_INCLUDE_SH="$(/bin/sh -c "grep -Lir '^\#!/bin/sh' ${SHELLCHECK_TARGET_DIRS} | grep '\.sh'    ${SHELLCHECK_EXCEPT_PATHS_CMD} | tr '\n' ' '")"

	#
	# Check scripts
	#
	_SHELLCHECK_ERROR=0
	if [ -n "${SHELLCHECK_FILES_NO_SH}" ]; then
		if ! /bin/sh -c "shellcheck ${SHELLCHECK_BASE_OPT} ${SHELLCHECK_IGN_OPT} ${SHELLCHECK_FILES_NO_SH}"; then
			_SHELLCHECK_ERROR=1
		fi
	fi
	if [ -n "${SHELLCHECK_FILES_SH}" ]; then
		if ! /bin/sh -c "shellcheck ${SHELLCHECK_BASE_OPT} ${SHELLCHECK_IGN_OPT} ${SHELLCHECK_FILES_SH}"; then
			_SHELLCHECK_ERROR=1
		fi
	fi
	if [ -n "${SHELLCHECK_FILES_INCLUDE_SH}" ]; then
		if ! /bin/sh -c "shellcheck ${SHELLCHECK_BASE_OPT} ${SHELLCHECK_INCLUDE_IGN_OPT} ${SHELLCHECK_FILES_INCLUDE_SH}"; then
			_SHELLCHECK_ERROR=1
		fi
	fi

	if [ "${_SHELLCHECK_ERROR}" -ne 0 ]; then
		PRNERR "Failed to run \"shellcheck\"."
		return 1
	fi
	return 0
}

#
# Check before building : Other
#
run_othercheck()
{
	PRNWARN "Not implement other check before building."
	return 0
}

#
# Before Build
#
run_pre_build()
{
	PRNWARN "Not implement process before building."
	return 0
}

#
# Build
#
run_build()
{
	if ! /bin/sh -c "${SWITCH_PHP_COMMAND} make ${BUILD_MAKE_EXT_OPT}"; then
		PRNERR "Failed to run \"make\"."
		return 1
	fi
	return 0
}

#
# After Build
#
run_post_build()
{
	PRNWARN "Not implement process after building."
	return 0
}

#
# Before Test
#
run_pre_test()
{
	PRNWARN "Not implement process before testing."
	return 0
}

#
# Test
#
run_test()
{
	if ! /bin/sh -c "${SWITCH_PHP_COMMAND} make ${MAKE_TEST_OPT}"; then
		PRNERR "Failed to run \"make ${MAKE_TEST_OPT} ${MAKE_TEST_EXT_OPT}\"."
		return 1
	fi
	return 0
}

#
# After Test
#
run_post_test()
{
	PRNWARN "Not implement process after testing."
	return 0
}

#
# Before Create Package
#
run_pre_create_package()
{
	PRNWARN "Not implement process before packaging."
	return 0
}

#
# Create Package
#
run_create_package()
{
	if ! RUN_AS_SUBPROCESS="true" /bin/sh -c "${SWITCH_PHP_COMMAND} ${CREATE_PACKAGE_TOOL} ${CREATE_PACKAGE_TOOL_OPT_AUTO} --buildnum ${CI_BUILD_NUMBER} ${CREATE_PACKAGE_TOOL_OPT}"; then
		PRNERR "Failed to create debian type packages"
		return 1
	fi
	return 0
}

#
# After Create Package
#
run_post_create_package()
{
	PRNWARN "Not implement process after packaging."
	return 0
}

#
# Publish Package
#
run_publish_package()
{
	if [ "${CI_DO_PUBLISH}" -eq 1 ]; then
		if [ -z "${CI_PACKAGECLOUD_TOKEN}" ]; then
			PRNERR "Token for uploading to packagecloud.io is not specified."
			return 1
		fi
		if ! PACKAGECLOUD_TOKEN="${CI_PACKAGECLOUD_TOKEN}" /bin/sh -c "package_cloud push ${CI_PACKAGECLOUD_OWNER}/${CI_PACKAGECLOUD_PUBLISH_REPO}/${DIST_TAG} ${SRCTOP}${PKG_OUTPUT_DIR}/*.${PKG_EXT}"; then
			PRNERR "Failed to publish *.${PKG_EXT} packages to ${CI_PACKAGECLOUD_OWNER}/${CI_PACKAGECLOUD_PUBLISH_REPO}/${DIST_TAG}"
			return 1
		fi
	else
		PRNINFO "Not need to publish packages"
	fi
	return 0
}

#==============================================================
# Check options and environments
#==============================================================
PRNTITLE "Start to check options and environments"

#
# Parse options
#
OPT_OSTYPE=""
OPT_PHPTYPE=""
OPT_PHPEXTTYPE_VARS_FILE=""
OPT_BUILD_NUMBER=
OPT_DEVELOPER_FULLNAME=""
OPT_DEVELOPER_EMAIL=""
OPT_FORCE_PUBLISH=""
OPT_USE_PACKAGECLOUD_REPO=
OPT_PACKAGECLOUD_TOKEN=""
OPT_PACKAGECLOUD_OWNER=""
OPT_PACKAGECLOUD_PUBLISH_REPO=""
OPT_PACKAGECLOUD_DOWNLOAD_REPO=""

while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break

	elif [ "$1" = "-h" ] || [ "$1" = "-H" ] || [ "$1" = "--help" ] || [ "$1" = "--HELP" ]; then
		func_usage "${PRGNAME}"
		exit 0

	elif [ "$1" = "-os" ] || [ "$1" = "-OS" ] || [ "$1" = "--ostype" ] || [ "$1" = "--OSTYPE" ]; then
		if [ -n "${OPT_OSTYPE}" ]; then
			PRNERR "already set \"--ostype(-os)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--ostype(-os)\" option is specified without parameter."
			exit 1
		fi
		OPT_OSTYPE="$1"

	elif [ "$1" = "-php" ] || [ "$1" = "-PHP" ] || [ "$1" = "--phptype" ] || [ "$1" = "--PHPTYPE" ]; then
		if [ -n "${OPT_PHPTYPE}" ]; then
			PRNERR "already set \"--phptype(-php)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--phptype(-php)\" option is specified without parameter."
			exit 1
		fi
		OPT_PHPTYPE="$1"

	elif [ "$1" = "-f" ] || [ "$1" = "-F" ] || [ "$1" = "--phpexttype-vars-file" ] || [ "$1" = "--PHPEXTTYPE-VARS-FILE" ]; then
		if [ -n "${OPT_PHPEXTTYPE_VARS_FILE}" ]; then
			PRNERR "already set \"--phpexttype-vars-file(-f)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--phpexttype-vars-file(-f)\" option is specified without parameter."
			exit 1
		fi
		if [ ! -f "$1" ]; then
			PRNERR "$1 file is not existed, it is specified \"--phpexttype-vars-file(-f)\" option."
			exit 1
		fi
		OPT_PHPEXTTYPE_VARS_FILE="$1"

	elif [ "$1" = "-p" ] || [ "$1" = "-P" ] || [ "$1" = "--force-publish" ] || [ "$1" = "--FORCE-PUBLISH" ]; then
		if [ -n "${OPT_FORCE_PUBLISH}" ]; then
			PRNERR "already set \"--force-publish(-p)\" or \"--not-publish(-np)\" option."
			exit 1
		fi
		OPT_FORCE_PUBLISH="true"

	elif [ "$1" = "-np" ] || [ "$1" = "-NP" ] || [ "$1" = "--not-publish" ] || [ "$1" = "--NOT-PUBLISH" ]; then
		if [ -n "${OPT_FORCE_PUBLISH}" ]; then
			PRNERR "already set \"--force-publish(-p)\" or \"--not-publish(-np)\" option."
			exit 1
		fi
		OPT_FORCE_PUBLISH="false"

	elif [ "$1" = "-num" ] || [ "$1" = "-NUM" ] || [ "$1" = "--build-number" ] || [ "$1" = "--BUILD-NUMBER" ]; then
		if [ -n "${OPT_BUILD_NUMBER}" ]; then
			PRNERR "already set \"--build-number(-num)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--build-number(-num)\" option is specified without parameter."
			exit 1
		fi
		if echo "$1" | grep -q '[^0-9]'; then
			PRNERR "\"--build-number(-num)\" option specify with positive NUMBER parameter."
			exit 1
		fi
		OPT_BUILD_NUMBER="$1"

	elif [ "$1" = "-devname" ] || [ "$1" = "-DEVNAME" ] || [ "$1" = "--developer-fullname" ] || [ "$1" = "--DEVELOPER-FULLNAME" ]; then
		if [ -n "${OPT_DEVELOPER_EMAIL}" ]; then
			PRNERR "already set \"--developer-fullname(-devname)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--developer-fullname(-devname)\" option is specified without parameter."
			exit 1
		fi
		OPT_DEVELOPER_EMAIL="$1"

	elif [ "$1" = "-devmail" ] || [ "$1" = "-DEVMAIL" ] || [ "$1" = "--developer-email" ] || [ "$1" = "--DEVELOPER-EMAIL" ]; then
		if [ -n "${OPT_DEVELOPER_FULLNAME}" ]; then
			PRNERR "already set \"--developer-email(-devmail)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--developer-email(-devmail)\" option is specified without parameter."
			exit 1
		fi
		OPT_DEVELOPER_FULLNAME="$1"

	elif [ "$1" = "-usepc" ] || [ "$1" = "-USEPC" ] || [ "$1" = "--use-packagecloudio-repo" ] || [ "$1" = "--USE-PACKAGECLOUDIO-REPO" ]; then
		if [ -n "${OPT_USE_PACKAGECLOUD_REPO}" ]; then
			PRNERR "already set \"--use-packagecloudio-repo(-usepc)\" or \"--not-use-packagecloudio-repo(-notpc)\" option."
			exit 1
		fi
		OPT_USE_PACKAGECLOUD_REPO=1

	elif [ "$1" = "-notpc" ] || [ "$1" = "-NOTPC" ] || [ "$1" = "--not-use-packagecloudio-repo" ] || [ "$1" = "--NOT-USE-PACKAGECLOUDIO-REPO" ]; then
		if [ -n "${OPT_USE_PACKAGECLOUD_REPO}" ]; then
			PRNERR "already set \"--use-packagecloudio-repo(-usepc)\" or \"--not-use-packagecloudio-repo(-notpc)\" option."
			exit 1
		fi
		OPT_USE_PACKAGECLOUD_REPO=0

	elif [ "$1" = "-pctoken" ] || [ "$1" = "-PCTOKEN" ] || [ "$1" = "--packagecloudio-token" ] || [ "$1" = "--PACKAGECLOUDIO-TOKEN" ]; then
		if [ -n "${OPT_PACKAGECLOUD_TOKEN}" ]; then
			PRNERR "already set \"--packagecloudio-token(-pctoken)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--packagecloudio-token(-pctoken)\" option is specified without parameter."
			exit 1
		fi
		OPT_PACKAGECLOUD_TOKEN="$1"

	elif [ "$1" = "-pcowner" ] || [ "$1" = "-PCOWNER" ] || [ "$1" = "--packagecloudio-owner" ] || [ "$1" = "--PACKAGECLOUDIO-OWNER" ]; then
		if [ -n "${OPT_PACKAGECLOUD_OWNER}" ]; then
			PRNERR "already set \"--packagecloudio-owner(-pcowner)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--packagecloudio-owner(-pcowner)\" option is specified without parameter."
			exit 1
		fi
		OPT_PACKAGECLOUD_OWNER="$1"

	elif [ "$1" = "-pcprepo" ] || [ "$1" = "-PCPREPO" ] || [ "$1" = "--packagecloudio-publish-repo" ] || [ "$1" = "--PACKAGECLOUDIO-PUBLICH-REPO" ]; then
		if [ -n "${OPT_PACKAGECLOUD_PUBLISH_REPO}" ]; then
			PRNERR "already set \"--packagecloudio-publish-repo(-pcprepo)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--packagecloudio-publish-repo(-pcprepo)\" option is specified without parameter."
			exit 1
		fi
		OPT_PACKAGECLOUD_PUBLISH_REPO="$1"

	elif [ "$1" = "-pcdlrepo" ] || [ "$1" = "-PCDLREPO" ] || [ "$1" = "--packagecloudio-download-repo" ] || [ "$1" = "--PACKAGECLOUDIO-DOWNLOAD-REPO" ]; then
		if [ -n "${OPT_PACKAGECLOUD_DOWNLOAD_REPO}" ]; then
			PRNERR "already set \"--packagecloudio-download-repo(-pcdlrepo)\" option."
			exit 1
		fi
		shift
		if [ $# -eq 0 ]; then
			PRNERR "\"--packagecloudio-download-repo(-pcdlrepo)\" option is specified without parameter."
			exit 1
		fi
		OPT_PACKAGECLOUD_DOWNLOAD_REPO="$1"
	fi
	shift
done

#
# [Required option] check OS and version
#
if [ -z "${OPT_OSTYPE}" ]; then
	PRNERR "\"--ostype(-os)\" option is not specified."
	exit 1
else
	CI_OSTYPE="${OPT_OSTYPE}"
fi
if [ -z "${OPT_PHPTYPE}" ]; then
	PRNERR "\"--phptype(-php)\" option is not specified."
	exit 1
else
	CI_PHPTYPE="${OPT_PHPTYPE}"
fi

#
# Check other options and enviroments
#
if [ -n "${OPT_PHPEXTTYPE_VARS_FILE}" ]; then
	CI_PHPEXTTYPE_VARS_FILE="${OPT_PHPEXTTYPE_VARS_FILE}"
elif [ -n "${ENV_PHPEXTTYPE_VARS_FILE}" ]; then
	CI_PHPEXTTYPE_VARS_FILE="${ENV_PHPEXTTYPE_VARS_FILE}"
fi

if [ -n "${OPT_BUILD_NUMBER}" ]; then
	CI_BUILD_NUMBER="${OPT_BUILD_NUMBER}"
elif [ -n "${ENV_BUILD_NUMBER}" ]; then
	CI_BUILD_NUMBER="${ENV_BUILD_NUMBER}"
fi

if [ -n "${OPT_DEVELOPER_FULLNAME}" ]; then
	CI_DEVELOPER_FULLNAME="${OPT_DEVELOPER_FULLNAME}"
elif [ -n "${ENV_DEVELOPER_FULLNAME}" ]; then
	CI_DEVELOPER_FULLNAME="${ENV_DEVELOPER_FULLNAME}"
fi

if [ -n "${OPT_DEVELOPER_EMAIL}" ]; then
	CI_DEVELOPER_EMAIL="${OPT_DEVELOPER_EMAIL}"
elif [ -n "${ENV_DEVELOPER_EMAIL}" ]; then
	CI_DEVELOPER_EMAIL="${ENV_DEVELOPER_EMAIL}"
fi

if [ -n "${OPT_FORCE_PUBLISH}" ]; then
	if echo "${OPT_FORCE_PUBLISH}" | grep -q -i '^true$'; then
		CI_FORCE_PUBLISH="true"
	elif echo "${OPT_FORCE_PUBLISH}" | grep -q -i '^false$'; then
		CI_FORCE_PUBLISH="false"
	else
		PRNERR "\"OPT_FORCE_PUBLISH\" value is wrong."
		exit 1
	fi
elif [ -n "${ENV_FORCE_PUBLISH}" ]; then
	if echo "${ENV_FORCE_PUBLISH}" | grep -q -i '^true$'; then
		CI_FORCE_PUBLISH="true"
	elif echo "${ENV_FORCE_PUBLISH}" | grep -q -i '^false$'; then
		CI_FORCE_PUBLISH="false"
	else
		PRNERR "\"ENV_FORCE_PUBLISH\" value is wrong."
		exit 1
	fi
fi

if [ -n "${OPT_USE_PACKAGECLOUD_REPO}" ]; then
	if [ "${OPT_USE_PACKAGECLOUD_REPO}" -eq 1 ]; then
		CI_USE_PACKAGECLOUD_REPO=1
	elif [ "${OPT_USE_PACKAGECLOUD_REPO}" -eq 0 ]; then
		CI_USE_PACKAGECLOUD_REPO=0
	else
		PRNERR "\"OPT_USE_PACKAGECLOUD_REPO\" value is wrong."
		exit 1
	fi
elif [ -n "${ENV_USE_PACKAGECLOUD_REPO}" ]; then
	if echo "${ENV_USE_PACKAGECLOUD_REPO}" | grep -q -i '^true$'; then
		CI_USE_PACKAGECLOUD_REPO=1
	elif echo "${ENV_USE_PACKAGECLOUD_REPO}" | grep -q -i '^false$'; then
		CI_USE_PACKAGECLOUD_REPO=0
	else
		PRNERR "\"ENV_USE_PACKAGECLOUD_REPO\" value is wrong."
		exit 1
	fi
fi

if [ -n "${OPT_PACKAGECLOUD_TOKEN}" ]; then
	CI_PACKAGECLOUD_TOKEN="${OPT_PACKAGECLOUD_TOKEN}"
elif [ -n "${ENV_PACKAGECLOUD_TOKEN}" ]; then
	CI_PACKAGECLOUD_TOKEN="${ENV_PACKAGECLOUD_TOKEN}"
fi

if [ -n "${OPT_PACKAGECLOUD_OWNER}" ]; then
	CI_PACKAGECLOUD_OWNER="${OPT_PACKAGECLOUD_OWNER}"
elif [ -n "${ENV_PACKAGECLOUD_OWNER}" ]; then
	CI_PACKAGECLOUD_OWNER="${ENV_PACKAGECLOUD_OWNER}"
fi

if [ -n "${OPT_PACKAGECLOUD_PUBLISH_REPO}" ]; then
	CI_PACKAGECLOUD_PUBLISH_REPO="${OPT_PACKAGECLOUD_PUBLISH_REPO}"
elif [ -n "${ENV_PACKAGECLOUD_PUBLISH_REPO}" ]; then
	CI_PACKAGECLOUD_PUBLISH_REPO="${ENV_PACKAGECLOUD_PUBLISH_REPO}"
fi

if [ -n "${OPT_PACKAGECLOUD_DOWNLOAD_REPO}" ]; then
	CI_PACKAGECLOUD_DOWNLOAD_REPO="${OPT_PACKAGECLOUD_DOWNLOAD_REPO}"
elif [ -n "${ENV_PACKAGECLOUD_DOWNLOAD_REPO}" ]; then
	CI_PACKAGECLOUD_DOWNLOAD_REPO="${ENV_PACKAGECLOUD_DOWNLOAD_REPO}"
fi

#
# Set environments for debian package
#
if [ -n "${CI_DEVELOPER_FULLNAME}" ]; then
	export DEBEMAIL="${CI_DEVELOPER_FULLNAME}"
fi
if [ -n "${CI_DEVELOPER_EMAIL}" ]; then
	export DEBFULLNAME="${CI_DEVELOPER_EMAIL}"
fi

# [NOTE] for ubuntu/debian
# When start to update, it may come across an unexpected interactive interface.
# (May occur with time zone updates)
# Set environment variables to avoid this.
#
export DEBIAN_FRONTEND=noninteractive

PRNSUCCESS "Start to check options and environments"


#==============================================================
# Set Variables
#==============================================================
#
# Default command parameters for each phase
#
PRE_CLEANUP_FILES_DIRS=""

CPPCHECK_TARGET="."
CPPCHECK_BASE_OPT="--quiet --error-exitcode=1 --inline-suppr -j 4 --std=c++03 --xml --enable=warning,style,information,missingInclude"
CPPCHECK_ENABLE_VALUES="warning style information missingInclude"
CPPCHECK_IGNORE_VALUES="missingIncludeSystem unmatchedSuppression"
CPPCHECK_BUILD_DIR="/tmp/cppcheck"

SHELLCHECK_TARGET_DIRS="."
SHELLCHECK_BASE_OPT="--shell=sh"
SHELLCHECK_EXCEPT_PATHS=".libs/ autom4te.cache/ build/ debian_build/ rpmbuild/ include/ modules/ packages/ run-tests.php"
SHELLCHECK_IGN="SC1117 SC1090 SC1091"
SHELLCHECK_INCLUDE_IGN="SC2034 SC2148"

BUILD_MAKE_EXT_OPT_RPM=""
BUILD_MAKE_EXT_OPT_DEBIAN=""
BUILD_MAKE_EXT_OPT_ALPINE=""
BUILD_MAKE_EXT_OPT_OTHER=""

MAKE_TEST_OPT_RPM="test"
MAKE_TEST_OPT_DEBIAN="test"
MAKE_TEST_OPT_ALPINE="test"
MAKE_TEST_OPT_OTHER="test"

CREATE_PACKAGE_TOOL_RPM="buildutils/php_rpm_build.sh"
CREATE_PACKAGE_TOOL_DEBIAN="buildutils/php_debian_build.sh"
CREATE_PACKAGE_TOOL_ALPINE="buildutils/php_apline_build.sh"
CREATE_PACKAGE_TOOL_OTHER=""

CREATE_PACKAGE_TOOL_OPT_AUTO="-y"
CREATE_PACKAGE_TOOL_OPT_RPM=""
CREATE_PACKAGE_TOOL_OPT_DEBIAN=""
CREATE_PACKAGE_TOOL_OPT_ALPINE=""
CREATE_PACKAGE_TOOL_OPT_OTHER=""

#
# Load variables from file
#
PRNTITLE "Load local variables with an external file"

#
# Load external variable file
#
if [ -f "${CI_PHPEXTTYPE_VARS_FILE}" ]; then
	PRNINFO "Load ${CI_PHPEXTTYPE_VARS_FILE} file for local variables by os:type(${CI_OSTYPE}) php:type(${CI_PHPTYPE})"
	. "${CI_PHPEXTTYPE_VARS_FILE}"
else
	PRNWARN "${CI_PHPEXTTYPE_VARS_FILE} file is not existed."
fi

#
# Check loading variables
#
if [ -z "${DIST_TAG}" ]; then
	PRNERR "Distro/Version is not set, please check ${CI_PHPEXTTYPE_VARS_FILE} and check \"DIST_TAG\" varibale."
	exit 1
fi

#
# Set command parameters
#
if [ "${IS_OS_UBUNTU}" -eq 1 ]; then
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_DEBIAN}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_DEBIAN}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_DEBIAN}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_DEBIAN}"

elif [ "${IS_OS_DEBIAN}" -eq 1 ]; then
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_DEBIAN}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_DEBIAN}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_DEBIAN}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_DEBIAN}"

elif [ "${IS_OS_CENTOS}" -eq 1 ]; then
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_DEBIAN}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_DEBIAN}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_RPM}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_RPM}"

elif [ "${IS_OS_FEDORA}" -eq 1 ]; then
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_RPM}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_RPM}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_RPM}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_RPM}"

elif [ "${IS_OS_ROCKY}" -eq 1 ]; then
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_RPM}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_RPM}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_RPM}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_RPM}"

elif [ "${IS_OS_ALPINE}" -eq 1 ]; then
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_ALPINE}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_ALPINE}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_ALPINE}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_ALPINE}"

else
	BUILD_MAKE_EXT_OPT="${BUILD_MAKE_EXT_OPT_OTHER}"
	MAKE_TEST_OPT="${MAKE_TEST_OPT_OTHER}"
	CREATE_PACKAGE_TOOL="${CREATE_PACKAGE_TOOL_OTHER}"
	CREATE_PACKAGE_TOOL_OPT="${CREATE_PACKAGE_TOOL_OPT_OTHER}"
fi

PRNSUCCESS "Load local variables with an external file"


#----------------------------------------------------------
# Check github actions environments
#----------------------------------------------------------
PRNTITLE "Check github actions environments"

#
# GITHUB_EVENT_NAME Environment
#
if [ -n "${GITHUB_EVENT_NAME}" ] && [ "${GITHUB_EVENT_NAME}" = "schedule" ]; then
	CI_IN_SCHEDULE_PROCESS=1
else
	CI_IN_SCHEDULE_PROCESS=0
fi

#
# GITHUB_REF Environments
#
if [ -n "${GITHUB_REF}" ] && echo "${GITHUB_REF}" | grep -q 'refs/tags/'; then
	CI_PUBLISH_TAG_NAME=$(echo "${GITHUB_REF}" | sed -e 's#refs/tags/##g' | tr -d '\n')
fi

PRNSUCCESS "Check github actions environments"

#----------------------------------------------------------
# Check whether to publish
#----------------------------------------------------------
PRNTITLE "Check whether to publish"

#
# Check whether to publish
#
if [ -z "${CI_FORCE_PUBLISH}" ]; then
	if [ -n "${CI_PUBLISH_TAG_NAME}" ] && [ "${CI_IN_SCHEDULE_PROCESS}" -ne 1 ]; then
		CI_DO_PUBLISH=1
	else
		CI_DO_PUBLISH=0
	fi
elif [ "${CI_FORCE_PUBLISH}" = "true" ]; then
	#
	# Force publishing
	#
	if [ -n "${CI_PUBLISH_TAG_NAME}" ] && [ "${CI_IN_SCHEDULE_PROCESS}" -ne 1 ]; then
		PRNINFO "specified \"--force-publish(-p)\" option or set \"ENV_FORCE_PUBLISH=true\" environment, then forcibly publish"
		CI_DO_PUBLISH=1
	else
		PRNWARN "specified \"--force-publish(-p)\" option or set \"ENV_FORCE_PUBLISH=true\" environment, but Ci was launched by schedule or did not have tag name. Thus it do not run publishing."
		CI_DO_PUBLISH=0
	fi
else
	#
	# FORCE NOT PUBLISH
	#
	PRNINFO "specified \"--not-publish(-np)\" option or set \"ENV_FORCE_PUBLISH=false\" environment, then it do not run publishing."
	CI_DO_PUBLISH=0
fi

PRNSUCCESS "Check whether to publish"

#----------------------------------------------------------
# Show execution environment variables
#----------------------------------------------------------
PRNTITLE "Show execution environment variables"

#
# Information
#
echo "  PRGNAME                       = ${PRGNAME}"
echo "  SCRIPTDIR                     = ${SCRIPTDIR}"
echo "  SRCTOP                        = ${SRCTOP}"
echo ""
echo "  CI_OSTYPE                     = ${CI_OSTYPE}"
echo "  CI_PHPTYPE                    = ${CI_PHPTYPE}"
echo "  PHPVER_NOPERIOD               = ${PHPVER_NOPERIOD}"
echo "  PHPVER_WITHPERIOD             = ${PHPVER_WITHPERIOD}"
echo ""
echo "  CI_IN_SCHEDULE_PROCESS        = ${CI_IN_SCHEDULE_PROCESS}"
echo "  CI_PHPEXTTYPE_VARS_FILE       = ${CI_PHPEXTTYPE_VARS_FILE}"
echo "  CI_BUILD_NUMBER               = ${CI_BUILD_NUMBER}"
echo "  CI_DO_PUBLISH                 = ${CI_DO_PUBLISH}"
echo "  CI_PUBLISH_TAG_NAME           = ${CI_PUBLISH_TAG_NAME}"
echo "  CI_USE_PACKAGECLOUD_REPO      = ${CI_USE_PACKAGECLOUD_REPO}"
echo "  CI_PACKAGECLOUD_TOKEN         = **********"
echo "  CI_PACKAGECLOUD_OWNER         = ${CI_PACKAGECLOUD_OWNER}"
echo "  CI_PACKAGECLOUD_PUBLISH_REPO  = ${CI_PACKAGECLOUD_PUBLISH_REPO}"
echo "  CI_PACKAGECLOUD_DOWNLOAD_REPO = ${CI_PACKAGECLOUD_DOWNLOAD_REPO}"
echo ""
echo "  DEBEMAIL                      = ${DEBEMAIL}"
echo "  DEBFULLNAME                   = ${DEBFULLNAME}"
echo ""
echo "  DIST_TAG                      = ${DIST_TAG}"
echo "  PKG_EXT                       = ${PKG_EXT}"
echo "  PKG_OUTPUT_DIR                = ${PKG_OUTPUT_DIR}"
echo ""
echo "  INSTALLER_BIN                 = ${INSTALLER_BIN}"
echo "  INSTALL_QUIET_ARG             = ${INSTALL_QUIET_ARG}"
echo "  INSTALL_PKG_LIST              = ${INSTALL_PKG_LIST}"
echo ""
echo "  INSTALL_PHP_PRE_ADD_REPO      = ${INSTALL_PHP_PRE_ADD_REPO}"
echo "  INSTALL_PHP_REPO              = ${INSTALL_PHP_REPO}"
echo "  INSTALL_PHP_PKG_LIST          = ${INSTALL_PHP_PKG_LIST}"
echo "  INSTALL_PHP_OPT               = ${INSTALL_PHP_OPT}"
echo "  INSTALL_PHP_POST_CONFIG       = ${INSTALL_PHP_POST_CONFIG}"
echo "  INSTALL_PHP_POST_BIN          = ${INSTALL_PHP_POST_BIN}"
echo "  SWITCH_PHP_COMMAND            = ${SWITCH_PHP_COMMAND}"
echo ""
echo "  IS_OS_UBUNTU                  = ${IS_OS_UBUNTU}"
echo "  IS_OS_DEBIAN                  = ${IS_OS_DEBIAN}"
echo "  IS_OS_CENTOS                  = ${IS_OS_CENTOS}"
echo "  IS_OS_FEDORA                  = ${IS_OS_FEDORA}"
echo "  IS_OS_ROCKY                   = ${IS_OS_ROCKY}"
echo "  IS_OS_ALPINE                  = ${IS_OS_ALPINE}"
echo ""
echo "  PRE_CLEANUP_FILES_DIRS        = ${PRE_CLEANUP_FILES_DIRS}"
echo "  BUILD_MAKE_EXT_OPT            = ${BUILD_MAKE_EXT_OPT}"
echo "  MAKE_TEST_OPT                 = ${MAKE_TEST_OPT}"
echo "  CREATE_PACKAGE_TOOL           = ${CREATE_PACKAGE_TOOL}"
echo "  CREATE_PACKAGE_TOOL_OPT       = ${CREATE_PACKAGE_TOOL_OPT}"
echo ""
echo "  CPPCHECK_TARGET               = ${CPPCHECK_TARGET}"
echo "  CPPCHECK_BASE_OPT             = ${CPPCHECK_BASE_OPT}"
echo "  CPPCHECK_ENABLE_VALUES        = ${CPPCHECK_ENABLE_VALUES}"
echo "  CPPCHECK_IGNORE_VALUES        = ${CPPCHECK_IGNORE_VALUES}"
echo "  CPPCHECK_BUILD_DIR            = ${CPPCHECK_BUILD_DIR}"
echo ""
echo "  SHELLCHECK_TARGET_DIRS        = ${SHELLCHECK_TARGET_DIRS}"
echo "  SHELLCHECK_BASE_OPT           = ${SHELLCHECK_BASE_OPT}"
echo "  SHELLCHECK_EXCEPT_PATHS       = ${SHELLCHECK_EXCEPT_PATHS}"
echo "  SHELLCHECK_IGN                = ${SHELLCHECK_IGN}"
echo "  SHELLCHECK_INCLUDE_IGN        = ${SHELLCHECK_INCLUDE_IGN}"
echo ""

PRNSUCCESS "Show execution environment variables"

#==============================================================
# Install all packages
#==============================================================
PRNTITLE "Update repository and Install curl"

#
# Update local packages
#
PRNINFO "Update local packages"
if ({ RUNCMD "${INSTALLER_BIN}" update -y "${INSTALL_QUIET_ARG}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
	PRNERR "Failed to update local packages"
	exit 1
fi

#
# Check and install curl
#
if ! CURLCMD=$(command -v curl); then
	PRNINFO "Install curl command"
	if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" curl || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install curl command"
		exit 1
	fi
	if ! CURLCMD=$(command -v curl); then
		PRNERR "Not found curl command"
		exit 1
	fi
else
	PRNINFO "Already curl is insatlled."
fi
PRNSUCCESS "Update repository and Install curl"


#--------------------------------------------------------------
# Set package repository for packagecloud.io
#--------------------------------------------------------------
PRNTITLE "Set package repository for packagecloud.io"

if [ "${CI_USE_PACKAGECLOUD_REPO}" -eq 1 ]; then
	#
	# Setup packagecloud.io repository
	#
	if [ "${IS_OS_CENTOS}" -eq 1 ] || [ "${IS_OS_FEDORA}" -eq 1 ] || [ "${IS_OS_ROCKY}" -eq 1 ]; then
		PC_REPO_ADD_SH="script.rpm.sh"
	elif [ "${IS_OS_UBUNTU}" -eq 1 ] || [ "${IS_OS_DEBIAN}" -eq 1 ]; then
		PC_REPO_ADD_SH="script.deb.sh"
	else
		PC_REPO_ADD_SH=""
	fi
	if [ -n "${PC_REPO_ADD_SH}" ]; then
		PRNINFO "Download script and setup packagecloud.io reposiory"
		if ({ RUNCMD "${CURLCMD} -s https://packagecloud.io/install/repositories/${CI_PACKAGECLOUD_OWNER}/${CI_PACKAGECLOUD_DOWNLOAD_REPO}/${PC_REPO_ADD_SH} | bash" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to download script or setup packagecloud.io reposiory"
			exit 1
		fi
	else
		PRNWARN "OS is not debian/ubuntu nor centos/fedora/rocky, then we do not know which download script use. Thus skip to setup packagecloud.io repository."
	fi
else
	PRNINFO "Not set packagecloud.io repository."
fi

PRNSUCCESS "Set package repository for packagecloud.io"

#----------------------------------------------------------
# Install packages(repositories) before adding PHP repository
#----------------------------------------------------------
PRNTITLE "Install packages(repositories) before adding PHP repository"

if [ -n "${INSTALL_PHP_PRE_ADD_REPO}" ]; then
	if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" "${INSTALL_PHP_PRE_ADD_REPO}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install packages(repositories) before adding PHP repository."
		exit 1
	fi
else
	PRNINFO "Nothing to install packages(repositories) before adding PHP repository."
fi

PRNSUCCESS "Install packages(repositories) before adding PHP repository"

#----------------------------------------------------------
# Add PHP repositories
#----------------------------------------------------------
PRNTITLE "Add PHP repositories"

if [ -n "${INSTALL_PHP_REPO}" ]; then
	if [ "${IS_OS_CENTOS}" -eq 1 ] || [ "${IS_OS_ROCKY}" -eq 1 ] || [ "${IS_OS_FEDORA}" -eq 1 ]; then
		if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" "${INSTALL_PHP_REPO}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to add PHP repository."
			exit 1
		fi
	elif [ "${IS_OS_UBUNTU}" -eq 1 ]; then
		if ({ RUNCMD add-apt-repository -y "${INSTALL_PHP_REPO}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to add PHP repository."
			exit 1
		fi
	elif [ "${IS_OS_DEBIAN}" -eq 1 ]; then
		#
		# For debian more complicated than the others.
		#
		if [ -z "${INSTALL_PHP_REPO_GPG_URL}" ] || [ -z "${INSTALL_PHP_REPO_GPG_FILEPATH}" ]; then
			PRNERR "\"INSTALL_PHP_REPO_GPG_URL\" or \"INSTALL_PHP_REPO_GPG_FILEPATH\" varibales are not specified."
			exit 1
		fi
		if ({ RUNCMD "${CURLCMD}" -sSLo "${INSTALL_PHP_REPO_GPG_FILEPATH}" "${INSTALL_PHP_REPO_GPG_URL}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install gpg file."
			exit 1
		fi
		if ({ RUNCMD "echo 'deb [signed-by=${INSTALL_PHP_REPO_GPG_FILEPATH}] https://${INSTALL_PHP_REPO}/ $(lsb_release -sc) main' > /etc/apt/sources.list.d/php.list" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to add repository for PHP"
			exit 1
		fi
		if ({ RUNCMD "${INSTALLER_BIN}" update -y "${INSTALL_QUIET_ARG}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to re-update local packages"
			exit 1
		fi
	else
		PRNINFO "Skip to add PHP repository, because unknown to add it."
	fi
else
	PRNINFO "Nothing to add PHP repository."
fi

PRNSUCCESS "Added PHP repositories"

#--------------------------------------------------------------
# Install packages
#--------------------------------------------------------------
PRNTITLE "Install packages for building/packaging"

if [ -n "${INSTALL_PKG_LIST}" ]; then
	PRNINFO "Install packages"
	if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" "${INSTALL_PKG_LIST}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install packages"
		exit 1
	fi
else
	PRNINFO "Specified no packages for installing. "
fi

PRNSUCCESS "Install packages for building/packaging"

#--------------------------------------------------------------
# Install PHP packages
#--------------------------------------------------------------
PRNTITLE "Install PHP packages"

if [ -n "${INSTALL_PHP_PKG_LIST}" ]; then
	PRNINFO "Install packages"
	if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" "${INSTALL_PHP_OPT}" "${INSTALL_PHP_PKG_LIST}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to install PHP packages"
		exit 1
	fi
else
	PRNINFO "Specified no PHP packages for installing. "
fi

if [ -n "${INSTALL_PHP_POST_CONFIG}" ]; then
	PRNINFO "Set PHP configuration after installing PHP packages"
	if ({ RUNCMD "${INSTALL_PHP_POST_CONFIG}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to set PHP configuration after installing PHP packages"
		exit 1
	fi
else
	PRNINFO "Specified no PHP configuration after installing PHP packages"
fi

if [ -n "${INSTALL_PHP_POST_BIN}" ]; then
	PRNINFO "Set PHP binary after installing PHP packages"
	if ({ RUNCMD "${INSTALL_PHP_POST_BIN}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNERR "Failed to set PHP binary after installing PHP packages"
		exit 1
	fi
else
	PRNINFO "Specified no PHP binary after installing PHP packages"
fi

PRNSUCCESS "Install PHP packages for building/packaging"

#--------------------------------------------------------------
# Install published tools for uploading packages to packagecloud.io
#--------------------------------------------------------------
PRNTITLE "Install published tools for uploading packages to packagecloud.io"

if [ "${CI_DO_PUBLISH}" -eq 1 ]; then
	PRNINFO "Install published tools for uploading packages to packagecloud.io"
	GEM_BIN="gem"

	if [ "${IS_OS_CENTOS}" -eq 1 ] && echo "${CI_OSTYPE}" | sed -e 's#:##g' | grep -q -i -e 'centos7' -e 'centos6'; then
		#
		# Case for CentOS
		#
		PRNWARN "OS is CentOS 7(6), so install ruby by special means(SCL)."

		if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" centos-release-scl || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install SCL packages"
			exit 1
		fi
		if ({ RUNCMD "${INSTALLER_BIN}" install -y "${INSTALL_QUIET_ARG}" rh-ruby24 rh-ruby24-ruby-devel rh-ruby24-rubygem-rake || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install ruby packages"
			exit 1
		fi
		. /opt/rh/rh-ruby24/enable

		if ({ RUNCMD "${GEM_BIN}" install package_cloud || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install packagecloud.io upload tools"
			exit 1
		fi
	else
		#
		# Case for other than CentOS
		#
		if ({ RUNCMD "${GEM_BIN}" install rake package_cloud || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install packagecloud.io upload tools"
			exit 1
		fi
	fi
else
	PRNINFO "Skip to install published tools for uploading packages to packagecloud.io, because this CI process does not upload any packages."
fi

PRNSUCCESS "Install published tools for uploading packages to packagecloud.io"

#--------------------------------------------------------------
# Install cppcheck
#--------------------------------------------------------------
PRNTITLE "Install cppcheck"

IS_SET_ANOTHER_REPOSITORIES=0
if [ "${RUN_CPPCHECK}" -eq 1 ]; then
	PRNINFO "Install cppcheck package."

	if [ "${IS_OS_CENTOS}" -eq 1 ]; then
		#
		# CentOS
		#
		if ({ RUNCMD "${INSTALLER_BIN}" install -y epel-release || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install epel repository"
			exit 1
		fi
		if ({ RUNCMD yum-config-manager --disable epel || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to disable epel repository"
			exit 1
		fi
		if ({ RUNCMD "${INSTALLER_BIN}" --enablerepo=epel install -y cppcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install cppcheck from epel repository"
			exit 1
		fi
		IS_SET_ANOTHER_REPOSITORIES=1

	elif [ "${IS_OS_FEDORA}" -eq 1 ]; then
		#
		# Fedora
		#
		if ({ RUNCMD "${INSTALLER_BIN}" install -y cppcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install cppcheck"
			exit 1
		fi

	elif [ "${IS_OS_ROCKY}" -eq 1 ]; then
		if echo "${CI_OSTYPE}" | sed -e 's#:##g' | grep -q -i 'rockylinux8'; then
			#
			# Rocky 8
			#
			if ({ RUNCMD "${INSTALLER_BIN}" install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to install epel repository"
				exit 1
			fi
			if ({ RUNCMD "${INSTALLER_BIN}" config-manager --enable epel || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to enable epel repository"
				exit 1
			fi
			if ({ RUNCMD "${INSTALLER_BIN}" config-manager --set-enabled powertools || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to enable powertools"
				exit 1
			fi
		else
			#
			# Rocky 9 or later
			#
			if ({ RUNCMD "${INSTALLER_BIN}" install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to install epel repository"
				exit 1
			fi
			if ({ RUNCMD "${INSTALLER_BIN}" config-manager --enable epel || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to enable epel repository"
				exit 1
			fi
		fi
		if ({ RUNCMD "${INSTALLER_BIN}" install -y cppcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install cppcheck"
			exit 1
		fi
		IS_SET_ANOTHER_REPOSITORIES=1

	elif [ "${IS_OS_UBUNTU}" -eq 1 ] || [ "${IS_OS_DEBIAN}" -eq 1 ]; then
		#
		# Ubuntu or Debian
		#
		if ({ RUNCMD "${INSTALLER_BIN}" install -y cppcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install cppcheck"
			exit 1
		fi

	else
		PRNINFO "Skip to install cppcheck package, because unknown to install it."
	fi
else
	PRNINFO "Skip to install cppcheck package, because cppcheck process does not need."
fi

PRNSUCCESS "Install cppcheck"

#--------------------------------------------------------------
# Install shellcheck
#--------------------------------------------------------------
PRNTITLE "Install shellcheck"

if [ "${RUN_SHELLCHECK}" -eq 1 ]; then
	PRNINFO "Install shellcheck package."

	if [ "${IS_OS_CENTOS}" -eq 1 ]; then
		#
		# CentOS
		#
		if [ "${IS_SET_ANOTHER_REPOSITORIES}" -eq 0 ]; then
			if ({ RUNCMD "${INSTALLER_BIN}" install -y epel-release || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to install epel repository"
				exit 1
			fi
			if ({ RUNCMD yum-config-manager --disable epel || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
				PRNERR "Failed to disable epel repository"
				exit 1
			fi
			IS_SET_ANOTHER_REPOSITORIES=1
		fi
		if ({ RUNCMD "${INSTALLER_BIN}" --enablerepo=epel install -y ShellCheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install ShellCheck from epel repository"
			exit 1
		fi

	elif [ "${IS_OS_FEDORA}" -eq 1 ]; then
		#
		# Fedora
		#
		if ({ RUNCMD "${INSTALLER_BIN}" install -y ShellCheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install cppcheck"
			exit 1
		fi

	elif [ "${IS_OS_ROCKY}" -eq 1 ]; then
		#
		# Rocky
		#
		if ! LATEST_SHELLCHECK_DOWNLOAD_URL=$("${CURLCMD}" -s -S https://api.github.com/repos/koalaman/shellcheck/releases/latest | grep '"browser_download_url"' | grep 'linux.x86_64' | sed -e 's|"||g' -e 's|^.*browser_download_url:[[:space:]]*||g' | tr -d '\n'); then
			PRNERR "Failed to get shellcheck download url path"
			exit 1
		fi
		if ({ RUNCMD "${CURLCMD}" -s -S -L -o /tmp/shellcheck.tar.xz "${LATEST_SHELLCHECK_DOWNLOAD_URL}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to download latest shellcheck tar.xz"
			exit 1
		fi
		if ({ RUNCMD tar -C /usr/bin/ -xf /tmp/shellcheck.tar.xz --no-anchored 'shellcheck' --strip=1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to extract latest shellcheck binary"
			exit 1
		fi
		rm -f /tmp/shellcheck.tar.xz

	elif [ "${IS_OS_UBUNTU}" -eq 1 ] || [ "${IS_OS_DEBIAN}" -eq 1 ]; then
		#
		# Ubuntu or Debian
		#
		if ({ RUNCMD "${INSTALLER_BIN}" install -y shellcheck || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
			PRNERR "Failed to install cppcheck"
			exit 1
		fi

	else
		PRNINFO "Skip to install shellcheck package, because unknown to install it."
	fi
else
	PRNINFO "Skip to install shellcheck package, because shellcheck process does not need."
fi

PRNSUCCESS "Install shellcheck"

#==============================================================
# Processing
#==============================================================
#
# Configuration
#

#
# Before configuration
#
if [ "${RUN_PRE_CONFIG}" -eq 1 ]; then
	PRNTITLE "Before configration"
	if ({ run_pre_configuration 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Before configration\"."
		exit 1
	fi
	PRNSUCCESS "Before configration."
fi

#
# Configuration
#
if [ "${RUN_CONFIG}" -eq 1 ]; then
	PRNTITLE "Configration"
	if ({ run_configuration 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Configration\"."
		exit 1
	fi
	PRNSUCCESS "Configuration."
fi

#--------------------------------------------------------------
# Cleanup
#--------------------------------------------------------------
#
# Before Cleanup
#
if [ "${RUN_PRE_CLEANUP}" -eq 1 ]; then
	PRNTITLE "Before Cleanup"
	if ({ run_pre_cleanup 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Before Cleanup\"."
		exit 1
	fi
	PRNSUCCESS "Before Cleanup."
fi

#
# Cleanup
#
if [ "${RUN_CLEANUP}" -eq 1 ]; then
	PRNTITLE "Cleanup"
	if ({ run_cleanup 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Cleanup\"."
		exit 1
	fi
	PRNSUCCESS "Cleanup."
fi

#
# After Cleanup
#
if [ "${RUN_POST_CLEANUP}" -eq 1 ]; then
	PRNTITLE "After Cleanup"
	if ({ run_post_cleanup 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"After Cleanup\"."
		exit 1
	fi
	PRNSUCCESS "After Cleanup."
fi

#--------------------------------------------------------------
# Check before building
#--------------------------------------------------------------
#
# CppCheck
#
if [ "${RUN_CPPCHECK}" -eq 1 ]; then
	PRNTITLE "Check before building : CppCheck"
	if ({ run_cppcheck 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Check before building : CppCheck\"."
		exit 1
	fi
	PRNSUCCESS "Check before building : CppCheck."
fi

#
# ShellCheck
#
if [ "${RUN_SHELLCHECK}" -eq 1 ]; then
	PRNTITLE "Check before building : ShellCheck"
	if ({ run_shellcheck 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Check before building : ShellCheck\"."
		exit 1
	fi
	PRNSUCCESS "Check before building : ShellCheck."
fi

#
# Other check
#
if [ "${RUN_CHECK_OTHER}" -eq 1 ]; then
	PRNTITLE "Check before building : Other"
	if ({ run_othercheck 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Check before building : Other\"."
		exit 1
	fi
	PRNSUCCESS "Check before building : Other."
fi

#--------------------------------------------------------------
# Build
#--------------------------------------------------------------
#
# Before Build
#
if [ "${RUN_PRE_BUILD}" -eq 1 ]; then
	PRNTITLE "Before Build"
	if ({ run_pre_build 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Before Build\"."
		exit 1
	fi
	PRNSUCCESS "Before Build."
fi

#
# Build
#
if [ "${RUN_BUILD}" -eq 1 ]; then
	PRNTITLE "Build"
	if ({ run_build 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Build\"."
		exit 1
	fi
	PRNSUCCESS "Build."
fi

#
# After Build
#
if [ "${RUN_POST_BUILD}" -eq 1 ]; then
	PRNTITLE "After Build"
	if ({ run_post_build 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"After Build\"."
		exit 1
	fi
	PRNSUCCESS "After Build."
fi

#--------------------------------------------------------------
# Test
#--------------------------------------------------------------
#
# Before Test
#
if [ "${RUN_PRE_TEST}" -eq 1 ]; then
	PRNTITLE "Before Test"
	if ({ run_pre_test 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Before Test\"."
		exit 1
	fi
	PRNSUCCESS "Before Test."
fi

#
# Test
#
if [ "${RUN_TEST}" -eq 1 ]; then
	PRNTITLE "Test"
	if ({ run_test 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Test\"."
		exit 1
	fi
	PRNSUCCESS "Test."
fi

#
# After Test
#
if [ "${RUN_POST_TEST}" -eq 1 ]; then
	PRNTITLE "After Test"
	if ({ run_post_test 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"After Test\"."
		exit 1
	fi
	PRNSUCCESS "After Test."
fi

#--------------------------------------------------------------
# Package
#--------------------------------------------------------------
#
# Before Create Package
#
if [ "${RUN_PRE_PACKAGE}" -eq 1 ]; then
	PRNTITLE "Before Create Package"
	if ({ run_pre_create_package 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Before Create Package\"."
		exit 1
	fi
	PRNSUCCESS "Before Create Package."
fi

#
# Create Package
#
if [ "${RUN_PACKAGE}" -eq 1 ]; then
	PRNTITLE "Create Package"
	if ({ run_create_package 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Create Package\"."
		exit 1
	fi
	PRNSUCCESS "Create Package."
fi

#
# After Create Package
#
if [ "${RUN_POST_PACKAGE}" -eq 1 ]; then
	PRNTITLE "After Create Package"
	if ({ run_post_create_package 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"After Create Package\"."
		exit 1
	fi
	PRNSUCCESS "After Create Package."
fi

#--------------------------------------------------------------
# Publish Package
#--------------------------------------------------------------
#
# Publish Package
#
if [ "${RUN_PUBLISH_PACKAGE}" -eq 1 ]; then
	PRNTITLE "Publish Package"
	if ({ run_publish_package 2>&1 || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /g') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		PRNFAILURE "Failed \"Publish Package\"."
		exit 1
	fi
	PRNSUCCESS "Publish Package."
fi

#----------------------------------------------------------
# Finish
#----------------------------------------------------------
PRNSUCCESS "Finished all processing without error."

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
