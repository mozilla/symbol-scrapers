#!/bin/sh
unalias -a

if [ -z "${DUMP_SYMS}" ]; then
  printf "You must set the \`DUMP_SYMS\` enviornment variable before running the script\n"
  exit 1
fi

if [ -z "${SYMBOLS_API_TOKEN}" ]; then
  printf "You must set the \`SYMBOLS_API_TOKEN\` enviornment variable before running the script\n"
  exit 1
fi

if [ -z "${CRASHSTATS_API_TOKEN}" ]; then
  printf "You must set the \`CRASHSTATS_API_TOKEN\` enviornment variable before running the script\n"
  exit 1
fi

cpu_count=$(grep -c ^processor /proc/cpuinfo)

URL="https://ftp.lysator.liu.se/pub/opensuse"

REPOS="
debug/distribution/leap/15.0/repo/oss/x86_64
debug/distribution/leap/15.1/repo/oss/x86_64
debug/distribution/leap/15.2/repo/oss/x86_64

debug/update/leap/15.0/oss/rpms/x86_64
debug/update/leap/15.1/oss/x86_64
debug/update/leap/15.2/oss/x86_64

distribution/leap/15.0/repo/oss/x86_64
distribution/leap/15.1/repo/oss/x86_64
distribution/leap/15.2/repo/oss/x86_64

tumbleweed/repo/oss/x86_64
tumbleweed/repo/debug/x86_64

update/leap/15.0/oss/rpms/x86_64/
update/leap/15.1/oss/x86_64
update/leap/15.2/oss/x86_64/

repositories/mozilla/openSUSE_Leap_15.0/x86_64
repositories/mozilla/openSUSE_Leap_15.1/x86_64
repositories/mozilla/openSUSE_Leap_15.2/x86_64
repositories/mozilla/openSUSE_Tumbleweed/x86_64
"

URL2="http://packman.inode.at/suse"

REPOS2="
openSUSE_Leap_15.1/Essentials/x86_64
openSUSE_Leap_15.2/Essentials/x86_64
openSUSE_Tumbleweed/Essentials/x86_64
"


