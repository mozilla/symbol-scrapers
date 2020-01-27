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

URL="http://ftp.nl.debian.org/debian/pool"
UPDATES_URL="http://security-cdn.debian.org/debian-security/pool/updates"
DDEB_URL="http://debug.mirrors.debian.org/debian-debug/pool"

get_package_urls() {
  local package_name=${1}
  local pkg_path=${2}
  local main_path="main/${pkg_path}"
  local dbg_package_name=${3:-$package_name}
  local dbgsym_package_name=${4:-$package_name}
  local alt_url="${UPDATES_URL}"
  local url=${URL}
  local ddeb_url=${DDEB_URL}

  local urls="${url}/${main_path}/ ${ddeb_url}/${main_path}/ "

  if [ -n "${alt_url}" ]; then
    urls="${urls} ${alt_url}/${main_path}/"
  fi

  wget -k --quiet ${urls}
  for i in ${urls}; do
    grep -h -o "${i}\(${package_name}\|${dbg_package_name}-dbg\|${dbgsym_package_name}-dbgsym\)_.*_\(i386\|amd64\).deb\"" index.html* | cut -d'"' -f1
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

function get_build_id {
  eu-readelf -n "${1}" | grep "^    Build ID:" | cut -b15-
}

function merge_debug_info {
  path="${1}"
  buildid=$(get_build_id "${path}")
  prefix=$(echo "${buildid}" | cut -b1-2)
  suffix=$(echo "${buildid}" | cut -b3-)
  debuginfo=$(find debug -path "*/${prefix}/${suffix}.debug" | head -n1)
  if test -n "${debuginfo}" ; then
    objcopy --decompress-debug-sections "${debuginfo}"
    eu-unstrip "${path}" "${debuginfo}"
    printf "Merging ${debuginfo} to ${path}\n"
    cp -f "${debuginfo}" "${path}"
    return
  else
    filename=$(basename "${path}")
    find debug -path "*-dbg*_*${filename}" -type f | while read debuginfo; do
        tbuildid=$(get_build_id "${debuginfo}")
        if [ "$buildid" == "$tbuildid" ]; then
            objcopy --decompress-debug-sections "${debuginfo}"
            eu-unstrip "${path}" "${debuginfo}"
            printf "Merging ${debuginfo} to ${path}\n"
            cp -f "${debuginfo}" "${path}"
            return 1
        fi
    done
    if [ $? -ne 1 ]; then
      printf "Could not find debuginfo for ${1}\n" >> error.log
    fi
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

rm -rf symbols debug tmp symbols*.zip error.log packages.txt package_names.txt
mkdir -p downloads
mkdir -p symbols
mkdir -p tmp
mkdir -p debug

packages="
dconf-gsettings-backend d/dconf
firefox f/firefox
firefox-esr f/firefox-esr
glib-networking g/glib-networking
gvfs g/gvfs
libasound2 a/alsa-lib
libavcodec[0-9][0-9] f/ffmpeg
libavutil[0-9][0-9] f/ffmpeg
libc6 g/glibc
libcairo2 c/cairo
libdbus-1-3 d/dbus
libdbus-glib-1-2 d/dbus-glib
libepoxy0 libe/libepoxy
libevent-2.[0-9]-[0-9] libe/libevent libevent libevent-2.[0-9]-[0-9]
libfontconfig1 f/fontconfig
libfreetype6 f/freetype
libfribidi0 f/fribidi
libgdk-pixbuf2.0-0 g/gdk-pixbuf
libgl1-mesa-dri m/mesa
libgl1-mesa-glx m/mesa
libglib2.0-0 g/glib2.0
libglx-mesa0 m/mesa
libgtk-3-0 g/gtk+3.0
libicu[0-9][0-9] i/icu
libopus0 o/opus libopus
libpcre3 p/pcre3
libpcsclite1 p/pcsc-lite
libpng12-0 libp/libpng
libpng16-16 libp/libpng1.6
libnspr4 n/nspr
libpango-1.0-0 p/pango1.0
libproxy1-plugin-gsettings libp/libproxy
libproxy1v5 libp/libproxy
libpulse0 p/pulseaudio
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
libxvidcore4 x/xvidcore
opensc-pkcs11 o/opensc
zlib1g z/zlib
"

fetch_packages "${packages}"

find downloads -name "*.deb" -type f | while read path; do
  full_hash=$(sha256sum "${path}")
  hash=$(echo "${full_hash}" | cut -b 1-64)
  if ! grep -q ${hash} SHA256SUMS; then
    7z -y x "${path}" > /dev/null
    if [[ ${path} =~ -(dbg|dbgsym)_ ]]; then
      mkdir -p "debug/${path##downloads/}"
      tar -C "debug/${path##downloads/}" -x -a -f data.tar
    else
      mkdir -p "tmp/${path##downloads/}"
      tar -C "tmp/${path##downloads/}" -x -a -f data.tar
    fi
    echo "${full_hash}" >> SHA256SUMS
  fi
done

find tmp -type f | while read path; do
  if file "${path}" | grep -q "ELF \(32\|64\)-bit LSB \(shared object\|pie executable\)" ; then
    filename=$(basename "${path}")
    merge_debug_info "${path}"
    tmpfile=$(mktemp)
    printf "Writing symbol file for ${path} ... "
    ${DUMP_SYMS} "${path}" > "${tmpfile}"
    printf "done\n"
    debugid=$(head -n 1 "${tmpfile}" | cut -d' ' -f4)
    mkdir -p "symbols/${filename}/${debugid}"
    mv "${tmpfile}" "symbols/${filename}/${debugid}/${filename}.sym"
    file_size=$(stat -c "%s" "${path}")
    # Copy the object file only if it's not larger than roughly 2GiB
    if [ $file_size -lt 2100000000 ]; then
      cp -f "${path}" "symbols/${filename}/${debugid}/${filename}"
    fi
  fi
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
