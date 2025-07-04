#!/bin/bash

export DEBUGINFOD_URLS="https://debuginfod.archlinux.org/"

. $(dirname $0)/../common.sh

URL="https://geo.mirror.pkgbuild.com"

REPOS="
core-testing
core-testing-debug
extra-testing
extra-testing-debug
core
core-debug
extra
extra-debug
"

ARCHITECTURES="
x86_64
"

PACKAGES="
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

function get_repo_regex() {
  local repo_regex=$(echo ${REPOS} | tr ' ' '\|')
  printf "(${repo_regex})"
}

function get_architecture_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | tr ' ' '\|')
  printf "(${architecture_list})"
}

function get_architecture_escaped_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | sed -e "s/ /\\\|/")
  printf "\(${architecture_list}\)"
}

function fetch_indexes() {
  local repo_regex=$(get_repo_regex)
  local architecture_regex=$(get_architecture_regex)

  local regex="${URL}/(${repo_regex}/)?(os/)?(${architecture_regex}/)?$"
  ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive --accept-regex "${regex}" "${URL}/"
}

function get_package_urls() {
  truncate -s 0 all-packages.txt unfiltered-packages.txt

  find indexes -name index.html -exec xmllint --html --xpath '//a/@href' {} \; 2>xmllint_error.log | \
    grep -o "https\?://.*\.pkg\.tar\.zst" | sort -u >> all-packages.txt

  local architecture_escaped_regex=$(get_architecture_escaped_regex)
  echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f1 | while read package; do
    grep -o "https\?://.*/${package}\(-debug\)\?-[0-9].*-${architecture_escaped_regex}\.pkg\.tar\.zst" all-packages.txt >> unfiltered-packages.txt
  done
}

function fetch_packages() {
  truncate -s 0 downloads.txt
  cat unfiltered-packages.txt | while read line; do
    local package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
    if ! grep -q -F "${package_name}" SHA256SUMS; then
      echo "${line}" >> downloads.txt
    fi
  done

  sort downloads.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
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

function process_packages() {
  local package_name="${1}"
  for arch in ${ARCHITECTURES}; do
    find downloads -name "${package_name}-[0-9]*-${arch}.pkg.tar.zst" -type f | while read package; do
      local package_filename="${package##downloads/}"
      local version=$(get_version "${package_name}" "${package_filename}")
      printf "package_name = ${package_name} version = ${version}\n"
      local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}")

      if [ -n "${debuginfo_package}" ]; then
        unpack_package "${package}" "${debuginfo_package}"
      else
        printf "***** Could not find debuginfo for ${package_filename}\n"
        unpack_package "${package}"
      fi

      find packages -type f | while read path; do
        if file "${path}" | grep -q ": *ELF" ; then
          local debuginfo_path="$(find_debuginfo "${path}")"

          truncate -s 0 error.log
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

          # Copy the symbol file and debug information
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
  done
}

function remove_temp_files() {
  rm -rf all-packages.txt crashes.list downloads downloads.txt indexes \
         packages symbols symbols.list tmp unfiltered-packages.txt \
         xmllint_error.log
}

echo "Cleaning up temporary files..."
remove_temp_files
mkdir -p downloads indexes symbols tmp

echo "Fetching packages..."
fetch_indexes
get_package_urls
fetch_packages

echo "Processing packages..."
echo "${PACKAGES}" | while read line; do
  [ -z "${line}" ] && continue
  echo "Processing ${line}"
  process_packages ${line}
done

echo "Creating symbols archive..."
create_symbols_archive

echo "Uploading symbols..."
upload_symbols

echo "Reprocessing crashes..."
reprocess_crashes

echo "Updating sha256sums..."
update_sha256sums

echo "Cleaning up temporary files..."
remove_temp_files
