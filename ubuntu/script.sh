#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

. $(dirname $0)/../common.sh

URL="http://nl.archive.ubuntu.com/ubuntu/pool"
DDEB_URL="http://ddebs.ubuntu.com/pool"

ARCHITECTURES="
i386
amd64
"

function get_architecture_escaped_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | sed -e "s/ /\\\|/")
  printf "\(${architecture_list}\)"
}

get_package_urls() {
  local package_name="${1}"
  local pkg_path="${2}"
  local main_path="main/${pkg_path}"
  local universe_path="universe/${pkg_path}"
  local multiverse_path="multiverse/${pkg_path}"
  local restricted_path="restricted/${pkg_path}"
  local dbg_package_name="${3:-$package_name}"
  local dbgsym_package_name="${4:-$package_name}"
  local alt_url="${5}"
  local url="${URL}"
  local ddeb_url="${DDEB_URL}"

  local urls="${url}/${main_path}/ ${url}/${universe_path}/ ${url}/${multiverse_path}/ ${url}/${restricted_path}/ ${ddeb_url}/${main_path}/ ${ddeb_url}/${universe_path}/ ${ddeb_url}/${multiverse_path}/ ${ddeb_url}/${restricted_path}/"

  if [ -n "${alt_url}" ]; then
    urls="${urls} ${alt_url}/${main_path}/ ${alt_url}/${universe_path}/ ${alt_url}/${multiverse_path}/ ${alt_url}/${restricted_path}/"
  fi

  ${WGET} -o wget_packages_urls.log -k ${urls}
  local architecture_escaped_regex=$(get_architecture_escaped_regex)
  find . -name "index.html*" -exec grep -o "${url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${url}/${universe_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${url}/${multiverse_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${url}/${restricted_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${ddeb_url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${ddeb_url}/${universe_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${ddeb_url}/${multiverse_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec grep -o "${ddeb_url}/${restricted_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1

  if [ -n "${alt_url}" ]; then
    find . -name "index.html*" -exec grep -o "${alt_url}/${main_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
    find . -name "index.html*" -exec grep -o "${alt_url}/${universe_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
    find . -name "index.html*" -exec grep -o "${alt_url}/${multiverse_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
    find . -name "index.html*" -exec grep -o "${alt_url}/${restricted_path}/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_${architecture_escaped_regex}.d.*eb\"" {} \; | cut -d'"' -f1
  fi

  find . -name "index.html*" -exec rm -f {} \;
}

fetch_packages() {
  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> unfiltered-packages.txt
  done

  touch packages.txt
  cat unfiltered-packages.txt | while read line; do
    local package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
    if ! grep -q -F "${package_name}" SHA256SUMS; then
      echo "${line}" >> packages.txt
    fi
  done

  sed -i -e 's/%2b/+/g' packages.txt
  sort packages.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
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
    result=$(find downloads -name "${package_name}-dbgsym_${version}.ddeb" -type f)
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

function remove_temp_files() {
  rm -rf downloads symbols packages debug-packages tmp \
         symbols*.zip indexes.txt packages.txt unfiltered-packages.txt \
         crashes.list symbols.list
}

remove_temp_files
mkdir -p downloads symbols tmp

packages="
apitrace-tracers a/apitrace
dconf-gsettings-backend d/dconf
firefox-esr f/firefox-esr firefox-esr firefox-esr https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu/pool
firefox f/firefox firefox firefox https://ppa.launchpadcontent.net/mozillateam/firefox-next/ubuntu/pool
firefox f/firefox firefox firefox https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu/pool
firefox-trunk f/firefox-trunk firefox-trunk firefox-trunk https://ppa.launchpadcontent.net/ubuntu-mozilla-daily/ppa/ubuntu/pool
glib-networking g/glib-networking
gvfs g/gvfs
intel-media-va-driver i/intel-media-driver
intel-media-va-driver-non-free i/intel-media-driver-non-free
libasound2 a/alsa-lib
libasound2t64 a/alsa-lib
libatk1.0-0 a/atk1.0
libatk1.0-0t64 a/atk1.0
libatk-bridge2.0-0 a/at-spi2-atk
libatk-bridge2.0-0t64 a/at-spi2-atk
libatspi2.0-0 a/at-spi2-core
libatspi2.0-0t64 a/at-spi2-core
libavcodec[0-9][0-9] f/ffmpeg
libavutil[0-9][0-9] f/ffmpeg
libc6 g/glibc
libcairo2 c/cairo
libcloudproviders0 libc/libcloudproviders
libcups2 c/cups
libcups2t64 c/cups
libdbus-1-3 d/dbus
libdbus-glib-1-2 d/dbus-glib
libdrm2 libd/libdrm
libdrm-amdgpu1 libd/libdrm
libdrm-intel1 libd/libdrm
libdrm-nouveau2 libd/libdrm
libdrm-radeon1 libd/libdrm
libegl1 libg/libglvnd
libegl1-mesa-drivers m/mesa
libegl-mesa0 m/mesa
libepoxy0 libe/libepoxy
libevent-2.[0-9]-[0-9] libe/libevent libevent libevent-2.[0-9]-[0-9]
libevent-2.[0-9]-[0-9]t64 libe/libevent libevent libevent-2.[0-9]-[0-9]t64
libexpat1 e/expat
libfam0 f/fam
libffi[0-9] libf/libffi
libfontconfig1 f/fontconfig
libfreetype6 f/freetype
libfribidi0 f/fribidi
libgamin0 g/gamin
libgbm1 m/mesa
libgcc-s1 g/gcc-10
libgcc-s1 g/gcc-11
libgcc-s1 g/gcc-12
libgcc-s1 g/gcc-13
libgcc-s1 g/gcc-14
libgdk-pixbuf-2.0-0 g/gdk-pixbuf
libgdk-pixbuf2.0-0 g/gdk-pixbuf
libgl1-mesa-dri m/mesa
libglib2.0-0 g/glib2.0
libglib2.0-0t64 g/glib2.0
libglx0 libg/libglvnd
libglx-mesa0 m/mesa
libgtk-3-0 g/gtk+3.0
libgtk-3-0t64 g/gtk+3.0
libhwy1 h/highway
libhwy1t64 h/highway
libibus-1.0-5 i/ibus
libice6 libi/libice
libicu[0-9][0-9] i/icu
libjemalloc2 j/jemalloc
libllvm16 l/llvm-toolchain-16
libllvm17 l/llvm-toolchain-17
libllvm18 l/llvm-toolchain-18
libnspr4 n/nspr
libnss3 n/nss
libnss-ldap libn/libnss-ldap
libnuma1 n/numactl
libnvidia-decode-[0-9][0-9][0-9] n/nvidia-graphics-drivers-[0-9][0-9][0-9]
libnvidia-egl-gbm1 n/nvidia-egl-gbm
libnvidia-gl-[0-9][0-9][0-9] n/nvidia-graphics-drivers-[0-9][0-9][0-9]
libnvidia-gl-[0-9][0-9][0-9]-server n/nvidia-graphics-drivers-[0-9][0-9][0-9]-server
libopus0 o/opus libopus
libpango-1.0-0 p/pango1.0
libpcre2-8-0 p/pcre2
libpcre3 p/pcre3
libpcsclite1 p/pcsc-lite
libpipewire-0.3-0 p/pipewire
libpipewire-0.3-0t64 p/pipewire
libpixman-1-0 p/pixman
libpng12-0 libp/libpng
libpng16-16 libp/libpng1.6
libpng16-16t64 libp/libpng1.6
libproxy1-plugin-gsettings libp/libproxy
libproxy1v5 libp/libproxy
libpulse0 p/pulseaudio
libsm6 libs/libsm
libspa-0.2-modules p/pipewire
libspeechd2 s/speech-dispatcher
libsqlite3-0 s/sqlite3
libstdc++6 g/gcc-10
libstdc++6 g/gcc-11
libstdc++6 g/gcc-12
libstdc++6 g/gcc-13
libstdc++6 g/gcc-14
libsystemd0 s/systemd
libtcmalloc-minimal4 g/google-perftools
libtcmalloc-minimal4t64 g/google-perftools
libthai0 libt/libthai
libva2 libv/libva
libvpx[0-9] libv/libvpx
libwayland-client0 w/wayland
libwayland-egl1 w/wayland
libx11-6 libx/libx11
libx264-[0-9][0-9][0-9] x/x264
libx265-[0-9][0-9][0-9] x/x265
libxcb1 libx/libxcb
libxext6 libx/libxext
libxkbcommon0 libx/libxkbcommon
libxml2 libx/libxml2
libxss1 libx/libxss
libxvidcore4 x/xvidcore
libzvbi0 z/zvbi
mesa-va-drivers m/mesa
mesa-vulkan-drivers m/mesa
nvidia-vaapi-driver n/nvidia-vaapi-driver
opensc-pkcs11 o/opensc
p11-kit-modules p/p11-kit
thunderbird t/thunderbird thunderbird thunderbird https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu/pool
vdpau-va-driver v/vdpau-video
zlib1g z/zlib
"

fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  for arch in ${ARCHITECTURES}; do
    find downloads -name "${package_name}_[0-9]*_${arch}.deb" -type f | grep -v dbg | while read package; do
      local package_filename="${package##downloads/}"
      local version=$(get_version "${package_name}" "${package_filename}")
      local debug_package_name="${3:-$package_name}"
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

echo "${packages}" | while read line; do
  [ -z "${line}" ] && continue
  process_packages ${line}
done

create_symbols_archive

upload_symbols

reprocess_crashes

update_sha256sums

remove_temp_files
