# Copyright (c) 2014 The Native Client Authors. All rights reserved.
# Use of this source code is governed by a BSD-style license that can be
# found in the LICENSE file.

OS_JOBS=1

if [ "${NACL_LIBC}" = "glibc" ]; then
  export RUNPROGRAM="${NACL_SEL_LDR} -a -B ${NACL_IRT} -- \
    ${NACL_SDK_LIB}/runnable-ld.so \
    --library-path ${NACL_SDK_LIBDIR}:${NACL_SDK_LIB}:${NACLPORTS_LIBDIR}"
  export RUNPROGRAM_ARGS="-a -B ${NACL_IRT} -- ${NACL_SDK_LIB}/runnable-ld.so \
    --library-path ${NACL_SDK_LIBDIR}:${NACL_SDK_LIB}:${NACLPORTS_LIBDIR}"
else
  export RUNPROGRAM="${NACL_SEL_LDR} -a -B ${NACL_IRT} -- "
  export RUNPROGRAM_ARGS="-a -B ${NACL_IRT} -- "
fi
export NACL_SEL_LDR

EXTRA_CONFIGURE_ARGS+=" --with-x"
EXTRA_CONFIGURE_ARGS+=" --with-x-toolkit=athena"
EXTRA_CONFIGURE_ARGS+=" --with-xpm=no"
EXTRA_CONFIGURE_ARGS+=" --with-jpeg=yes"
EXTRA_CONFIGURE_ARGS+=" --with-png=yes"
EXTRA_CONFIGURE_ARGS+=" --with-gif=yes"
EXTRA_CONFIGURE_ARGS+=" --with-tiff=yes"

export COMPAT_LIBS="-l${NACL_CXX_LIB}"

export EXTRA_LIBS="${NACL_CLI_MAIN_LIB} \
  -lppapi_simple -lppapi -lnacl_io -ltar -l${NACL_CXX_LIB}"

if [ "${NACL_LIBC}" = "newlib" ]; then
  export emacs_cv_func__setjmp=no
  NACLPORTS_CPPFLAGS+=" -I${NACLPORTS_INCLUDE}/glibc-compat"
  # Additional transitive dependencies not usually on the link line,
  # but required for static linking.
  DEP_LIBS="-pthread -lxcb -lXau -lXpm -lnacl_io -lglibc-compat"
  COMPAT_LIBS="${DEP_LIBS} ${COMPAT_LIBS}"
  export LIBS+=" ${COMPAT_LIBS}"
  EXTRA_LIBS+=" -lglibc-compat"
fi

ConfigureStep() {
  export CFLAGS="${NACLPORTS_CFLAGS} -I${NACL_SDK_ROOT}/include"
  DefaultConfigureStep
}

# Build twice to workaround a problem in the build script that builds something
# partially the first time that makes the second time succeed.
# TODO(petewil): Find and fix the problem that makes us build twice.
BuildStep() {
  # Since we can't detect that a rebuild file hasn't changed, delete them all.
  # Rebuild a second time on the buildbots only.
  if [ "${BUILDBOT_BUILDERNAME:-}" != "" ]; then
    DefaultBuildStep || DefaultBuildStep
  else
    DefaultBuildStep
  fi
}

PatchStep() {
  DefaultPatchStep

  ChangeDir ${SRC_DIR}
  rm -f lisp/emacs-lisp/bytecomp.elc
  rm -f lisp/files.elc
  rm -f lisp/international/quail.elc
  rm -f lisp/startup.elc
  rm -f lisp/loaddefs.el
  rm -f lisp/loaddefs.elc
  rm -f lisp/vc/vc-git.elc
  LogExecute cp ${START_DIR}/emacs_pepper.c ${SRC_DIR}/src/emacs_pepper.c
}

# Today the install step copies emacs_x86_63.nexe to the publish dir, but we
# need nacl_temacs.nexe instead.  Change to copy that here.

PublishStep() {
  MakeDir ${PUBLISH_DIR}
  local ASSEMBLY_DIR="${PUBLISH_DIR}/emacs"

  DESTDIR=${ASSEMBLY_DIR}/emacstar
  DefaultInstallStep

  #Copy all the elisp files and other files emacs needs to here.
  ChangeDir ${ASSEMBLY_DIR}/emacstar
  echo "****** pwd is " $(pwd)
  echo cp ${BUILD_DIR}/src/nacl_temacs${NACL_EXEEXT} \
       ../emacs_${NACL_ARCH}${NACL_EXEEXT}
  cp ${BUILD_DIR}/src/nacl_temacs${NACL_EXEEXT} \
     ../emacs_${NACL_ARCH}${NACL_EXEEXT}
  rm -rf bin
  rm -rf share/man
  find . -iname "*.nexe" -delete
  mkdir -p ${ASSEMBLY_DIR}/emacstar/home/user/.emacs.d
  cp ${START_DIR}/init.el ${ASSEMBLY_DIR}/emacstar/home/user/.emacs.d
  tar cf ${ASSEMBLY_DIR}/emacs.tar .
  rm -rf ${ASSEMBLY_DIR}/emacstar
  shasum ${ASSEMBLY_DIR}/emacs.tar > ${ASSEMBLY_DIR}/emacs.tar.hash
  cd ${ASSEMBLY_DIR}
  # TODO(petewil) this is expecting an exe, but we give it a shell script
  # since we have emacs running "unpacked", so it fails. Give it
  # nacl_temacs.nexe instead.
  LogExecute python ${NACL_SDK_ROOT}/tools/create_nmf.py \
      emacs_*${NACL_EXEEXT} \
      -s . \
      -o emacs.nmf
  LogExecute python ${TOOLS_DIR}/create_term.py emacs.nmf

  InstallNaClTerm ${ASSEMBLY_DIR}
  GenerateManifest ${START_DIR}/manifest.json ${ASSEMBLY_DIR} "TITLE"="Emacs"
  LogExecute cp ${START_DIR}/background.js ${ASSEMBLY_DIR}
  LogExecute cp ${START_DIR}/icon_16.png ${ASSEMBLY_DIR}
  LogExecute cp ${START_DIR}/icon_48.png ${ASSEMBLY_DIR}
  LogExecute cp ${START_DIR}/icon_128.png ${ASSEMBLY_DIR}
  LogExecute cp ${START_DIR}/emacs.js ${ASSEMBLY_DIR}
  ChangeDir ${PUBLISH_DIR}
  CreateWebStoreZip emacs-${VERSION}.zip emacs
}
