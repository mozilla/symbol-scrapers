#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.opensuse.org/"

. $(dirname $0)/../common.sh

URL="https://download.opensuse.org"

REPOS="
debug/distribution/leap/15.6/repo/oss/x86_64
debug/distribution/leap/16.0/repo/oss/x86_64

debug/update/leap/15.6/oss/x86_64
debug/update/leap/15.6-test/oss/x86_64
debug/update/leap/16.0/oss/x86_64
debug/update/leap/16.0-test/oss/x86_64

distribution/leap/15.6/repo/oss/x86_64
distribution/leap/16.0/repo/oss/x86_64

tumbleweed/repo/oss/x86_64
tumbleweed/repo/debug/x86_64

update/leap/15.6/oss/x86_64/
update/leap/15.6-test/oss/x86_64
update/leap/16.0/oss/x86_64/
update/leap/16.0-test/oss/x86_64

repositories/mozilla/openSUSE_Leap_15.6/x86_64
repositories/mozilla/openSUSE_Leap_15.6_debug/x86_64
repositories/mozilla/openSUSE_Leap_16.0/x86_64
repositories/mozilla/openSUSE_Leap_16.0_debug/x86_64
repositories/mozilla/openSUSE_Tumbleweed/x86_64
repositories/mozilla%3A/Factory/openSUSE_Factory/x86_64
"

URL2="https://ftp.gwdg.de/pub/linux/misc/packman/suse"

REPOS2="
openSUSE_Leap_15.6/Essentials/x86_64
openSUSE_Leap_16.0/Essentials/x86_64
openSUSE_Tumbleweed/Essentials/x86_64
"

URL3="https://download.nvidia.com"

REPOS3="
opensuse/leap/15.6/x86_64
opensuse/leap/16.0/x86_64
opensuse/tumbleweed/x86_64
"

ARCHITECTURES="
x86_64
"

function get_architecture_escaped_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | sed -e "s/ /\\\|/")
  printf "\(${architecture_list}\)"
}

get_package_urls() {
  local package_name="${1}"
  local dbg_package_name="${package_name}-debuginfo"
  local url=${2:-$URL}

  local architecture_escaped_regex=$(get_architecture_escaped_regex)
  find . -name "index.html*" -exec grep -o "${url}.*/\(${package_name}-[0-9].*.${architecture_escaped_regex}.rpm\|${dbg_package_name}-[0-9].*.${architecture_escaped_regex}.rpm\)\"" {} \; | \
  cut -d'"' -f1 | \
  grep -v 32bit
}

get_package_indexes() {
  echo "${REPOS}" | while read line; do
    [ -z "${line}" ] && continue
    echo "${URL}/${line}/"
  done | sort -u > indexes.txt

  echo "${REPOS2}" | while read line; do
    [ -z "${line}" ] && continue
    echo "${URL2}/${line}/"
  done | sort -u >> indexes.txt

  echo "${REPOS3}" | while read line; do
    [ -z "${line}" ] && continue
    echo "${URL3}/${line}/"
  done | sort -u >> indexes.txt
}

fetch_packages() {
  get_package_indexes

  sort indexes.txt | ${WGET} -o wget_packages_urls.log -k -i -

  find . -name "index.html*" | while read path; do
    mv "${path}" "${path}.bak"
    xmllint --nowarning --format --html --output "${path}" "${path}.bak" 2>/dev/null
    rm -f "${path}.bak"
  done

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

  find . -name "index.html*" -exec rm -f {} \;

  sort packages.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
}

function get_version() {
  local package_name="${1}"
  local filename="${2}"

  local version="${filename##${package_name}-}"
  version="${version%%.rpm}"
  printf "${version}"
}

function find_debuginfo_package() {
  local package_name="${1}"
  local version="${2}"
  find downloads -name "${package_name}-debuginfo-${version}.rpm" -type f
}

function remove_temp_files() {
  rm -rf downloads symbols packages debug-packages tmp \
         symbols*.zip indexes.txt packages.txt unfiltered-packages.txt \
         crashes.list symbols.list
}

remove_temp_files
mkdir -p downloads symbols tmp

packages="
alsa
apitrace-wrappers
at-spi2-atk-gtk2
at-spi2-core
dbus-1-glib
firefox-esr
fontconfig
glibc
glib-networking
gnome-vfs2
gsettings-backend-dconf
intel-media-driver
intel-vaapi-driver
libasound2
libatk-1_0-0
libatk-bridge-2_0-0
libavcodec[0-9][0-9]
libavfilter[0-9]
libavformat[0-9][0-9]
libavresample[0-9]
libavutil[0-9][0-9]
libcairo2
libcloudproviders0
libcups2
libdbus-1-3
libdconf1
libdrm2
libdrm_amdgpu1
libdrm_intel1
libdrm_nouveau2
libdrm_radeon1
libepoxy0
libevent-2_1-7
libexpat1
libfam0-gamin
libffi8
libfreetype6
libfribidi0
libgbm1
libgcc_s1
libgdk_pixbuf-2_0-0
libgio-2_0-0
libgio-fam
libglib-2_0-0
libglvnd
libgobject-2_0-0
libgtk-2_0-0
libgtk-3-0
libhwy1
libibus-1_0-5
libICE6
libicu[0-9][0-9]
libigdgmm12
libjemalloc2
libnuma1
libnvidia-egl-wayland1
libnvidia-egl-x111
libopus0
libp11-kit0
libpango-1_0-0
libpcre1
libpcre2-8-0
libpcslite1
libpipewire-0_3-0
libpixman-1-0
libpng12-0
libpng16-16
libpostproc[0-9][0-9]
libproxy1
libproxy1
libproxy1-config-kde
libpulse0
libSM6
libsoftokn3
libsqlite3-0
libstdc++6
libswresample[0-9]
libswscale[0-9]
libsystemd0
libthai0
libva2
libva-vdpau-driver
libvpx4
libvulkan1
libvulkan_intel
libvulkan_radeon
libwayland-client0
libX11-6
libx264-[0-9][0-9][0-9] http://packman.inode.at/suse
libx265-[0-9][0-9][0-9] http://packman.inode.at/suse
libxcb1
libXext6
libxkbcommon0
libxml2-2
libxvidcore4
libz1
libzvbi0
Mesa-dri
Mesa-dri-nouveau
Mesa-gallium
Mesa-libEGL1
Mesa-libGL1
Mesa-libva
MozillaFirefox
mozilla-nspr
mozilla-nss
nvidia-compute-G[0-9][0-9]
nvidia-gl-G[0-9][0-9]
nvidia-glG[0-9][0-9]
nvidia-utils-G[0-9][0-9]
nvidia-video-G[0-9][0-9]
openCryptoki-64bit
opensc
p11-kit
pipewire-spa-plugins-0_2
speech-dispatcher
x11-video-nvidiaG[0-9][0-9]
"

fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  for arch in ${ARCHITECTURES}; do
    find downloads -name "${package_name}-[0-9]*.${arch}.rpm" -type f | grep -v debuginfo | while read package; do
      local package_filename="${package##downloads/}"
      local version=$(get_version "${package_name}" "${package_filename}")
      printf "package_name = ${package_name} version = ${version}\n"
      local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}")

      if [ -n "${debuginfo_package}" ]; then
        unpack_rpm_package ${package} ${debuginfo_package}
      else
        printf "***** Could not find debuginfo for ${package_filename}\n"
        unpack_rpm_package ${package}
      fi

      find packages -type f | grep -v debug | while read path; do
        if file "${path}" | grep -q ": *ELF" ; then
          local debuginfo_path="$(find_debuginfo "${path}" "${version}")"

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
