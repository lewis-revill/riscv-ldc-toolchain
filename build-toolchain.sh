#!/bin/bash
# Script for building a RISC-V LDC Toolchain from checked out sources

# Copyright (C) 2021 Embecosm Limited

# Contributor: Lewis Revill <lewis.revill@embecosm.com>

# SPDX-License-Identifier: GPL-3.0-or-later

# Variables used in this script
SRCPREFIX="$(dirname $(dirname $(readlink -f $0)))"
INSTALLPREFIX="${SRCPREFIX}/install"
BUILDPREFIX="${SRCPREFIX}/build"
LOGDIR="${SRCPREFIX}/logs/$(date +%Y%m%d-%H%M)"

# Default variables to be overridden by this script:
BUILD_CMAKE_TYPE=Release
BUILD_CMAKE_SHARED=OFF
BUILD_LLVM_ENABLE_ASSERTIONS=OFF
BUILD_GDB=no
BUILD_QEMU=no
BUILD_BINUTILS=no
BUILD_LLVM=no
BUILD_LDC=no
BUILD_NEWLIB=no
BUILD_COMPILER_RT=no
BUILD_DUB=no
STRIP=no

for opt in ${@}; do
  valid_arg=1
  case ${opt} in
  "--clean")
    echo "Erasing ${BUILDPREFIX}..."
    rm -rf "${BUILDPREFIX}..."
    ;;
  "--mode=debug")
    BUILD_CMAKE_TYPE=Debug
    BUILD_CMAKE_SHARED=ON
    BUILD_LLVM_ENABLE_ASSERTIONS=ON
    ;;
  "--mode=release")
    BUILD_CMAKE_TYPE=Release
    BUILD_CMAKE_SHARED=OFF
    BUILD_LLVM_ENABLE_ASSERTIONS=OFF
    ;;
  "--mode=reldebug")
    BUILD_CMAKE_TYPE=RelWithDebInfo
    BUILD_CMAKE_SHARED=OFF
    BUILD_LLVM_ENABLE_ASSERTIONS=ON
    ;;
  "--with-gdb")
    BUILD_GDB=yes
    ;;
  "--with-qemu")
    BUILD_QEMU=yes
    ;;
  "--with-binutils")
    BUILD_BINUTILS=yes
    ;;
  "--with-llvm")
    BUILD_LLVM=yes
    BUILD_BINUTILS=yes
    ;;
  "--with-ldc")
    BUILD_LDC=yes
    BUILD_LLVM=yes
    BUILD_BINUTILS=yes
    ;;
  "--with-newlib")
    BUILD_NEWLIB=yes
    BUILD_LLVM=yes
    BUILD_BINUTILS=yes
    ;;
  "--with-compiler-rt")
    BUILD_COMPILER_RT=yes
    BUILD_LLVM=yes
    BUILD_BINUTILS=yes
    ;;
  "--with-dub")
    BUILD_DUB=yes
    ;;
  "--all")
    BUILD_GDB=yes
    BUILD_QEMU=yes
    BUILD_BINUTILS=yes
    BUILD_LLVM=yes
    BUILD_LDC=yes
    BUILD_NEWLIB=yes
    BUILD_COMPILER_RT=yes
    BUILD_DUB=yes
    ;;
  "--strip")
    STRIP=yes
    ;;
  "--help")
    valid_arg=0
    ;;& # Fallthrough
  *)
    echo "Usage for $0:"
    echo "  --clean             Erase build directory."
    echo "  --mode=debug        Do a debug build."
    echo "  --mode=release      Do a release build. [Default]"
    echo "  --mode=reldebug     Do a release build with debug info."
    echo "  --with-gdb          Build GDB."
    echo "  --with-qemu         Build QEMU."
    echo "  --with-binutils     Build Binutils."
    echo "  --with-llvm         Build LLVM."
    echo "  --with-ldc          Build LDC."
    echo "  --with-newlib       Build Newlib."
    echo "  --with-compiler-rt  Build compiler-rt."
    echo "  --with-dub          Build DUB."
    echo "  --all               Build all components."
    echo "  --strip             Strip toolchain binaries."
    echo "  --help              Present this message."
    exit $valid_arg
    ;;
  esac
done

