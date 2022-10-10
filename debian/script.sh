#!/bin/sh

. $(dirname $0)/../common.sh

URL="http://ftp.nl.debian.org/debian/pool"
UPDATES_URL="http://security-cdn.debian.org/debian-security/pool/updates"
DDEB_URL="http://debug.mirrors.debian.org/debian-debug/pool"

get_package_urls() {
  local package_name="${1}"
  local pkg_path="${2}"
  local main_path="main/${pkg_path}"
  local non_free_path="non-free/${pkg_path}"
  local dbg_package_name="${3:-$package_name}"
  local dbgsym_package_name="${4:-$package_name}"
  local alt_url="${5:-$UPDATES_URL}"
  local url="${URL}"
  local ddeb_url="${DDEB_URL}"

  local urls="${url}/${main_path}/ ${url}/${non_free_path}/ ${ddeb_url}/${main_path}/ ${ddeb_url}/${non_free_path}/"

  if [ -n "${alt_url}" ]; then
    urls="${urls} ${alt_url}/${main_path}/"
  fi

  wget -o wget_packages_urls.log --progress=dot:mega -k ${urls}
  for i in ${urls}; do
    find . -name "index.html*" -exec grep -o "${i}\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(i386\|amd64\).deb\"" {} \; | cut -d'"' -f1
  done
  find . -name "index.html*" -exec rm -f {} \;
}

fetch_packages() {
  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> packages.txt
  done

  sed -i -e 's/%2b/+/g' packages.txt
  sort packages.txt | wget -o wget_packages.log --progress=dot:mega -P downloads -c -i -
  rev packages.txt | cut -d'/' -f1 | rev > package_names.txt
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
  ar x "${package_name}" && \
  tar -C packages -x -a -f "${data_file}"
  if [ $? -ne 0 ]; then
    printf "Failed to extract ${package_name}\n" 2>>error.log
  fi
  rm -f data.tar* control.tar* debian-binary
  if [ -n "${debug_package_name}" ]; then
    data_file=$(ar t "${package_name}" | grep ^data)
    ar x "${debug_package_name}" && \
    tar -C packages -x -a -f "${data_file}"
    if [ $? -ne 0 ]; then
      printf "Failed to extract ${debug_package_name}\n" 2>>error.log
    fi
    rm -f data.tar* control.tar* debian-binary
  fi
}

function remove_temp_files() {
  rm -rf symbols packages tmp symbols*.zip packages.txt package_names.txt
}

function generate_fake_packages() {
  cat SHA256SUMS | while read line; do
    local package_name=$(echo ${line} | cut -d',' -f1)
    local package_size=$(echo ${line} | cut -d',' -f2)
    truncate --size "${package_size}" "downloads/${package_name}"
  done
}

remove_temp_files
mkdir -p downloads symbols tmp
generate_fake_packages

