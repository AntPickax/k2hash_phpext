#!/bin/sh
#
# Utility tools for building PHP packages by AntPickax
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
# CREATE:   Tue, Feb 22 2022
# REVISION:
#

#==============================================================
# Autobuild for PHP debian package
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

#----------------------------------------------------------
# Common variables
#----------------------------------------------------------
PRGNAME=$(basename "$0")
SCRIPTDIR=$(dirname "$0")
SCRIPTDIR=$(cd "${SCRIPTDIR}" || exit 1; pwd)
SRCTOP=$(cd "${SCRIPTDIR}"/.. || exit 1; pwd)

BUILDDEBDIR="${SRCTOP}/debian_build"
DEBPKGDIR="${SRCTOP}/packages"

PRGNAME_NOEXT=$(echo "${PRGNAME}" | sed -e 's/[\.].*$//g' | tr -d '\n')
EXTRA_COPY_FILES_CONF="${SCRIPTDIR}/${PRGNAME_NOEXT}_copy.conf"

#
# Variables
#
BUILD_NUMBER=0
IS_CLEAN=0
NO_INTERACTIVE=0
IS_COPY_COMMON_PKGS=0

#----------------------------------------------------------
# Utility: Usage
#----------------------------------------------------------
func_usage()
{
	echo ""
	echo "Usage:  $1 [--help(-h)] [--clean(-c)] [--copy-common-package(-ccp)] [--buildnum(-b) <build number>] [--yes(-y)]"
	echo "        --help(-h)                     print help"
	echo "        --clean(-c)                    only clean work directory."
	echo "        --copy-common-package(-ccp)    copy common package to packages directory."
	echo "        --buildnum(-b) <build number>  specify build number for packaging(default 1)"
	echo "        --yes(-y)                      runs no interactive mode."
	echo ""
	echo "Note:  Only if \"--copy-common-package(-ccp)\" is specified, the following"
	echo "       packages will be copied to the packages directory."
	echo "           php-pecl-k2hash_X.Y.Z-N_****.deb"
	echo "           php-pecl-k2hash-all-dev_X.Y.Z-N_all.deb"
	echo "       These packages are PHP version independent and common, so use this"
	echo "       option to avoid conflicts."
	echo ""
}

#----------------------------------------------------------
# Utilities for message
#----------------------------------------------------------
if [ -t 1 ] || [ "X${CI}" = "Xtrue" ]; then
	# shellcheck disable=SC2034
	CBLD=$(printf '\033[1m')
	CREV=$(printf '\033[7m')
	CRED=$(printf '\033[31m')
	CYEL=$(printf '\033[33m')
	CGRN=$(printf '\033[32m')
	CDEF=$(printf '\033[0m')
else
	# shellcheck disable=SC2034
	CBLD=""
	CREV=""
	CRED=""
	CYEL=""
	CGRN=""
	CDEF=""
fi
if [ "X${CI}" = "Xtrue" ]; then
	GHAGRP_START="::group::"
	GHAGRP_END="::endgroup::"
else
	GHAGRP_START=""
	GHAGRP_END=""
fi

prn_title()
{
	echo "${GHAGRP_START}${CBLD}$*${CDEF}"
}
prn_success()
{
	echo "${CBLD}${CGRN}${CREV}[SUCCESS]${CDEF} $*"
	echo ""
}
prn_fauilure()
{
	echo "${CBLD}${CRED}${CREV}[FAILURE]${CDEF} ${CRED}$*${CDEF}"
	echo ""
}
prn_warning()
{
	echo "${CBLD}${CYEL}${CREV}[WARNING]${CDEF} ${CYEL}$*${CDEF}"
	echo ""
}
prn_groupend()
{
	if [ -n "${GHAGRP_END}" ]; then
		echo "${GHAGRP_END}"
	fi
}

