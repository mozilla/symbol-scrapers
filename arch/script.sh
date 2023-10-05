#!/bin/bash

export DEBUGINFOD_URLS="https://debuginfod.archlinux.org/"

. $(dirname $0)/../common.sh

URL="https://geo.mirror.pkgbuild.com"

REPOS="
community/os/x86_64
community-debug/os/x86_64
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

  wget -o wget_packages_urls.log --progress=dot:mega --compression=auto -k -i indexes.txt

  find . -name "index.html*" | while read path; do
    mv "${path}" "${path}.bak"
    xmllint --nowarning --format --html --output "${path}" "${path}.bak" 2>/dev/null
    rm -f "${path}.bak"
  done

  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> packages.txt
  done

  find . -name "index.html*" -exec rm -f {} \;

  wget -o wget_packages.log --progress=dot:mega -P downloads -c -i packages.txt

  rev packages.txt | cut -d'/' -f1 | rev > package_names.txt
}

function get_version() {
  package_name="${1}"
  filename="${2}"

  version="${filename##${package_name}-}"
  version="${version%%.pkg.tar.zst}"
  printf "${version}"
}

function find_debuginfo_package() {
  package_name="${1}"
  version="${2}"
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

function find_debuginfo() {
  local buildid=$(get_build_id "${1}")
  local debuginfo=$(debuginfod-find debuginfo "${buildid}" 2>/dev/null)

  if [ \( $? -eq 0 \) -a \( -n "${debuginfo}" \) ]; then
    printf "${debuginfo}"
    return
  fi

  local filename="${1##packages}"
  find debug-packages -path "*${filename}.debug" -type f
}

function remove_temp_files() {
  rm -rf symbols packages debug-packages tmp symbols*.zip packages.txt package_names.txt
}

function generate_fake_packages() {
  cat SHA256SUMS | while read line; do
    local package_name=$(echo ${line} | cut -d',' -f1)
    local package_size=$(echo ${line} | cut -d',' -f2)
    truncate -s "${package_size}" "downloads/${package_name}"
  done
}

remove_temp_files
mkdir -p downloads symbols tmp
generate_fake_packages

packages="
amdvlk
apitrace
atk
at-spi2-atk
at-spi2-core
cairo
libcups
dbus
dbus-glib
dconf
egl-wayland
expat
ffmpeg
gcc-libs
gdk-pixbuf2
glib2
glibc
gtk3
gvfs
intel-gmmlib
intel-media-driver
libdrm
libffi
libglvnd
libibus
libice
libp11-kit
libpulse
libsm
libspeechd
libva
libva-mesa-driver
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
pcre2
pipewire
pixman
vulkan-intel
vulkan-radeon
wayland
x264
x265
"

fetch_packages "${packages}"

function add_package_to_list() {
  local package_filename=$(basename "${1}")
  local package_size=$(stat -c"%s" "${1}")
  printf "${package_filename},${package_size}\n" >> SHA256SUMS
  truncate -s 0 "${1}"
  truncate -s "${package_size}" "${1}"

  if [ -n "${2}" ]; then
    local debuginfo_package_filename=$(basename "${2}")
    local debuginfo_package_size=$(stat -c"%s" "${2}")
    printf "${debuginfo_package_filename},${debuginfo_package_size}\n" >> SHA256SUMS
    truncate -s 0 "${2}"
    truncate -s "${debuginfo_package_size}" "${2}"
  fi
}

function process_packages() {
  local package_name="${1}"
  find downloads -name "${package_name}-[0-9]*.pkg.tar.zst" -type f | while read package; do
    local package_filename="${package##downloads/}"
    if ! grep -q -F "${package_filename}" SHA256SUMS; then
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
          debugid=$(head -n 1 "${tmpfile}" | cut -d' ' -f4)
          filename="$(basename "${path}")"
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
      add_package_to_list "${package}" "${debuginfo_package}"
    fi
  done
}

echo "${packages}" | while read line; do
  [ -z "${line}" ] && continue
  process_packages ${line}
done

zip_symbols

upload_symbols

reprocess_crashes

remove_temp_files
