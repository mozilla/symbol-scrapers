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

URL="https://ftp.lysator.liu.se/pub/opensuse"

REPOS="
debug/distribution/leap/15.0/repo/oss/x86_64
debug/distribution/leap/15.1/repo/oss/x86_64
debug/distribution/leap/15.2/repo/oss/x86_64

debug/update/leap/15.0/oss/rpms/x86_64
debug/update/leap/15.1/oss/x86_64

distribution/leap/15.0/repo/oss/x86_64
distribution/leap/15.1/repo/oss/x86_64
distribution/leap/15.2/repo/oss/x86_64

tumbleweed/repo/oss/x86_64
tumbleweed/repo/debug/x86_64

update/leap/15.0/oss/rpms/x86_64/
update/leap/15.1/oss/x86_64

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

  grep -h -o "${url}.*/\(${package_name}-[0-9].*.x86_64.rpm\|${dbg_package_name}-[0-9].*.x86_64.rpm\)\"" index.html* | cut -d'"' -f1 | grep -v 32bit
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
    xmllint --format --html -o "${path}" "${path}.bak"
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

unpack_package() {
  package_filename="${1##downloads/}"
  package_name="${package_filename%%.rpm}"

  if [[ ${package_filename} =~ -debuginfo- ]]; then
    mkdir -p "debug/${package_name}"
    rpm2cpio "${1}" | cpio --quiet -i -d -D "debug/${package_name}"
  else
    mkdir -p "packages/${package_name}"
    rpm2cpio "${1}" | cpio --quiet -i -d -D "packages/${package_name}"
  fi
}

function get_soname {
  local path="${1}"
  local soname=$(objdump -p "${path}" | grep "^  SONAME *" | cut -b24-)
  if [ -n "${soname}" ]; then
    printf "${soname}"
  fi
}

purge_old_packages() {
  find downloads | while read line; do
    name=$(echo "${line}" | cut -d'/' -f2)

    if ! grep -q ${name} package_names.txt; then
      rm -vf "downloads/${name}"
    fi
  done
}

find_elf_folders() {
  local tmpfile=$(mktemp --tmpdir=tmp)
  find "${1}" -type f > "${tmpfile}"
  file --files-from "${tmpfile}" | grep ": *ELF" | cut -d':' -f1 | rev | cut -d'/' -f2- | rev | sort -u
  rm -f "${tmpfile}"
}

find_executables() {
  local tmpfile=$(mktemp --tmpdir=tmp)
  find "${1}" -type f > "${tmpfile}"
  file --files-from "${tmpfile}" | grep ": *ELF" | cut -d':' -f1
  rm -f "${tmpfile}"
}

unpack_debuginfo() {
  chmod -R +w debug packages
  find_executables debug | xargs -I{} objcopy --decompress-debug-sections {}
  find_executables packages | xargs -I{} objcopy --decompress-debug-sections {}
}

rm -rf symbols packages debug tmp symbols*.zip error.log packages.txt package_names.txt
mkdir -p debug
mkdir -p downloads
mkdir -p packages
mkdir -p symbols
mkdir -p tmp

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
libgdk_pixbuf-2_0-0
libgio-2_0-0
libglib-2_0-0
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
  find downloads -name "${package_name}-*.rpm" -type f  | while read path; do
    local filename="${path##downloads/}"
    if ! grep -q -F "${filename}" SHA256SUMS; then
      unpack_package "${path}"
      echo "$filename" >> SHA256SUMS
    fi
  done

  unpack_debuginfo
  debuginfo_folders="$(find_elf_folders packages) $(find_elf_folders debug)"

  find packages -type f | while read path; do
    if file "${path}" | grep -q ": *ELF" ; then
      local tmpfile=$(mktemp --tmpdir=tmp)
      printf "Writing symbol file for ${path} ... "
      ${DUMP_SYMS} "${path}" ${debuginfo_folders} > "${tmpfile}"
      if [ $? -ne 0 ]; then
        ${DUMP_SYMS} "${path}" > "${tmpfile}"
        if [ $? -ne 0 ]; then
          printf "Something went terribly wrong with ${path}\n"
          exit 1
        fi
      fi
      printf "done\n"

      local debugid=$(head -n 1 "${tmpfile}" | cut -d' ' -f4)
      local filename=$(basename "${path}")
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
}

echo "${packages}" | while read line; do
  [ -z "${line}" ] && continue
  process_packages ${line}
  rm -rf debug packages
  mkdir -p debug packages
done

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