#----------------------------------------------------------
# Parse options
#----------------------------------------------------------
while [ $# -ne 0 ]; do
	if [ -z "$1" ]; then
		break

	elif [ "$1" = "-h" ] || [ "$1" = "-H" ] || [ "$1" = "--help" ] || [ "$1" = "--HELP" ]; then
		func_usage "${PRGNAME}"
		exit 0

	elif [ "$1" = "-c" ] || [ "$1" = "-C" ] || [ "$1" = "--clean" ] || [ "$1" = "--CLEAN" ]; then
		if [ "${IS_CLEAN}" -ne 0 ]; then
			prn_fauilure "Already --clean(-c) option is specified."
			exit 1
		fi
		IS_CLEAN=1

	elif [ "$1" = "-b" ] || [ "$1" = "-B" ] || [ "$1" = "--buildnum" ] || [ "$1" = "--BUILDNUM" ]; then
		if [ "${BUILD_NUMBER}" -ne 0 ]; then
			prn_fauilure "Already --buildnum(-b) option is specified(${BUILD_NUMBER})."
			exit 1
		fi
		shift
		if [ -z "$1" ]; then
			prn_fauilure "--buildnum(-b) option need parameter."
			exit 1
		fi
		if echo "$1" | grep -q "[^0-9]"; then
			prn_fauilure "--buildnum(-b) option parameter must be number(and not equal zero)."
			exit 1
		fi
		if [ "$1" -eq 0 ]; then
			prn_fauilure "--buildnum(-b) option parameter must be number(and not equal zero)."
			exit 1
		fi
		BUILD_NUMBER="$1"

	elif [ "$1" = "-ccp" ] || [ "$1" = "-CCP" ] || [ "$1" = "--copy-common-package" ] || [ "$1" = "--COPY-COMMON-PACKAGE" ]; then
		if [ "${IS_COPY_COMMON_PKGS}" -ne 0 ]; then
			prn_fauilure "Already --copy-common-package(-ccp) option is specified."
			exit 1
		fi
		IS_COPY_COMMON_PKGS=1

	elif [ "$1" = "-y" ] || [ "$1" = "-Y" ] || [ "$1" = "--yes" ] || [ "$1" = "--YES" ]; then
		if [ "${NO_INTERACTIVE}" -ne 0 ]; then
			prn_fauilure "Already --yes(-y) option is specified."
			exit 1
		fi
		NO_INTERACTIVE=1

	else
		prn_fauilure "Unknown option - $1."
		exit 1
	fi
	shift
done

#
# Check parameters
#
if [ "${BUILD_NUMBER}" -eq 0 ]; then
	BUILD_NUMBER=1
fi

#----------------------------------------------------------
# Welcome message and confirming for interactive mode
#----------------------------------------------------------
if [ "${NO_INTERACTIVE}" -eq 0 ] && [ "${IS_CLEAN}" -ne 1 ]; then
	echo "---------------------------------------------------------------"
	echo " Do you change these file and commit to github?"
	echo " - ChangeLog     modify / add changes like dch tool format"
	echo " - Git TAG       stamp git tag for release"
	echo "---------------------------------------------------------------"
	IS_CONFIRMED=0
	while [ "${IS_CONFIRMED}" -eq 0 ]; do
		printf '[INPUT] Confirm (y/n) : '
		read -r CONFIRM

		if [ "${CONFIRM}" = "y" ] || [ "${CONFIRM}" = "Y" ] || [ "${CONFIRM}" = "yes" ] || [ "${CONFIRM}" = "YES" ]; then
			IS_CONFIRMED=1
		elif [ "${CONFIRM}" = "n" ] || [ "${CONFIRM}" = "N" ] || [ "${CONFIRM}" = "no" ] || [ "${CONFIRM}" = "NO" ]; then
			echo "Interrupt this processing, bye..."
			exit 0
		fi
	done
	echo ""
fi

#----------------------------------------------------------
# Remove directory for clenup
#----------------------------------------------------------
prn_title "Remove old work directory for packaging"

rm -rf "${BUILDDEBDIR}"
prn_success "Removed ${BUILDDEBDIR}"
prn_groupend

#
# Clean mode -> finish
#
if [ "${IS_CLEAN}" -eq 1 ]; then
	exit 0
fi

#----------------------------------------------------------
# Start building
#----------------------------------------------------------
cd "${SRCTOP}" || exit 1

#----------------------------------------------------------
# Check untracked files
#----------------------------------------------------------
prn_title "Check untracked files"

# [NOTE]
# When using actions/checkout@v1, suppress the following errors.
# "Error: fatal: unsafe repository ('...' is owned by someone else)"
#
git config --global --add safe.directory "${GITHUB_WORKSPACE}"

if [ -n "$(git status --untracked-files=no --porcelain 2>&1)" ]; then
	prn_warning "Some files are in untracked state. Packages are created for testing, but must not be published."
else
	prn_success "No untracked files"
fi
prn_groupend

#----------------------------------------------------------
# Run phpize and configure
#----------------------------------------------------------
prn_title "Run phpize"

if ! phpize; then
	prn_fauilure "Failed to run phpize."
	exit 1
fi
prn_success "phpize done"
prn_groupend

prn_title "Run configure"

if ! ./configure; then
	prn_fauilure "Failed to run configure."
	exit 1
fi
prn_success "configure done"
prn_groupend

#----------------------------------------------------------
# Create package top directory
#----------------------------------------------------------
prn_title "Create work directory for packaging"

if ! mkdir "${BUILDDEBDIR}"; then
	prn_fauilure "Could not create ${BUILDDEBDIR} dicretory."
	exit 1
fi

prn_success "Created ${BUILDDEBDIR}"
prn_groupend

#----------------------------------------------------------
# Get package name and version/build number
#----------------------------------------------------------
prn_title "Get package information"

PACKAGE_NAME=$(head -n 1 ./ChangeLog | awk '{print $1}' | tr -d '\n')
PACKAGE_VERSION=$(head -n 1 ./ChangeLog | sed -e 's/[(]//g' -e 's/[)]//g' | awk '{print $2}' | sed -e 's/-.*$//g' | tr -d '\n')
PACKAGE_PHPVERSION=$(php -r 'echo "".PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PACKAGE_PHPVER_NAME=$(echo "${PACKAGE_NAME}" | sed -s "s/php/php${PACKAGE_PHPVERSION}/g")

echo "-----------------------------------------------------------"
echo " Package name     : ${PACKAGE_NAME} / ${PACKAGE_PHPVER_NAME}"
echo " Package version  : ${PACKAGE_VERSION}"
echo " Build number     : ${BUILD_NUMBER}"
echo " PHP version      : ${PACKAGE_PHPVERSION}"
echo "-----------------------------------------------------------"
prn_success "done"
prn_groupend

EXPANDDIR="${BUILDDEBDIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}"

#----------------------------------------------------------
# Make source tar.gz from git by archive
#----------------------------------------------------------
prn_title "Create base tar ball of source files"

if ! git archive HEAD --prefix="${PACKAGE_NAME}-${PACKAGE_VERSION}"/ --output="${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}".tar.gz; then
	prn_fauilure "Could not make source tar ball(${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}.tar.gz) from github repository."
	exit 1
fi
prn_success "Created ${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}.tar.gz"
prn_groupend

#----------------------------------------------------------
# Expand tar ball
#----------------------------------------------------------
prn_title "Expand base tar ball in work directory"

if ! tar xvfz "${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}".tar.gz -C "${BUILDDEBDIR}"/; then
	prn_fauilure "Could not expand tar ball(${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}.tar.gz)."
	exit 1
fi
prn_success "Expanded to ${EXPANDDIR}"
prn_groupend

#----------------------------------------------------------
# Delete unnecessary files and directories
#----------------------------------------------------------
prn_title "Remove unnecessary files and directories"

rm -rf "${EXPANDDIR}/.github"
rm -rf "${EXPANDDIR}/buildutils"
rm -f  "${EXPANDDIR}/.gitignore"
prn_success "Removed .github, .gitignore, buildutils/"
prn_groupend

#----------------------------------------------------------
# Setup debian directory
#----------------------------------------------------------
prn_title "Setup debian directories"

if ! mkdir -p "${EXPANDDIR}/debian"; then
	prn_fauilure "Could not create ${EXPANDDIR}/debian dicretory."
	exit 1
fi
if ! mkdir -p "${EXPANDDIR}/debian/source"; then
	prn_fauilure "Could not create ${EXPANDDIR}/debian/source dicretory."
	exit 1
fi
if ! mkdir -p "${EXPANDDIR}/debian/upstream"; then
	prn_fauilure "Could not create ${EXPANDDIR}/debian/upstream dicretory."
	exit 1
fi
prn_success "Created ${EXPANDDIR}/debian"
prn_groupend

prn_title "Copy files under debian directory"

#
# copy extra file from php_debian_build_copy.conf
#
# [NOTE]
# If you have files to copy under "<package build to pdirectory>/debian" directory
# (includes in your package), you can prepare "buildutils/php_debian_build_copy.conf"
# file and lists target files int it.
# The file names in this configuration file list with relative paths from the source
# top directory.
#	ex)	src/myfile
#		lib/mylib
#
if [ -f "${EXTRA_COPY_FILES_CONF}" ]; then
	EXTRA_COPY_FILES=$(sed -e 's/#.*$//g' -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' -e '/^$/d' "${EXTRA_COPY_FILES_CONF}")
	for _extra_file in ${EXTRA_COPY_FILES}; do
		if [ ! -f "${SRCTOP}/${_extra_file}" ]; then
			prn_fauilure "${SRCTOP}/${_extra_file} file is not found."
			exit 1
		fi
		if ! cp -p "${SRCTOP}/${_extra_file}" "${EXPANDDIR}/debian"; then
			prn_fauilure "Could not copy ${SRCTOP}/${_extra_file} to ${EXPANDDIR}/debian dicretories."
			exit 1
		fi
	done
	EXTRA_COPY_FILES=" , $(echo "${EXTRA_COPY_FILES}" | sed -e 's/[[:space:]]\+/, /g')"
else
	EXTRA_COPY_FILES=""
fi

#
# convert and copy changelog
#
if ! OS_VERSION_NAME=$(grep '^[[:space:]]*VERSION_CODENAME[[:space:]]*=' /etc/os-release | sed -e 's/^[[:space:]]*VERSION_CODENAME[[:space:]]*=//g' -e 's/^[[:space:]]*//g' -e 's/[[:space:]]*$//g' | tr -d '\n'); then
	prn_fauilure "Could not get OS VERSION CODENAME from /etc/os-relase."
	exit 1
fi
if [ -z "${OS_VERSION_NAME}" ]; then
	prn_fauilure "Could not get OS VERSION CODENAME from /etc/os-relase."
	exit 1
fi
if ! sed -e "s/[\(]${PACKAGE_VERSION}[\)]/\(${PACKAGE_VERSION}-${BUILD_NUMBER}\)/g" -e "s/[\)] unstable; /\) ${OS_VERSION_NAME}; /g" ChangeLog > "${EXPANDDIR}/debian/changelog"; then
	prn_fauilure "Could not convert and copy ChangeLog to ${EXPANDDIR}/debian dicretories."
	exit 1
fi

#
# create files under source directory
#
if ! printf '3.0 (quilt)\n' > "${EXPANDDIR}/debian/source/format"; then
	prn_fauilure "Could not create ${EXPANDDIR}/debian/source/format file."
	exit 1
fi
if ! printf '#abort-on-upstream-changes\n#unapply-patches\n' > "${EXPANDDIR}/debian/source/local-options"; then
	prn_fauilure "Could not create ${EXPANDDIR}/debian/source/local-options file."
	exit 1
fi

#
# copy other files
#
if ! cp buildutils/copyright "${EXPANDDIR}/debian/copyright"; then
	prn_fauilure "Could not copy buildutils/copyright to ${EXPANDDIR}/debian dicretories."
	exit 1
fi
if ! cp buildutils/rules "${EXPANDDIR}/debian/rules"; then
	prn_fauilure "Could not copy buildutils/rules to ${EXPANDDIR}/debian dicretories."
	exit 1
fi
if ! cp buildutils/watch "${EXPANDDIR}/debian/watch"; then
	prn_fauilure "Could not copy buildutils/watch to ${EXPANDDIR}/debian dicretories."
	exit 1
fi
if ! cp buildutils/control.in "${EXPANDDIR}/debian/control.in"; then
	prn_fauilure "Could not copy buildutils/control.in to ${EXPANDDIR}/debian dicretories."
	exit 1
fi
if ! cp buildutils/upstream/metadata "${EXPANDDIR}/debian/upstream/metadata"; then
	prn_fauilure "Could not copy buildutils/upstream/metadata to ${EXPANDDIR}/debian dicretories."
	exit 1
fi

prn_success "Copied/Created changelog, copyright, rules, watch, control.in${EXTRA_COPY_FILES}, source/format, source/local-options, upstream/metadata"
prn_groupend

# [NOTE]
# The "control" file is created from "control.in", but when we run "dpkg-buildpackage",
# we need this file first.
# Thus, before running "dpkg-buildpackage", we need to prepare the "control" file.
# (But after running dpkg-buildpackage, the control file will be updated again)
#
prn_title "Pre-run gen-control"

cd "${EXPANDDIR}" || exit 1
if ! /usr/share/dh-php/gen-control; then
	prn_fauilure "Failed to run gen-control for initializing control file."
	exit 1
fi
prn_success "Generated ${EXPANDDIR}/debian/control"
prn_groupend

#----------------------------------------------------------
# Create "orig" tar ball
#----------------------------------------------------------
prn_title "Create tar ball of original source file"

cd "${BUILDDEBDIR}" || exit 1
if ! tar cvfz "${PACKAGE_NAME}_${PACKAGE_VERSION}.orig.tar.gz" "${PACKAGE_NAME}-${PACKAGE_VERSION}"; then
	prn_fauilure "Failed to craete original source tar ball(${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}.orig.tar.gz)."
	exit 1
fi
prn_success "Created ${BUILDDEBDIR}/${PACKAGE_NAME}_${PACKAGE_VERSION}.orig.tar.gz"
prn_groupend

#----------------------------------------------------------
# Build packages
#----------------------------------------------------------
prn_title "Run dpkg-buildpackage for creating packages"

cd "${EXPANDDIR}" || exit 1
if ! dpkg-buildpackage -us -uc; then
	prn_fauilure "Failed to create packages."
	exit 1
fi
prn_success "Created package files"
prn_groupend

#----------------------------------------------------------
# Check packages
#----------------------------------------------------------
prn_title "Check created debian packages"

cd "${SRCTOP}" || exit 1

#
# Check and show debian package
#
# [NOTE] Check following files:
#	${PACKAGE_PHPVER_NAME}_${PACKAGE_VERSION}-${BUILD_NUMBER}_*.deb
#	${PACKAGE_NAME}_${PACKAGE_VERSION}-${BUILD_NUMBER}_*.deb
#	${PACKAGE_NAME}-all-dev_${PACKAGE_VERSION}-${BUILD_NUMBER}_all.deb
#
DEBIAN_PACKAGE_PHP=$(find "${BUILDDEBDIR}" -name "${PACKAGE_PHPVER_NAME}_${PACKAGE_VERSION}-${BUILD_NUMBER}_*.deb" 2>/dev/null)
DEBIAN_PACKAGE_NORM=$(find "${BUILDDEBDIR}" -name "${PACKAGE_NAME}_${PACKAGE_VERSION}-${BUILD_NUMBER}_*.deb" 2>/dev/null)
DEBIAN_PACKAGE_ALL=$(find "${BUILDDEBDIR}" -name "${PACKAGE_NAME}-all-dev_${PACKAGE_VERSION}-${BUILD_NUMBER}_all.deb" 2>/dev/null)

FOUND_DEB_PACKAGES="${DEBIAN_PACKAGE_PHP} ${DEBIAN_PACKAGE_NORM} ${DEBIAN_PACKAGE_ALL}"

if [ -z "${DEBIAN_PACKAGE_PHP}" ] || [ -z "${DEBIAN_PACKAGE_NORM}" ] || [ -z "${DEBIAN_PACKAGE_ALL}" ]; then
	prn_fauilure "No debian package in ${BUILDDEBDIR}."
	exit 1
fi
if [ "$(echo "${FOUND_DEB_PACKAGES}" | sed -e 's/[[:space:]]/\n/g'| grep -c '\.deb')" -ne 3 ]; then
	prn_fauilure "There are too or few created debian packages(*.deb) : ${FOUND_DEB_PACKAGES}"
	exit 1
fi

for _one_pkg in ${FOUND_DEB_PACKAGES}; do
	echo ""
	echo "[INFO] ${_one_pkg} package information"
	if ({ dpkg -c "${_one_pkg}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		prn_fauilure "Failed to print ${_one_pkg} package insformation by \"dpkg -c\"."
		exit 1
	fi
	echo "    ---------------------------"

	if ({ dpkg -I "${_one_pkg}" || echo > "${PIPEFAILURE_FILE}"; } | sed -e 's/^/    /') && rm "${PIPEFAILURE_FILE}" >/dev/null 2>&1; then
		prn_fauilure "Failed to print ${_one_pkg} package insformation by \"dpkg -I\"."
		exit 1
	fi
done

prn_success "Checked package files"
prn_groupend

#----------------------------------------------------------
# Copy packages
#----------------------------------------------------------
if [ ! -d "${DEBPKGDIR}" ]; then
	prn_title "Create ${DEBPKGDIR} directory"

	if ! mkdir -p "${DEBPKGDIR}"; then
		prn_fauilure "Failed to create ${DEBPKGDIR} directory"
		exit 1
	fi
	prn_success "Created ${DEBPKGDIR} directory"
	prn_groupend
fi

prn_title "Copy created debian packages to packages directory"

if ! cp -p "${DEBIAN_PACKAGE_PHP}" "${DEBPKGDIR}"; then
	prn_fauilure "Failed to copy ${DEBIAN_PACKAGE_PHP} packages to ${DEBPKGDIR}"
	exit 1
fi
echo "Copied ${DEBIAN_PACKAGE_PHP} package."

if [ "${IS_COPY_COMMON_PKGS}" -eq 1 ]; then
	if ! cp -p "${DEBIAN_PACKAGE_NORM}" "${DEBPKGDIR}"; then
		prn_fauilure "Failed to copy ${DEBIAN_PACKAGE_NORM} packages to ${DEBPKGDIR}"
		exit 1
	fi
	echo "Copied ${DEBIAN_PACKAGE_NORM} package."
else
	echo "Skip copying ${DEBIAN_PACKAGE_NORM} package."
fi

if [ "${IS_COPY_COMMON_PKGS}" -eq 1 ]; then
	if ! cp -p "${DEBIAN_PACKAGE_ALL}" "${DEBPKGDIR}"; then
		prn_fauilure "Failed to copy ${DEBIAN_PACKAGE_ALL} packages to ${DEBPKGDIR}"
		exit 1
	fi
	echo "Copied ${DEBIAN_PACKAGE_ALL} package."
else
	echo "Skip copying ${DEBIAN_PACKAGE_ALL} package."
fi
prn_success "Copied debian packages to ${DEBPKGDIR}"
prn_groupend

#----------------------------------------------------------
# finish
#----------------------------------------------------------
prn_title "Install Summary"

prn_success "All processing is succeed"
echo "[SUCCEED] You can find ${PACKAGE_NAME} ${PACKAGE_VERSION}-${BUILD_NUMBER} version debian package in ${DEBPKGDIR} directory."
echo ""
prn_groupend

exit 0

#
# Local variables:
# tab-width: 4
# c-basic-offset: 4
# End:
# vim600: noexpandtab sw=4 ts=4 fdm=marker
# vim<600: noexpandtab sw=4 ts=4
#