# Check branches
checkBranch() {(
  cd ${SRCPREFIX}/${1}
  THISBRANCH=$(git rev-parse --abbrev-ref HEAD)
  if [ "${THISBRANCH}" != "${2}" ]; then
    echo "${1} branch not as expected? Expected '${2}', found '${THISBRANCH}'"
  fi
)}
source "${SRCPREFIX}/toolchain/EXPECTED_BRANCHES"
checkBranch gdb ${EXPECTED_GDB}
checkBranch qemu ${EXPECTED_QEMU}
checkBranch binutils ${EXPECTED_BINUTILS}
checkBranch llvm-project ${EXPECTED_LLVM}
checkBranch ldc ${EXPECTED_LDC}
checkBranch dub ${EXPECTED_DUB}
checkBranch newlib ${EXPECTED_NEWLIB}
checkBranch toolchain ${EXPECTED_TOOLCHAIN}

# Create log dir
mkdir -p ${LOGDIR}

if [ "${BUILD_CMAKE_TYPE}" == "Debug" ] && [ "${STRIP}" == "yes" ]; then
  echo "--strip is skipped in debug mode"
  STRIP=no
fi

# Allow environment to control parallelism
if [ "x${PARALLEL_JOBS}" == "x" ]; then
  PARALLEL_JOBS=$(nproc)
fi

# Make the built D compiler the default for building D components.
if [ "${DMD}" == "" ]; then
  DMD=${INSTALLPREFIX}/bin/ldmd2
  BUILD_LDC=yes
  BUILD_LLVM=yes
  BUILD_BINUTILS=yes
fi

