#!/bin/sh

# No debuginfo server for rpi-os
export DEBUGINFOD_URLS=""

. $(dirname $0)/../common.sh

# Unified repository used for debug symbol package
URL="https://archive.raspberrypi.com/debian/pool"
DDEB_URL=$URL

# No separate updates repository
UPDATES_URL=""
DDEB_UPDATES_URL=""

get_package_urls() {
  local package_name="${1}"
  local pkg_path="${2}"
  local main_path="main/${pkg_path}"
  local dbg_package_name="${3:-$package_name}"
  local dbgsym_package_name="${4:-$package_name}"
  local alt_url="${5:-$UPDATES_URL}"
  local url="${URL}"
  local ddeb_url="${DDEB_URL}"
  local ddeb_alt_url="${DDEB_UPDATES_URL}"

  local urls="${url}/${main_path}/ ${ddeb_url}/${main_path}/"

  if [ -n "${alt_url}" ]; then
    urls="${urls} ${alt_url}/${main_path}/ ${ddeb_alt_url}/${main_path}/"
  fi

  ${WGET} -o wget_packages_urls.log -k ${urls}

  find . -name "index.html*" -exec grep -o "${url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(armhf\|arm64\).deb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${url}/${non_free_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(armhf\|arm64\).deb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${ddeb_url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(armhf\|arm64\).deb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${ddeb_url}/${non_free_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(armhf\|arm64\).deb\"" {} \; | cut -d'"' -f1

  if [ -n "${alt_url}" ]; then
    find . -name "index.html*" -exec grep -o "${alt_url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(armhf\|arm64\).deb\"" {} \; | cut -d'"' -f1
    find . -name "index.html*" -exec grep -o "${ddeb_alt_url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(armhf\|arm64\).deb\"" {} \; | cut -d'"' -f1
  fi

  find . -name "index.html*" -exec rm -f {} \;
}

fetch_packages() {
  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    echo "Fetching ${line}"
    get_package_urls ${line} >> unfiltered-packages.txt
  done

  touch packages.txt
  cat unfiltered-packages.txt | while read line; do
    package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
    if ! grep -q -s -F "${package_name}" SHA256SUMS; then
      echo "${line}" >> packages.txt
    fi
  done

  sed -i -e 's/%2b/+/g' packages.txt
  sort packages.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
}

function get_version() {
  package_name="${1}"
  filename="${2}"

  version="${filename##${package_name}_}"
  version="${version%%.deb}"
  printf "${version}"
}

function find_debuginfo_package() {
  local package_name="${1}"
  local version="${2}"
  local dbg_package_name="${3}"
  local result=$(find downloads -name "${dbg_package_name}-dbg_${version}.deb" -type f)
  if [ -z "${result}" ]; then
    result=$(find downloads -name "${package_name}-dbgsym_${version}.deb" -type f)
  fi
  printf "${result}\n"
}

function unpack_package() {
  local package_name="${1}"
  local debug_package_name="${2}"
  mkdir packages
  data_file=$(ar t "${package_name}" | grep ^data)
  ar x "${package_name}" "${data_file}" && \
  tar -C packages -x -a -f "${data_file}"
  if [ $? -ne 0 ]; then
    printf "Failed to extract ${package_name}\n" 2>>error.log
  fi
  rm -f "${data_file}"
  if [ -n "${debug_package_name}" ]; then
    data_file=$(ar t "${package_name}" | grep ^data)
    ar x "${debug_package_name}" "${data_file}" && \
    tar -C packages -x -a -f "${data_file}"
    if [ $? -ne 0 ]; then
      printf "Failed to extract ${debug_package_name}\n" 2>>error.log
    fi
    rm -f "${data_file}"
  fi
}

function remove_temp_files() {
  rm -rf downloads symbols packages debug-packages tmp \
         symbols*.zip indexes.txt packages.txt unfiltered-packages.txt \
         crashes.list symbols.list
}

echo "Cleaning up temporary files..."
remove_temp_files
mkdir -p downloads symbols tmp

# Note that the 64-bit rpi-os repository doesn't mirror all packages from
# arm64 debian, only those specifically packaged for rpi-os or with downstream
# patches.
packages="
firefox f/firefox
libasound2 a/alsa-lib
libatk1.0-0 a/atk1.0
libatk-bridge2.0-0 a/at-spi2-core
libatspi2.0-0 a/at-spi2-core
libavcodec58 f/ffmpeg
libavcodec59 f/ffmpeg
libavutil56 f/ffmpeg
libavutil57 f/ffmpeg
libc6 g/glibc
libcairo2 c/cairo
libdrm2 libd/libdrm
libegl-mesa0 m/mesa
libgbm1 m/mesa
libgl1-mesa-dri m/mesa
libglx-mesa0 m/mesa
libgtk-3-0 g/gtk+3.0
libpipewire-0.3-0 p/pipewire
libpixman-1-0 p/pixman
libpulse0 p/pulseaudio
libspa-0.2-modules p/pipewire
libspeechd2 s/speech-dispatcher
libwayland-client0 w/wayland
mesa-va-drivers m/mesa
mesa-vulkan-drivers m/mesa
zlib1g z/zlib
"

echo "Fetching packages..."
fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  for arch in armhf arm64; do
    find downloads -name "${package_name}_[0-9]*_${arch}.deb" -type f | grep -v dbg | while read package; do
      local package_filename="${package##downloads/}"
      local version=$(get_version "${package_name}" "${package_filename}")
      local debug_package_name="${3:-$package_name}"
      printf "package_name = ${package_name} version = ${version} dbg_package_name = ${debug_package_name}\n"
      local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}" "${debug_package_name}")

      if [ -n "${debuginfo_package}" ]; then
        unpack_package ${package} ${debuginfo_package}
      else
        printf "***** Could not find debuginfo for ${package_filename}\n"
        unpack_package ${package}
      fi

      find packages -type f | grep -v debug | while read path; do
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

      rm -rf packages
    done
  done
}

echo "Processing packages..."
echo "${packages}" | while read line; do
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
