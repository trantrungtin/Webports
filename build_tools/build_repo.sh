# Copyright 2015 The Native Client Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

set -o errexit
set -o nounset

SCRIPT_DIR="$(cd $(dirname $0) && pwd)"
NACLPORTS_ROOT="$(cd ${SCRIPT_DIR}/.. && pwd)"

PKG_HOST_DIR=${NACLPORTS_ROOT}/pkg_host/
PKG_FILENAME=pkg-1.5.5
PKG_URL=http://storage.googleapis.com/naclports/mirror/${PKG_FILENAME}.tar.gz


#
# Attempt to download a file from a given URL
# $1 - URL to fetch
# $2 - Filename to write to.
#
Fetch() {
  local URL=$1
  local FILENAME=$2
  # Send curl's status messages to stdout rather then stderr
  CURL_ARGS="--fail --location --stderr -"
  if [ -t 1 ]; then
      # Add --progress-bar but only if stdout is a TTY device.
      CURL_ARGS+=" --progress-bar"
  else
      # otherwise suppress all status output, since curl always
      # assumes a TTY and writes \r and \b characters.
      CURL_ARGS+=" --silent"
  fi
  if which curl > /dev/null ; then
      curl ${CURL_ARGS} -o "${FILENAME}" "${URL}"
  else
      echo "error: could not find 'curl' in your PATH"
      exit 1
  fi
}

BuildPkg() {
  if [ -d ${PKG_HOST_DIR} ]; then
      return
  fi
  mkdir -p ${PKG_HOST_DIR}
  Fetch ${PKG_URL} ${PKG_HOST_DIR}/${PKG_FILENAME}
  cd "${PKG_HOST_DIR}"
  tar -xvf ${PKG_FILENAME}
  cd ${PKG_FILENAME}
  ./autogen.sh
  ./configure --with-ldns
  make
}

WriteMetaFile() {
  echo "version = 1;" >> $1
  echo "packing_format = "tbz";" >> $1
  echo "digest_format = "sha256_base32";" >> $1
  echo "digests = "digests";" >> $1
  echo "manifests = "packagesite.yaml";" >> $1
  echo "filesite = "filesite.yaml";" >> $1
  echo "digests_archive = "digests";" >> $1
  echo "manifests_archive = "packagesite";" >> $1
  echo "filesite_archive = "filesite";" >> $1
}

BuildRepo() {
  cd ${SCRIPT_DIR}
  ./download_pkg.py $1
  for pkg_dir in ${NACLPORTS_ROOT}/out/packages/prebuilt/pkg/*/ ; do
    WriteMetaFile "${pkg_dir}/meta"
    "${PKG_HOST_DIR}/${PKG_FILENAME}/src/pkg" repo \
                                              -m "${pkg_dir}/meta" "${pkg_dir}"
  done
}

if [[ $# -ne 1 ]]; then
  echo "./build_repo.sh REVISION"
  exit 1
fi
BuildPkg
BuildRepo $1