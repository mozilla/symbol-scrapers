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

URL="http://nl.archive.ubuntu.com/ubuntu/pool"
DDEB_URL="http://ddebs.ubuntu.com/pool"

get_package_urls() {
  local package_name="${1}"
  local pkg_path="${2}"
  local main_path="main/${pkg_path}"
  local universe_path="universe/${pkg_path}"
  local dbg_package_name="${3:-$package_name}"
  local dbgsym_package_name="${4:-$package_name}"
  local alt_url="${5}"
  local url="${URL}"
  local ddeb_url="${DDEB_URL}"

  local urls="${url}/${main_path}/ ${url}/${universe_path}/ ${ddeb_url}/${main_path}/ ${ddeb_url}/${universe_path}/"

  if [ -n "${alt_url}" ]; then
    urls="${urls} ${alt_url}/${main_path}/ ${alt_url}/${universe_path}/"
  fi

  wget -k --quiet ${urls}
  for i in ${urls}; do
    grep -h -o "${i}\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(i386\|amd64\).d.*eb\"" index.html* | cut -d'"' -f1
  done
  rm -f index.html*
}

fetch_packages() {
  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> packages.txt
  done

  sed -i -e 's/%2b/+/g' packages.txt
  sort packages.txt | wget -o wget.log -P downloads -c -i -
  rev packages.txt | cut -d'/' -f1 | rev > package_names.txt
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
dconf-gsettings-backend d/dconf
firefox f/firefox firefox firefox http://ppa.launchpad.net/mozillateam/firefox-next/ubuntu/pool
glib-networking g/glib-networking
gvfs g/gvfs
libasound2 a/alsa-lib
libatk1.0-0 a/atk1.0
libatk-bridge2.0-0 a/at-spi2-atk
libatspi2.0-0 a/at-spi2-core
libavcodec[0-9][0-9] f/ffmpeg
libavutil[0-9][0-9] f/ffmpeg
libc6 g/glibc
libcairo2 c/cairo
libdbus-1-3 d/dbus
libdbus-glib-1-2 d/dbus-glib
libegl1-mesa-drivers m/mesa
libegl1-mesa m/mesa
libegl-mesa0 m/mesa
libepoxy0 libe/libepoxy
libevent-2.[0-9]-[0-9] libe/libevent libevent libevent-2.[0-9]-[0-9]
libffi[0-9] libf/libffi
libfontconfig1 f/fontconfig
libfreetype6 f/freetype
libfribidi0 f/fribidi
libgdk-pixbuf2.0-0 g/gdk-pixbuf
libgl1-mesa-dri m/mesa
libgl1-mesa-glx m/mesa
libglib2.0-0 g/glib2.0
libglx-mesa0 m/mesa
libgtk-3-0 g/gtk+3.0
libice6 libi/libice
libicu[0-9][0-9] i/icu
libnspr4 n/nspr
libopus0 o/opus libopus
libpango-1.0-0 p/pango1.0
libpcre3 p/pcre3
libpcsclite1 p/pcsc-lite
libpixman-1-0 p/pixman
libpng12-0 libp/libpng
libpng16-16 libp/libpng1.6
libproxy1-plugin-gsettings libp/libproxy
libproxy1v5 libp/libproxy
libpulse0 p/pulseaudio
libsm6 libs/libsm
libspeechd2 s/speech-dispatcher
libsqlite3-0 s/sqlite3
libstdc++6 g/gcc-9 libstdc++6-9
libsystemd0 s/systemd
libthai0 libt/libthai
libvpx[0-9] libv/libvpx
libwayland-client0 w/wayland
libx11-6 libx/libx11
libx264-[0-9][0-9][0-9] x/x264
libx265-[0-9][0-9][0-9] x/x265
libxcb1 libx/libxcb
libxext6 libx/libxext
libxml2 libx/libxml2
libxss1 libx/libxss
libxvidcore4 x/xvidcore
mesa-vulkan-drivers m/mesa
opensc-pkcs11 o/opensc
thunderbird t/thunderbird
zlib1g z/zlib
"

fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  local dbg_package_name="${3:-$package_name}"
  local dbgsym_package_name="${4:-$package_name}"

  find downloads -regex "downloads/\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(i386\|amd64\).d.?eb" -type f  | while read path; do
    local filename="${path##downloads/}"
    if ! grep -q -F "${filename}" SHA256SUMS; then
      7z -y x "${path}" > /dev/null
      if [[ ${path} =~ -(dbg|dbgsym)_ ]]; then
        mkdir -p "debug/${filename}"
        tar -C "debug/${filename}" -x -a -f data.tar
      else
        mkdir -p "packages/${filename}"
        tar -C "packages/${filename}" -x -a -f data.tar
      fi
      echo "${filename}" >> SHA256SUMS
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
        printf "Writing symbol file with missing debuginfo ... "
        ${DUMP_SYMS} "${path}" > "${tmpfile}"
        if [ $? -ne 0 ]; then
          printf "failed\nSomething went terribly wrong with ${path}\n"
          exit 1
        else
          printf "done\n"
        fi
      else
        printf "done\n"
      fi

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
  zip -r "../symbols${zip_count}.zip" "${path##./}"
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
