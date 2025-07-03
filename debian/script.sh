#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.debian.net/"

. $(dirname $0)/../common.sh

POOLS="
http://deb.debian.org/debian-debug/pool
http://deb.debian.org/debian/pool
http://deb.debian.org/debian-security-debug/pool/updates
http://deb.debian.org/debian-security/pool/updates
https://debian-mirrors.sdinet.de/deb-multimedia/pool
"

AREAS="
contrib
main
non-free
"

ARCHITECTURES="
i386
amd64
"

# <top-level package folder> <package folder> <package name>
PACKAGES="
apitrace-tracers a/apitrace
dconf-gsettings-backend d/dconf
firefox-esr f/firefox-esr
firefox f/firefox
glib-networking g/glib-networking
gvfs g/gvfs
intel-media-va-driver i/intel-media-driver
intel-media-va-driver-non-free i/intel-media-driver-non-free
libasound2 a/alsa-lib
libasound2t64 a/alsa-lib
libatk1.0-0 a/atk1.0
libatk1.0-0t64 a/atk1.0
libatk-bridge2.0-0 a/at-spi2-atk
libatk-bridge2.0-0 a/at-spi2-core
libatk-bridge2.0-0t64 a/at-spi2-atk
libatk-bridge2.0-0t64 a/at-spi2-core
libatspi2.0-0 a/at-spi2-core
libatspi2.0-0t64 a/at-spi2-core
libavcodec[0-9][0-9] f/ffmpeg
libavcodec[0-9][0-9] f/ffmpeg-dmo
libavutil[0-9][0-9] f/ffmpeg
libavutil[0-9][0-9] f/ffmpeg-dmo
libc6 g/glibc
libcairo2 c/cairo
libcloudproviders0 libc/libcloudproviders
libcuda1 n/nvidia-graphics-drivers
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
libegl-nvidia0 n/nvidia-graphics-drivers
libepoxy0 libe/libepoxy
libevent-2.[0-9]-[0-9] libe/libevent
libevent-2.[0-9]-[0-9]t64 libe/libevent
libexpat1 e/expat
libfam0 f/fam
libffi[0-9] libf/libffi
libfontconfig1 f/fontconfig
libfreetype6 f/freetype
libfribidi0 f/fribidi
libgamin0 g/gamin
libgbm1 m/mesa
libgcc-s1 g/gcc-[0-9][0-9]
libgdk-pixbuf-2.0-0 g/gdk-pixbuf
libgdk-pixbuf2.0-0 g/gdk-pixbuf
libgl1-mesa-dri m/mesa
libgl1-nvidia-glvnd-glx n/nvidia-graphics-drivers
libgles-nvidia1 n/nvidia-graphics-drivers
libgles-nvidia2 n/nvidia-graphics-drivers
libglib2.0-0 g/glib2.0
libglib2.0-0t64 g/glib2.0
libglx0 libg/libglvnd
libglx-mesa0 m/mesa
libglx-nvidia0 n/nvidia-graphics-drivers
libgtk-3-0 g/gtk+3.0
libgtk-3-0t64 g/gtk+3.0
libhwy1 h/highway
libhwy1t64 h/highway
libibus-1.0-5 i/ibus
libice6 libi/libice
libicu[0-9][0-9] i/icu
libjemalloc2 j/jemalloc
libllvm[0-9][0-9] l/llvm-toolchain-[0-9][0-9]
libnspr4 n/nspr
libnss3 n/nss
libnss-ldap libn/libnss-ldap
libnuma1 n/numactl
libnvcuvid1 n/nvidia-graphics-drivers
libnvidia-allocator1 n/nvidia-graphics-drivers
libnvidia-eglcore n/nvidia-graphics-drivers
libnvidia-egl-gbm1 n/nvidia-egl-gbm
libnvidia-glcore n/nvidia-graphics-drivers
libnvidia-glvkspirv n/nvidia-graphics-drivers
libopus0 o/opus libopus
libpango-1.0-0 p/pango1.0
libpangoft2-1.0-0 p/pango1.0
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
libstdc++6 g/gcc-[0-9][0-9]
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
thunderbird t/thunderbird
vdpau-va-driver v/vdpau-video
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
  local package_folder_list=$(echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f2 | cut -d'/' -f2 | sort -u | tr '\n' '\|' | sed 's/\+/\\+/g')
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
