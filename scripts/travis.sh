#!/usr/bin/env bash

# Copyright (c) 2019 Trail of Bits, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specifi

main() {
  if [ $# -ne 2 ] ; then
    printf "Usage:\n\ttravis.sh <linux|osx> <initialize|build>\n"
    return 1
  fi

  local platform_name="$1"
  local operation_type="$2"

  if [[ "${platform_name}" != "osx" && "${platform_name}" != "linux" ]] ; then
    printf "Invalid platform: ${platform_name}\n"
    return 1
  fi

  if [[ "${operation_type}" == "initialize" ]] ; then
    "${platform_name}_initialize"
    return $?

  elif [[ "$operation_type" == "build" ]] ; then
    "${platform_name}_build"
    return $?

  else
    printf "Invalid operation\n"
    return 1
  fi
}

linux_initialize() {
  printf "Initializing platform: linux\n"

  printf " > Updating the system...\n"
  sudo apt-get -qq update
  if [ $? -ne 0 ] ; then
    printf " x The package database could not be updated\n"
    return 1
  fi

  printf " > Installing the required packages...\n"
  sudo apt-get install -qqy git python2.7 unzip curl realpath build-essential gcc-multilib g++-multilib libomp-dev libtinfo-dev lsb-release
  if [ $? -ne 0 ] ; then
    printf " x Could not install the required dependencies\n"
    return 1
  fi

  printf " > The system has been successfully initialized\n"
  return 0
}

osx_initialize() {
  printf "Initializing platform: osx\n"
  return 0
}

linux_build() {
  local os_version=`cat /etc/issue | awk '{ print $2 }' | cut -d '.' -f 1-2 | tr -d '.'`

  get_z3

  llvm_version_list=( "40" "50" "60" "70" "80" )
  
  for llvm_version in "${llvm_version_list[@]}" ; do
    common_build "ubuntu${os_version}" "${llvm_version}" 1
    if [ $? -ne 0 ] ; then
      return 1
    fi

    printf "\n\n"
  done

  return 0
}

osx_build() {
  get_z3
  
  llvm_version_list=( "40" "50" "60" "70" "80" )
  
  for llvm_version in "${llvm_version_list[@]}" ; do
    common_build "osx" "${llvm_version}" 1
    if [ $? -ne 0 ] ; then
      return 1
    fi

    printf "\n\n"
  done

  return 0
}

get_z3() { 
  local log_file=`mktemp`
  local z3_version="4.7.1"
  local z3_release="z3-${z3_version}-x64-ubuntu-16.04"
  
  # clean up any existing Z3 stuff  
  if [ -d "z3" ] ; then
    sudo rm -rf z3 > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x Failed to remove the existing z3 folder. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"
      return 1
    fi
  fi
  
  if [ -f "${z3_release}.zip" ] ; then
    sudo rm "${z3_release}.zip" > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x Failed to remove the existing z3 archive. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"
      return 1
    fi
  fi

  printf "#\n"
  printf "# Acquiring Z3 release: ${z3_release}\n"
  printf "#\n\n"
   
  curl -C - "https://github.com/Z3Prover/z3/releases/download/z3-${z3_version}/${z3_release}.zip" -OL > "${log_file}" 2>&1
  if [ $? -ne 0 ] ; then
    printf " x Failed to download the z3 release archive. Error output follows:\n"
    printf "===\n"
    cat "${log_file}"

    rm "${z3_release}.zip"
    return 1
  fi

  unzip -qq "${z3_release}.zip" > "${log_file}" 2>&1
  if [ $? -ne 0 ] ; then
    printf " x Failed to unzip the z3 release archive. Error output follows:\n"
    printf "===\n"
    cat "${log_file}"

    rm "${z3_release}.zip"
    rm -rf "${z3_release}"
    return 1
  fi

  mv ${z3_release} z3 > "${log_file}" 2>&1
  if [ $? -ne 0 ] ; then
    printf " x Failed to move the z3 release archive. Error output follows:\n"
    printf "===\n"
    cat "${log_file}"

    rm "${z3_release}.zip"
    rm -rf "${z3_release}"
    rm -rf z3
    return 1
  fi
}

common_build() {
  if [ $# -ne 3 ] ; then
    printf "Usage:\n\tcommon_build <os_version> <llvm_version> <use_host_compiler>\n\nllvm_version: 35, 40, ...\n"
    return 1
  fi

  local original_path="${PATH}"
  local log_file=`mktemp`
  local os_version="$1"
  local llvm_version="$2"
  local use_host_compiler="$3"

  printf "#\n"
  printf "# Running CI tests for LLVM version ${llvm_version}...\n"
  printf "#\n\n"

  printf " > Cleaning up the environment variables...\n"
  export PATH="${original_path}"

  unset TRAILOFBITS_LIBRARIES
  unset CC
  unset CXX

  printf " > Cleaning up the build folders...\n"
  if [ -d "build" ] ; then
    sudo rm -rf build > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x Failed to remove the existing build folder. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"
      return 1
    fi
  fi

  if [ -d "libraries" ] ; then
    sudo rm -rf libraries > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x Failed to remove the existing libraries folder. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"
      return 1
    fi
  fi

  # acquire the cxx-common package
  printf " > Acquiring the cxx-common package: LLVM${llvm_version} for ${os_version}\n"

  if [ ! -d "cxxcommon" ] ; then
    mkdir "cxxcommon" > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x Failed to create the cxxcommon folder. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"
      return 1
    fi
  fi

  local cxx_common_tarball_name="libraries-llvm${llvm_version}-${os_version}-amd64.tar.gz"
  if [ ! -f "cxxcommon/${cxx_common_tarball_name}" ] ; then
    ( cd "cxxcommon" && curl -C - "https://s3.amazonaws.com/cxx-common/${cxx_common_tarball_name}" -O ) > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x Failed to download the cxx-common package. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"

      rm "cxxcommon/${cxx_common_tarball_name}"
      return 1
    fi
  fi

  if [ ! -d "libraries" ] ; then
    tar xzf "cxxcommon/${cxx_common_tarball_name}" > "${log_file}" 2>&1
    if [ $? -ne 0 ] ; then
      printf " x The archive appears to be corrupted. Error output follows:\n"
      printf "===\n"
      cat "${log_file}"

      rm "cxxcommon/${cxx_common_tarball_name}"
      rm -rf libraries
      return 1
    fi
  fi

  export TRAILOFBITS_LIBRARIES=`GetRealPath libraries`
  export Z3_LIBRARIES=`GetRealPath z3`
  export PATH="${TRAILOFBITS_LIBRARIES}/llvm/bin:${TRAILOFBITS_LIBRARIES}/cmake/bin:${TRAILOFBITS_LIBRARIES}/protobuf/bin:${PATH}"

  if [[ "${use_host_compiler}" = "1" ]] ; then
    if [[ "x${CC}x" = "xx" ]] ; then
      export CC=$(which cc)
    fi
    
    if [[ "x${CXX}x" = "xx" ]] ; then
      export CXX=$(which c++)
    fi
  else
    export CC="${TRAILOFBITS_LIBRARIES}/llvm/bin/clang"
    export CXX="${TRAILOFBITS_LIBRARIES}/llvm/bin/clang++"
  fi

  printf " > Generating the project...\n"
  mkdir build > "${log_file}" 2>&1
  if [ $? -ne 0 ] ; then
    printf " x Failed to create the build folder. Error output follows:\n"
    printf "===\n"
    cat "${log_file}"
    return 1
  fi

  ( cd build && cmake -DZ3_INSTALL_PREFIX="${Z3_LIBRARIES}" -DCMAKE_VERBOSE_MAKEFILE=True .. ) > "${log_file}" 2>&1
  if [ $? -ne 0 ] ; then
    printf " x Failed to generate the project. Error output follows:\n"
    printf "===\n"
    cat "${log_file}"
    return 1
  fi

  printf " > Building rellic...\n"
  if [ "${llvm_version:0:1}" == "3" ] ; then
    printf " i Clang static analyzer not supported on this LLVM release (${llvm_version})\n"
    ( cd build && make -j `nproc` && make test) &
  else
    printf " i Clang static analyzer enabled\n"
    ( cd build && scan-build --show-description make -j `GetProcessorCount` && make test) > "${log_file}" 2>&1 &
  fi

  local build_pid="$!"

  printf "\nWaiting..."
  while [ true ] ; do
    kill -s 0 "${build_pid}" > /dev/null 2>&1
    if [ $? -ne 0 ] ; then
      break
    fi

    printf "."
    sleep 5
  done
  printf "\n\n"

  wait "${build_pid}"
  if [ $? -ne 0 ] ; then
    printf " x Failed to build the project. Error output follows:\n"
    printf "===\n"
    cat "${log_file}"
    cat build/Testing/Temporary/LastTest.log
    return 1
  fi

  if [ "${llvm_version:0:1}" != "3" ] ; then
    if [ `cat "${log_file}" | grep 'scan-build: No bugs found.' | wc -l` != 0 ] ; then
      printf " i scan-build didn't find any bug\n"
    else
      printf " ! scan-build output follows\n"
      if [ "${llvm_version:0:1}" != "3" ] ; then
        cat "${log_file}" | while read line ; do printf "   %s\n" "${line}" ; done
        printf "\n"
      fi
    fi
  fi

  printf " > Build succeeded\n"
  return 0
}

GetProcessorCount() {
  which nproc > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    nproc
  else
    sysctl -n hw.ncpu
  fi
}

GetRealPath() {
  which realpath > /dev/null 2>&1
  if [ $? -eq 0 ] ; then
    realpath $1
  else
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
  fi
}

main $@
exit $?