# GDB
if [ "${BUILD_GDB}" == "yes" ]; then
  LOGFILE="${LOGDIR}/gdb.log"
  echo "Building gdb... logging to ${LOGFILE}"
  (
    set -e
    mkdir -p ${BUILDPREFIX}/gdb
    cd ${BUILDPREFIX}/gdb
    ../../gdb/configure                                                        \
        --target=riscv32-unknown-elf                                           \
        --prefix=${INSTALLPREFIX}                                              \
        --without-gnu-as                                                       \
        --disable-werror                                                       \
        --disable-gprof                                                        \
        --disable-ld                                                           \
        --disable-gas                                                          \
        --disable-binutils                                                     \
        ${EXTRA_OPTS}                                                          \
        ${EXTRA_GDB_OPTS}
    make -j${PARALLEL_JOBS}
    make install
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building gdb, check log file!" > /dev/stderr
    exit 1
  fi
else
  echo "Skipping GDB..."
fi

# QEMU
if [ "${BUILD_QEMU}" == "yes" ]; then
  LOGFILE="${LOGDIR}/qemu.log"
  echo "Building qemu... logging to ${LOGFILE}"
  (
    set -e
    mkdir -p ${BUILDPREFIX}/qemu
    cd ${BUILDPREFIX}/qemu
    ../../qemu/configure                                                       \
        --target-list=riscv32-linux-user                                       \
        --prefix=${INSTALLPREFIX}                                              \
        ${EXTRA_OPTS}                                                          \
        ${EXTRA_QEMU_OPTS}
    make -j${PARALLEL_JOBS} all
    make install
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building qemu, check log file!" > /dev/stderr
    exit 1
  fi
else
  echo "Skipping QEMU..."
fi

# Binutils
if [ "${BUILD_BINUTILS}" == "yes" ]; then
  LOGFILE="${LOGDIR}/binutils.log"
  echo "Building binutils... logging to ${LOGFILE}"
  (
    set -e
    mkdir -p ${BUILDPREFIX}/binutils
    cd ${BUILDPREFIX}/binutils
    ../../binutils/configure                                                   \
        --target=riscv32-unknown-elf                                           \
        --prefix=${INSTALLPREFIX}                                              \
        --without-gnu-as                                                       \
        --disable-werror                                                       \
        --disable-gdb                                                          \
        --disable-libdecnumber                                                 \
        --disable-readline                                                     \
        --disable-sim                                                          \
        ${EXTRA_OPTS}                                                          \
        ${EXTRA_BINUTILS_OPTS}
    make -j${PARALLEL_JOBS} all-ld
    make install-ld
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building binutils, check log file!" > /dev/stderr
    exit 1
  fi
else
  echo "Skipping Binutils..."
fi

# Clang/LLVM
if [ "${BUILD_LLVM}" == "yes" ]; then
  LOGFILE="${LOGDIR}/llvm.log"
  echo "Building LLVM... logging to ${LOGFILE}"
  (
    set -e
    mkdir -p ${BUILDPREFIX}/llvm
    cd ${BUILDPREFIX}/llvm
    cmake -G "Ninja"                                                           \
        -DCMAKE_BUILD_TYPE=${BUILD_CMAKE_TYPE}                                 \
        -DBUILD_SHARED_LIBS=${BUILD_CMAKE_SHARED}                              \
        -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}                                \
        -DLLVM_ENABLE_ASSERTIONS=${BUILD_ENABLE_ASSERTIONS}                    \
        -DLLVM_ENABLE_PROJECTS=clang                                           \
        -DLLVM_ENABLE_PLUGINS=ON                                               \
        -DLLVM_BINUTILS_INCDIR=${SRCPREFIX}/binutils/include                   \
        -DLLVM_PARALLEL_LINK_JOBS=5                                            \
        -DLLVM_TARGETS_TO_BUILD=X86\;RISCV                                     \
        ${LLVM_EXTRA_OPTS}                                                     \
        ../../llvm-project/llvm
    cmake --build . -j${PARALLEL_JOBS} --target all
    cmake --build . --target install
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building llvm, check log file!" > /dev/stderr
    exit 1
  fi

  # Add symlinks to LLVM tools
  cd ${INSTALLPREFIX}/bin
  for TRIPLE in riscv32-unknown-elf; do
    for TOOL in clang clang++ cc c++ as; do
      ln -sfv clang ${TRIPLE}-${TOOL}
    done
    ln -sfv llvm-ar ${TRIPLE}-ar
    ln -sfv llvm-ranlib ${TRIPLE}-ranlib
    ln -sfv llvm-objcopy ${TRIPLE}-strip
    ln -sfv llvm-readobj ${TRIPLE}-readelf
  done
else
  echo "Skipping LLVM..."
fi


# LDC
if [ "${BUILD_LDC}" == "yes" ]; then
  LOGFILE="${LOGDIR}/ldc.log"
  echo "Building ldc... logging to ${LOGFILE}"
  (
    set -e
    mkdir -p ${BUILDPREFIX}/ldc
    cd ${BUILDPREFIX}/ldc
    cmake -G "Ninja"                                                           \
        -DCMAKE_BUILD_TYPE=${BUILD_CMAKE_TYPE}                                 \
        -DBUILD_SHARED_LIBS=${BUILD_CMAKE_SHARED}                              \
        -DCMAKE_INSTALL_PREFIX=${INSTALLPREFIX}                                \
        -DLLVM_ROOT_DIR=${INSTALLPREFIX}                                       \
        ${LDC_EXTRA_OPTS}                                                      \
        ../../ldc
    cmake --build . -j${PARALLEL_JOBS} --target all
    cmake --build . --target install
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building ldc, check log file!" > /dev/stderr
    exit 1
  fi
else
  echo "Skipping LDC..."
fi

# From now on, the tools need to be in PATH
PATH=${INSTALLPREFIX}/bin:${PATH}

# DUB
if [ "${BUILD_DUB}" == "yes" ]; then
  LOGFILE="${LOGDIR}/dub.log"
  echo "Building dub... logging to ${LOGFILE}"
  (
    set -e
    rm -rf ${BUILDPREFIX}/dub
    cp -r ${SRCPREFIX}/dub ${BUILDPREFIX}
    cd ${BUILDPREFIX}/dub
    ${DMD} --run build.d
    cp -r ${BUILDPREFIX}/dub/bin/* ${INSTALLPREFIX}/bin/
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building dub, check log file!" > /dev/stderr
    exit 1
  fi
else
  echo "Skipping DUB..."
fi

# Newlib - build for rv32
if [ "${BUILD_NEWLIB}" == "yes" ]; then
  LOGFILE="${LOGDIR}/newlib.log"
  echo "Building newlib... logging to ${LOGFILE}"
  (
    set -e
    mkdir -p ${BUILDPREFIX}/newlib32
    cd ${BUILDPREFIX}/newlib32
    CFLAGS_FOR_TARGET="-DPREFER_SIZE_OVER_SPEED=1 -Os"                         \
    ../../newlib/configure                                                     \
        --target=riscv32-unknown-elf                                           \
        --prefix=${INSTALLPREFIX}                                              \
        --enable-multilib                                                      \
        --enable-newlib-global-atexit                                          \
        --disable-newlib-fvwrite-in-streamio                                   \
        --disable-newlib-fseek-optimization                                    \
        --enable-newlib-nano-malloc                                            \
        --disable-newlib-unbuf-stream-opt                                      \
        --enable-newlib-reent-small                                            \
        --disable-newlib-wide-orient                                           \
        --disable-newlib-io-float                                              \
        --enable-newlib-nano-formatted-io                                      \
        --enable-newlib-io-c99-formats                                         \
        --enable-lite-exit                                                     \
        --disable-newlib-multithread                                           \
        ${EXTRA_OPTS}                                                          \
        ${EXTRA_NEWLIB_OPTS}
    make -j${PARALLEL_JOBS}
    make install
  ) > ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building newlib, check log file!" > /dev/stderr
    exit 1
  fi
else
  echo "Skipping Newlib..."
fi

# Compiler-rt for rv32 and rv64
# NOTE: CMAKE_SYSTEM_NAME is set to linux to allow the configure step to
#       correctly validate that clang works for cross compiling
if [ "${BUILD_COMPILER_RT}" == "yes" ]; then
  LOGFILE="${LOGDIR}/compiler-rt.log"
  echo "Building compiler-rt... logging to ${LOGFILE}"
  for CRT_MULTILIB in $(${BUILDPREFIX}/llvm/bin/clang -target riscv32-unknown-elf -print-multi-lib 2>/dev/null); do
    CRT_MULTILIB_DIR=$(echo ${CRT_MULTILIB} | sed 's/;.*//')
    CRT_MULTILIB_OPT=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/-/' | sed 's/@/ -/g')
    CRT_MULTILIB_BDIR=$(echo ${CRT_MULTILIB} | sed 's/.*;//' | sed 's/@/_/g')
    echo "Multilib: \"${CRT_MULTILIB_DIR}\" -> \"${CRT_MULTILIB_OPT}\"" | tee -a ${LOGFILE}
  (
    set -e
    mkdir -p ${BUILDPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}
    cd ${BUILDPREFIX}/compiler-rt${CRT_MULTILIB_BDIR}
    cmake -G"Unix Makefiles"                                                     \
        -DCMAKE_SYSTEM_NAME=Linux                                                \
        -DCMAKE_INSTALL_PREFIX=$(${INSTALLPREFIX}/bin/clang -print-resource-dir)/riscv32-unknown-elf/${CRT_MULTILIB_DIR} \
        -DCMAKE_C_COMPILER=${INSTALLPREFIX}/bin/clang                            \
        -DCMAKE_AR=${INSTALLPREFIX}/bin/llvm-ar                                  \
        -DCMAKE_NM=${INSTALLPREFIX}/bin/llvm-nm                                  \
        -DCMAKE_RANLIB=${INSTALLPREFIX}/bin/llvm-ranlib                          \
        -DCMAKE_OBJDUMP=${INSTALLPREFIX}/bin/llvm-objdump                        \
        -DCMAKE_C_COMPILER_TARGET="riscv32-unknown-elf"                          \
        -DCMAKE_ASM_COMPILER_TARGET="riscv32-unknown-elf"                        \
        -DCMAKE_C_FLAGS="${CRT_MULTILIB_OPT} -Oz -mno-save-restore -g3"          \
        -DCMAKE_ASM_FLAGS="${CRT_MULTILIB_OPT} -Oz -mno-save-restore"            \
        -DCMAKE_EXE_LINKER_FLAGS="-nostartfiles -nostdlib"                       \
        -DCOMPILER_RT_BAREMETAL_BUILD=ON                                         \
        -DCOMPILER_RT_BUILD_BUILTINS=ON                                          \
        -DCOMPILER_RT_BUILD_LIBFUZZER=OFF                                        \
        -DCOMPILER_RT_BUILD_PROFILE=OFF                                          \
        -DCOMPILER_RT_BUILD_SANITIZERS=OFF                                       \
        -DCOMPILER_RT_BUILD_XRAY=OFF                                             \
        -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON                                     \
        -DCOMPILER_RT_OS_DIR=".."                                                \
        -DLLVM_CONFIG_PATH=${BUILDPREFIX}/llvm/bin/llvm-config                   \
        ../../llvm-project/compiler-rt
    make -j${PARALLEL_JOBS}
    make install
  ) >> ${LOGFILE} 2>&1
  if [ $? -ne 0 ]; then
    echo "Error building compiler-rt, check log file!" > /dev/stderr
    exit 1
  fi
  done

  # Compiler-rt files by default compile with a architecture name, but newer clang
  # checks remove this. Find an rename all files appropriately.
  (
    cd $(${INSTALLPREFIX}/bin/clang -print-resource-dir)/riscv32-unknown-elf
    for i in $(find . -name '*-riscv32.a'); do
      mv ${i} ${i%-riscv32.a}.a
    done
    for i in $(find . -name '*-riscv32.o'); do
      mv ${i} ${i%-riscv32.o}.o
    done
  )
else
  echo "Skipping compiler-rt..."
fi

# Strip binaries when --strip is passed
if [ "${STRIP}" == "yes" ]; then
  echo "Stripping binaries..."
  (
    cd "${INSTALLPREFIX}/bin"
    for i in $(find . -type f -executable); do
      if $(file "${i}" | grep -q "ELF.*x86-64"); then
        strip ${i}
      fi
      if $(file "${i}" | grep -q "PE32.*x86-64"); then
        strip ${i}
      fi
    done
  )
fi

echo "Build completed successfully."