packages="
apitrace-tracers a/apitrace
dconf-gsettings-backend d/dconf
firefox-esr f/firefox-esr
firefox f/firefox
glib-networking g/glib-networking
gvfs g/gvfs
intel-media-va-driver i/intel-media-driver
intel-media-va-driver-non-free i/intel-media-driver-non-free
libasound2 a/alsa-lib
libatk1.0-0 a/atk1.0
libatk-bridge2.0-0 a/at-spi2-atk
libatspi2.0-0 a/at-spi2-core
libavcodec[0-9][0-9] f/ffmpeg
libavcodec[0-9][0-9] f/ffmpeg-dmo libavcodec[0-9][0-9] libavcodec[0-9][0-9] http://mirror.home-dn.net/debian-multimedia/pool
libavutil[0-9][0-9] f/ffmpeg
libavutil[0-9][0-9] f/ffmpeg-dmo libavutil[0-9][0-9] libavutil[0-9][0-9] http://mirror.home-dn.net/debian-multimedia/pool
libc6 g/glibc
libcairo2 c/cairo
libcups2 c/cups
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
libgdk-pixbuf-2.0-0 g/gdk-pixbuf
libgdk-pixbuf2.0-0 g/gdk-pixbuf
libgl1-mesa-dri m/mesa
libglib2.0-0 g/glib2.0
libglx0 libg/libglvnd
libglx-mesa0 m/mesa
libgtk-3-0 g/gtk+3.0
libibus-1.0-5 i/ibus
libice6 libi/libice
libicu[0-9][0-9] i/icu
libnspr4 n/nspr
libnss3 n/nss
libnss-ldap libn/libnss-ldap
libnuma1 n/numactl
libopus0 o/opus libopus
libpango-1.0-0 p/pango1.0
libpcre2-8-0 p/pcre2
libpcre3 p/pcre3
libpcsclite1 p/pcsc-lite
libpipewire-0.3-0 p/pipewire
libpixman-1-0 p/pixman
libpng12-0 libp/libpng
libpng16-16 libp/libpng1.6
libproxy1-plugin-gsettings libp/libproxy
libproxy1v5 libp/libproxy
libpulse0 p/pulseaudio
libsm6 libs/libsm
libspa-0.2-modules p/pipewire
libspeechd2 s/speech-dispatcher
libsqlite3-0 s/sqlite3
libstdc++6 g/gcc-10 libstdc++6-10
libstdc++6 g/gcc-11 libstdc++6-11
libstdc++6 g/gcc-12 libstdc++6-12
libsystemd0 s/systemd
libtcmalloc-minimal4 g/google-perftools
libthai0 libt/libthai
libva2 libv/libva
libvpx[0-9] libv/libvpx
libwayland-client0 w/wayland
libx11-6 libx/libx11
libx264-[0-9][0-9][0-9] x/x264
libx265-[0-9][0-9][0-9] x/x265
libxcb1 libx/libxcb
libxext6 libx/libxext
libxkbcommon0 libx/libxkbcommon
libxml2 libx/libxml2
libxss1 libx/libxss
libxvidcore4 x/xvidcore
mesa-va-drivers m/mesa
mesa-vulkan-drivers m/mesa
opensc-pkcs11 o/opensc
p11-kit-modules p/p11-kit
thunderbird t/thunderbird
vdpau-va-driver v/vdpau-video
zlib1g z/zlib
"

fetch_packages "${packages}"

function add_package_to_list() {
  local package_filename=$(basename "${1}")
  local package_size=$(stat -c"%s" "${1}")
  printf "${package_filename},${package_size}\n" >> SHA256SUMS
  truncate --size 0 "${1}"
  truncate --size "${package_size}" "${1}"

  if [ -n "${2}" ]; then
    local debuginfo_package_filename=$(basename "${2}")
    local debuginfo_package_size=$(stat -c"%s" "${2}")
    printf "${debuginfo_package_filename},${debuginfo_package_size}\n" >> SHA256SUMS
    truncate --size 0 "${2}"
    truncate --size "${debuginfo_package_size}" "${2}"
  fi
}

function process_packages() {
  local package_name="${1}"
  for arch in i386 amd64; do
    find downloads -name "${package_name}_[0-9]*_${arch}.deb" -type f | grep -v dbg | while read package; do
      local package_filename="${package##downloads/}"
      if ! grep -q -F "${package_filename}" SHA256SUMS; then
        local version=$(get_version "${package_name}" "${package_filename}")
        local debug_package_name="${3:-$package_name}"
        printf "package_name = ${package_name} version = ${version} dbg_package_name = ${debug_package_name}\n"
        local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}" "${debug_package_name}")

        truncate --size=0 error.log

        if [ -n "${debuginfo_package}" ]; then
          unpack_package ${package} ${debuginfo_package}
        else
          printf "***** Could not find debuginfo for ${package_filename}\n"
          unpack_package ${package}
        fi

        find packages -type f | grep -v debug | while read path; do
          if file "${path}" | grep -q ": *ELF" ; then
            local debuginfo_path="$(find_debuginfo "${path}")"

            [ -z "${debuginfo_path}" ] && printf "Could not find debuginfo for ${path}\n" && continue

            local tmpfile=$(mktemp --tmpdir=tmp)
            printf "Writing symbol file for ${path} ${debuginfo_path} ... "
            ${DUMP_SYMS} --inlines "${path}" "${debuginfo_path}" 1> "${tmpfile}" 2>>error.log
            if [ -s "${tmpfile}" ]; then
              printf "done\n"
            else
              ${DUMP_SYMS} --inlines "${path}" > "${tmpfile}"
              if [ -s "${tmpfile}" ]; then
                printf "done w/o debuginfo\n"
              else
                printf "something went terribly wrong!\n"
              fi
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

        if [ -s error.log ]; then
          printf "***** error log for package ${package}\n"
          cat error.log
          printf "***** error log for package ${package} ends here\n"
        fi

        rm -rf packages
        add_package_to_list "${package}" "${debuginfo_package}"
      fi
    done
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