get_package_urls() {
  local package_name="${1}"
  local dbg_package_name="${package_name}-debuginfo"
  local url=${2:-$URL}

  grep -h -o "${url}.*/\(${package_name}-[0-9].*.x86_64.rpm\|${dbg_package_name}-[0-9].*.x86_64.rpm\)\"" index.html* | \
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

  wget -o wget.log --progress=dot:mega --compression=auto -k -i indexes.txt

  find . -name "index.html*" | while read path; do
    mv "${path}" "${path}.bak"
    xmllint --nowarning --format --html --output "${path}" "${path}.bak" 2>/dev/null
    rm -f "${path}.bak"
  done

  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> packages.txt
  done

  rm -f index.html*

  wget -o wget.log --progress=dot:mega -P downloads -c -i packages.txt

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

function unpack_package() {
  mkdir packages
  rpm2cpio "${1}" | cpio --quiet -i -d -D packages
  rpm2cpio "${2}" | cpio --quiet -i -d -D packages
}

function get_build_id {
  eu-readelf -n "${1}" | grep "^    Build ID:" | cut -b15-
}

function find_debuginfo() {
  local buildid=$(get_build_id "${1}")
  local prefix=$(echo "${buildid}" | cut -b1-2)
  local suffix=$(echo "${buildid}" | cut -b3-)
  local debuginfo=$(find packages -path "*/${prefix}/${suffix}*.debug" | head -n1)
  printf "${debuginfo}"
}

function get_soname {
  local path="${1}"
  local soname=$(objdump -p "${path}" | grep "^  SONAME *" | cut -b24-)
  if [ -n "${soname}" ]; then
    printf "${soname}"
  fi
}

function zip_symbols() {
  cd symbols
  zip_count=1
  total_size=0
  find . -mindepth 2 -type d | while read path; do
    size=$(du -s -b "${path}" | cut -f1)
    zip -q -r "../symbols${zip_count}.zip" "${path##./}"
    total_size=$((total_size + size))
    if [[ ${total_size} -gt 500000000 ]]; then
      zip_count=$((zip_count + 1))
      total_size=0
    fi
  done
  cd ..
}

purge_old_packages() {
  find downloads | while read line; do
    name=$(echo "${line}" | cut -d'/' -f2)

    if ! grep -q ${name} package_names.txt; then
      rm -vf "downloads/${name}"
    fi
  done
}

rm -rf symbols packages tmp symbols*.zip packages.txt package_names.txt
mkdir -p downloads symbols tmp

packages="
alsa
at-spi2-atk-gtk2
at-spi2-core
dbus-1-glib
firefox-esr
fontconfig
freetype
glibc
glib-networking
gnome-vfs2
gsettings-backend-dconf
libatk-1_0-0
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
libffi8
libfribidi0
libgbm1
libgdk_pixbuf-2_0-0
libgio-2_0-0
libglib-2_0-0
libglvnd
libgtk-2_0-0
libgtk-3-0
libICE6
libicu[0-9][0-9]
libopus0
libpango-1_0-0
libpcre1
libpcslite1
libpng12-0
libpng16-16
libpostproc[0-9][0-9]
libproxy1
libproxy1
libproxy1-config-kde
libSM6
libsoftokn3
libsqlite3-0
libstdc++6
libswresample[0-9]
libxvidcore4
libswscale[0-9]
libthai0
libvpx4
libvulkan1
libvulkan_intel
libvulkan_radeon
libwayland-client0
libX11-6
libxcb1
libXext6
libxml2-2
Mesa-dri
Mesa-dri-nouveau
Mesa-gallium
Mesa-libEGL1
Mesa-libGL1
Mesa-libva
MozillaFirefox
mozilla-nspr
mozilla-nss
libpixman-1-0
libpulse0
speech-dispatcher
libsystemd0
libx264-[0-9][0-9][0-9] http://packman.inode.at/suse
libx265-[0-9][0-9][0-9] http://packman.inode.at/suse
libz1
"

fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  find downloads -name "${package_name}-[0-9]*.rpm" -type f | grep -v debuginfo | while read package; do
    local filename="${package##downloads/}"
    if ! grep -q -F "${filename}" SHA256SUMS; then
      local version=$(get_version "${package_name}" "${filename}")
      local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}")

      [ -z "${debuginfo_package}" ] && printf "***** Could not find debuginfo for ${filename}\n" && continue

      echo package = $package version = $version debuginfo = $debuginfo_package
      unpack_package ${package} ${debuginfo_package}

      find packages -type f | grep -v debug | while read path; do
        if file "${path}" | grep -q ": *ELF" ; then
          local debuginfo_path="$(find_debuginfo "${path}")"

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
            cat error.log
          fi

          # Copy the symbol file and debug information
          debugid=$(head -n 1 "${tmpfile}" | cut -d' ' -f4)
          filename="$(basename "${path}")"
          mkdir -p "symbols/${filename}/${debugid}"
          cp "${tmpfile}" "symbols/${filename}/${debugid}/${filename}.sym"
          cp "${debuginfo_path}" "symbols/${filename}/${debugid}/${filename}.dbg"
          local soname=$(get_soname "${path}")
          if [ -n "${soname}" ]; then
            if [ "${soname}" != "${filename}" ]; then
              mkdir -p "symbols/${soname}/${debugid}"
              cp "${tmpfile}" "symbols/${soname}/${debugid}/${soname}.sym"
              cp "${debuginfo_path}" "symbols/${soname}/${debugid}/${soname}.dbg"
            fi
          fi

          rm -f "${tmpfile}"
        fi
      done

      # Compress the debug information
      find symbols -name "*.dbg" -type f -print0 | xargs -0 -P${cpu_count} -I{} gzip -f --best "{}"

      rm -rf packages
      printf "${filename}\n" >> SHA256SUMS
      if [ -n "${debuginfo_package}" ]; then
        local debuginfo_package_filename=$(basename "${debuginfo_package}")
        printf "${debuginfo_package_filename}\n" >> SHA256SUMS
      fi
    fi
  done
}

echo "${packages}" | while read line; do
  [ -z "${line}" ] && continue
  process_packages ${line}
done

zip_symbols

find . -name "*.zip" | while read myfile; do
  printf "Uploading ${myfile}\n"
  while : ; do
    res=$(curl -H "auth-token: ${SYMBOLS_API_TOKEN}" --form ${myfile}=@${myfile} https://symbols.mozilla.org/upload/)
    if [ -n "${res}" ]; then
      echo "${res}"
      break
    fi
  done
done

find symbols -mindepth 2 -maxdepth 2 -type d | while read module; do
  module_name=${module##symbols/}
  crashes=$(supersearch --num=all --modules_in_stack=${module_name//-})
  if [ -n "${crashes}" ]; then
   echo "${crashes}" | reprocess
  fi
done

purge_old_packages
