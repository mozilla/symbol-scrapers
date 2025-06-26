#!/bin/bash

export DEBUGINFOD_URLS="https://debuginfod.archlinux.org/"

. $(dirname $0)/../common.sh

URL="https://geo.mirror.pkgbuild.com"

REPOS="
core-testing/os/x86_64
core-testing-debug/os/x86_64
extra-testing/os/x86_64
extra-testing-debug/os/x86_64
core/os/x86_64
core-debug/os/x86_64
extra/os/x86_64
extra-debug/os/x86_64
"

function get_package_urls() {
  local package_name="${1}"
  local dbg_package_name="${package_name}-debug"
  local url=${2:-$URL}

  find . -name "index.html*" -exec grep -o "${url}.*/\(${package_name}-[0-9].*-x86_64.pkg.tar.zst\|${dbg_package_name}-[0-9].*-x86_64.pkg.tar.zst\)\"" {} \; | \
  cut -d'"' -f1
}

function get_package_indexes() {
  echo "${REPOS}" | while read line; do
    [ -z "${line}" ] && continue
    printf "${URL}/${line}/\n"
  done | sort -u > indexes.txt
}

function fetch_packages() {
  get_package_indexes

  ${WGET} -o wget_packages_urls.log -k -i indexes.txt

  find . -name "index.html*" | while read path; do
    mv "${path}" "${path}.bak"
    xmllint --nowarning --format --html --output "${path}" "${path}.bak" 2>/dev/null
    rm -f "${path}.bak"
  done

  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> unfiltered-packages.txt
  done

  find . -name "index.html*" -exec rm -f {} \;

  touch packages.txt
  cat unfiltered-packages.txt | while read line; do
    local package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
    if ! grep -q -F "${package_name}" SHA256SUMS; then
      echo "${line}" >> packages.txt
    fi
  done

  sort packages.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
}

function get_version() {
  local package_name="${1}"
  local filename="${2}"

  local version="${filename##${package_name}-}"
  version="${version%%.pkg.tar.zst}"
  printf "${version}"
}

function find_debuginfo_package() {
  local package_name="${1}"
  local version="${2}"
  find downloads -name "${package_name}-debug-${version}.pkg.tar.zst" -type f
}

function unpack_package() {
  local package_path="${1}"
  local debug_package_path="${2}"

  mkdir packages debug-packages
  tar -C packages -x -a -f "${package_path}"

  if [ -n "${debug_package_path}" ]; then
    tar -C debug-packages -x -a -f "${debug_package_path}"
  fi
}

function remove_temp_files() {
  rm -rf downloads symbols packages debug-packages tmp \
         symbols*.zip indexes.txt packages.txt unfiltered-packages.txt \
         crashes.list symbols.list
}

remove_temp_files
mkdir -p downloads symbols tmp

packages="
amdvlk
apitrace
atk
at-spi2-atk
at-spi2-core
cairo
dbus
dbus-glib
dconf
egl-wayland
expat
ffmpeg
firefox
firefox-developer-edition
gcc-libs
gdk-pixbuf2
glib2
glibc
gperftools
gtk3
gvfs
highway
intel-gmmlib
intel-media-driver
jemalloc
libcloudproviders
libcups
libdrm
libevent
libffi
libglvnd
libibus
libice
libp11-kit
libpipewire
libpulse
libsm
libspeechd
libva
libva-mesa-driver
libva-nvidia-driver
libva-vdpau-driver
libx11
libxcb
libxext
libxkbcommon
llvm-libs
mesa
nspr
nss
numactl
nvidia-utils
opencl-nvidia
pango
pcre2
pipewire
pixman
systemd-libs
vulkan-icd-loader
vulkan-intel
vulkan-nouveau
vulkan-radeon
vulkan-swrast
wayland
x264
x265
zvbi
"

fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  find downloads -name "${package_name}-[0-9]*.pkg.tar.zst" -type f | while read package; do
    local package_filename="${package##downloads/}"
    local version=$(get_version "${package_name}" "${package_filename}")
    local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}")

    truncate -s 0 error.log

    if [ -n "${debuginfo_package}" ]; then
      unpack_package "${package}" "${debuginfo_package}"
    else
      printf "***** Could not find debuginfo for ${package_filename}\n"
      unpack_package "${package}"
    fi

    find packages -type f | while read path; do
      if file "${path}" | grep -q ": *ELF" ; then
        local debuginfo_path="$(find_debuginfo "${path}")"

        local tmpfile=$(mktemp --tmpdir=tmp)
        printf "Writing symbol file for ${path} ${debuginfo_path} ... "
        if [ -n "${debuginfo_path}" ]; then
          ${DUMP_SYMS} --inlines "${path}" "${debuginfo_path}" 1> "${tmpfile}" 2> error.log
        else
          ${DUMP_SYMS} --inlines "${path}" 1> "${tmpfile}" 2> error.log
        fi

        if [ -s "${tmpfile}" -a -z "${debuginfo_path}" ]; then
          printf "done w/o debuginfo\n"
        elif [ -s "${tmpfile}" ]; then
          printf "done\n"
        else
          printf "something went terribly wrong!\n"
        fi

        if [ -s error.log ]; then
          printf "***** error log for package ${package} ${path} ${debuginfo_path}\n"
          cat error.log
          printf "***** error log for package ${package} ${path} ${debuginfo_path} ends here\n"
        fi

        # Copy the symbol file
        local debugid=$(head -n 1 "${tmpfile}" | cut -d' ' -f4)
        local filename="$(basename "${path}")"
        mkdir -p "symbols/${filename}/${debugid}"
        cp "${tmpfile}" "symbols/${filename}/${debugid}/${filename}.sym"
        local soname=$(get_soname "${path}")
        if [ -n "${soname}" ]; then
          if [ "${soname}" != "${filename}" ]; then
            mkdir -p "symbols/${soname}/${debugid}"
            cp "${tmpfile}" "symbols/${soname}/${debugid}/${soname}.sym"
          fi
        fi

        rm -f "${tmpfile}"
      fi
    done

    rm -rf packages debug-packages
  done
}

echo "${packages}" | while read line; do
  [ -z "${line}" ] && continue
  process_packages ${line}
done

create_symbols_archive

upload_symbols

reprocess_crashes

update_sha256sums

remove_temp_files
