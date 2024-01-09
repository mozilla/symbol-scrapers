#!/bin/sh

. $(dirname $0)/../common.sh

URL="https://ftp.lysator.liu.se/pub/opensuse"

REPOS="
debug/distribution/leap/15.3/repo/oss/x86_64
debug/distribution/leap/15.4/repo/oss/x86_64

debug/update/leap/15.3/oss/x86_64
debug/update/leap/15.3-test/oss/x86_64
debug/update/leap/15.4/oss/x86_64
debug/update/leap/15.4-test/oss/x86_64

distribution/leap/15.3/repo/oss/x86_64
distribution/leap/15.4/repo/oss/x86_64

tumbleweed/repo/oss/x86_64
tumbleweed/repo/debug/x86_64

update/leap/15.3/oss/x86_64/
update/leap/15.3-test/oss/x86_64/
update/leap/15.4/oss/x86_64/
update/leap/15.4-test/oss/x86_64

repositories/mozilla/openSUSE_Leap_15.3/x86_64
repositories/mozilla/openSUSE_Leap_15.3_debug/x86_64
repositories/mozilla/openSUSE_Leap_15.4/x86_64
repositories/mozilla/openSUSE_Leap_15.4_debug/x86_64
repositories/mozilla/openSUSE_Tumbleweed/x86_64
"

URL2="https://ftp.gwdg.de/pub/linux/misc/packman/suse"

REPOS2="
openSUSE_Leap_15.3/Essentials/x86_64
openSUSE_Leap_15.4/Essentials/x86_64
openSUSE_Tumbleweed/Essentials/x86_64
"

get_package_urls() {
  local package_name="${1}"
  local dbg_package_name="${package_name}-debuginfo"
  local url=${2:-$URL}

  find . -name "index.html*" -exec grep -o "${url}.*/\(${package_name}-[0-9].*.x86_64.rpm\|${dbg_package_name}-[0-9].*.x86_64.rpm\)\"" {} \; | \
  cut -d'"' -f1 | \
  grep -v 32bit
}

get_package_indexes() {
  echo "${REPOS}" | while read line; do
    [ -z "${line}" ] && continue
    printf "${URL}/${line}/\n"
  done | sort -u > indexes.txt

  echo "${REPOS2}" | while read line; do
    [ -z "${line}" ] && continue
    printf "${URL2}/${line}/\n"
  done | sort -u >> indexes.txt
}

fetch_packages() {
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
  version="${version%%.rpm}"
  printf "${version}"
}

function find_debuginfo_package() {
  package_name="${1}"
  version="${2}"
  find downloads -name "${package_name}-debuginfo-${version}.rpm" -type f
}

function get_build_id {
  eu-readelf -n "${1}" | grep "^    Build ID:" | cut -b15-
}

function find_debuginfo() {
  local buildid=$(get_build_id "${1}")
  local prefix=$(echo "${buildid}" | cut -b1-2)
  local suffix=$(echo "${buildid}" | cut -b3-)
  local debuginfo=$(find packages -path "*/${prefix}/${suffix}*.debug" | head -n1)
  if [ -e "${debuginfo}" ]; then
    printf "${debuginfo}"
  else
    find packages/usr/lib/debug -name $(basename "${1}")-"${2}".debug -type f | head -n 1
  fi
}

function get_soname {
  local path="${1}"
  local soname=$(objdump -p "${path}" | grep "^  SONAME *" | cut -b24-)
  if [ -n "${soname}" ]; then
    printf "${soname}"
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
alsa
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
libatk-1_0-0
libatk-bridge-2_0-0
libavcodec[0-9][0-9]
libavfilter[0-9]
libavformat[0-9][0-9]
libavresample[0-9]
libavutil[0-9][0-9]
libcairo2
libdbus-1-3
libdconf1
libdrm2
libdrm_amdgpu1
libdrm_intel1
libdrm_nouveau2
libdrm_radeon1
libepoxy0
libevent-2_1-7
libfam0-gamin
libffi8
libfreetype6
libfribidi0
libgbm1
libgdk_pixbuf-2_0-0
libgio-2_0-0
libgio-fam
libglib-2_0-0
libglvnd
libgobject-2_0-0
libgtk-2_0-0
libgtk-3-0
libibus-1_0-5
libICE6
libicu[0-9][0-9]
libigdgmm12
libnuma1
libopus0
libpango-1_0-0
libpcre1
libpcre2-8-0
libpcslite1
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
Mesa-dri
Mesa-dri-nouveau
Mesa-gallium
Mesa-libEGL1
Mesa-libGL1
Mesa-libva
MozillaFirefox
mozilla-nspr
mozilla-nss
openCryptoki-64bit
opensc
libp11-kit0
speech-dispatcher
x11-video-nvidiaG[0-9][0-9]
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
  find downloads -name "${package_name}-[0-9]*.rpm" -type f | grep -v debuginfo | while read package; do
    local package_filename="${package##downloads/}"
    if ! grep -q -F "${package_filename}" SHA256SUMS; then
      local version=$(get_version "${package_name}" "${package_filename}")
      local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}")

      truncate --size=0 error.log

      if [ -n "${debuginfo_package}" ]; then
        unpack_rpm_package ${package} ${debuginfo_package}
      else
        printf "***** Could not find debuginfo for ${package_filename}\n"
        unpack_rpm_package ${package}
      fi

      find packages -type f | grep -v debug | while read path; do
        if file "${path}" | grep -q ": *ELF" ; then
          local debuginfo_path="$(find_debuginfo "${path}" "${version}")"

          [ -z "${debuginfo_path}" ] && printf "Could not find debuginfo for ${path}\n" && continue

          local tmpfile=$(mktemp --tmpdir=tmp)
          printf "Writing symbol file for ${path} ${debuginfo_path} ... "
          ${DUMP_SYMS} --type elf "${path}" "${debuginfo_path}" 1> "${tmpfile}" 2> error.log
          if [ -s "${tmpfile}" ]; then
            printf "done\n"
          else
            ${DUMP_SYMS} --type elf "${path}" > "${tmpfile}"
            if [ -s "${tmpfile}" ]; then
              printf "done w/o debuginfo\n"
            else
              printf "something went terribly wrong!\n"
            fi
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
