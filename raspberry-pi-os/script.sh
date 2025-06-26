#!/bin/sh

# No debuginfo server for rpi-os
export DEBUGINFOD_URLS=""

. $(dirname $0)/../common.sh

# Unified repository used for debug symbol packages
POOLS="
https://archive.raspberrypi.com/debian/pool
"

AREAS="
beta
main
untested
"

ARCHITECTURES="
armhf
arm64
"

# Note that the 64-bit rpi-os repository doesn't mirror all packages from
# arm64 debian, only those specifically packaged for rpi-os or with downstream
# patches.
PACKAGES="
firefox f/firefox
libasound2 a/alsa-lib
libatk1.0-0 a/atk1.0
libatk-bridge2.0-0 a/at-spi2-core
libatspi2.0-0 a/at-spi2-core
libavcodec[0-9][0-9] f/ffmpeg
libavutil[0-9][0-9] f/ffmpeg
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
mesa-libgallium m/mesa
mesa-va-drivers m/mesa
mesa-vulkan-drivers m/mesa
zlib1g z/zlib
"

function get_area_regex() {
  local area_regex=$(echo ${AREAS} | tr ' ' '\|')
  printf "(${area_regex})"
}

function get_architecture_escaped_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | sed -e "s/ /\\\|/")
  printf "\(${architecture_list}\)"
}

function get_top_level_folder_regex() {
  local top_level_folder_regex=$(echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f2 | cut -d'/' -f1 | sort -u | tr '\n' '\|')
  printf "(${top_level_folder_regex%%|})"
}

function get_package_folder_regex() {
  local package_folder_list=$(echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f2 | cut -d'/' -f2 | sort -u | tr '\n' '\|')
  printf "(${package_folder_list%%|})"
}

function fetch_indexes() {
  local area_regex=$(get_area_regex)
  local top_level_folder_regex=$(get_top_level_folder_regex)
  local package_folder_regex=$(get_package_folder_regex)

  echo "${POOLS}" | while read url; do
    [ -z "${url}" ] && continue
    local regex="${url}/(${area_regex}/)?(${top_level_folder_regex}/)?(${package_folder_regex}/)?$"
    ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive --accept-regex "${regex}" "${url}/"
  done
}

function get_package_urls() {
  truncate -s 0 all-packages.txt unfiltered-packages.txt

  find indexes -name index.html -exec xmllint --html --xpath '//a/@href' {} \; 2>xmllint_error.log | \
    grep -o "https\?://.*\.deb" | sort -u >> all-packages.txt

  local architecture_escaped_regex=$(get_architecture_escaped_regex)
  echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f1 | while read package; do
    grep -o "https\?://.*/${package}\(-dbg\(sym\)\?\)\?_[^\_]*_${architecture_escaped_regex}\.deb" all-packages.txt >> unfiltered-packages.txt
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

  local version="${filename##${package_name}_}"
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
  local data_file=$(ar t "${package_name}" | grep ^data)
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

function process_packages() {
  local package_name="${1}"
  for arch in ${ARCHITECTURES}; do
    find downloads -name "${package_name}_[0-9]*_${arch}.deb" -type f | grep -v dbg | while read package; do
      local package_filename="${package##downloads/}"
      local version=$(get_version "${package_name}" "${package_filename}")
      local debug_package_name="${package_name}"
      printf "package_name = ${package_name} version = ${version} dbg_package_name = ${debug_package_name}\n"
      local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}" "${debug_package_name}")

      if [ -n "${debuginfo_package}" ]; then
        unpack_package "${package}" "${debuginfo_package}"
      else
        printf "***** Could not find debuginfo for ${package_filename}\n"
        unpack_package "${package}"
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

      rm -rf packages
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
