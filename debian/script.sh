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

URL="http://ftp.it.debian.org/debian/pool"
UPDATES_URL="http://security-cdn.debian.org/debian-security/pool/updates"
DDEB_URL="http://debug.mirrors.debian.org/debian-debug/pool"
ARCHITECTURES="i386 amd64"

function fetch {
  package_name=${1}
  pkg_path=${2}
  dbg_package_name=${3:-$package_name}
  dbgsym_package_name=${4:-$package_name}
  alt_url="${UPDATES_URL}"
  url=${URL}
  ddeb_url=${DDEB_URL}

  for arch in ${ARCHITECTURES}; do
    package_regexp="${package_name}_*_${arch}.deb,${package_regexp}"
    dbg_package_regexp="${dbg_package_name}-dbg_*_${arch}.deb,${dbg_package_regexp}"
    dbgsym_package_regexp="${dbgsym_package_name}-dbgsym_*_${arch}.deb,${dbgsym_package_regexp}"
  done

  package_regexp="${package_regexp%%,}"
  dbg_package_regexp="${dbg_package_regexp%%,}"
  dbgsym_package_regexp="${dbgsym_package_regexp%%,}"

  wget -o wget.log --no-cache -P downloads -nd -c -r -np -e robots=off -A "${package_regexp},${dbg_package_regexp}" "${url}/${pkg_path}/"
  wget -o wget.log --no-cache -P downloads -nd -c -r -np -e robots=off -A "${dbgsym_package_regexp}" "${ddeb_url}/${pkg_path}/"

  if [ -n "${alt_url}" ]; then
    wget -o wget.log --no-cache -P downloads -nd -c -r -np -e robots=off -A "${package_regexp},${dbg_package_regexp}" "${alt_url}/${pkg_path}/"
    wget -o wget.log --no-cache -P downloads -nd -c -r -np -e robots=off -A "${dbgsym_package_regexp}" "${alt_url}/${pkg_path}/"
  fi
}

function purge {
  package_name=${1}
  pkg_path=${2}
  dbg_package_name=${3:-$package_name}
  dbgsym_package_name=${4:-$package_name}
  url=${URL}
  ddeb_url=${DDEB_URL}
  alt_url="${UPDATES_URL}"

  find downloads -name "${package_name}_*.*deb" | while read path; do
    package=$(basename "${path}")
    if wget -q --method HEAD "${url}/${pkg_path}/${package}" ; then
      :
    elif [ -n "${alt_url}" ]; then
      if wget -q --method HEAD "${alt_url}/${pkg_path}/${package}" ; then
        :
      else
        rm -f "${path}"
      fi
    else
      rm -f "${path}"
    fi
  done

  find downloads -name "${package_name}-dbgsym_*.deb" | while read path; do
    package=$(basename "${path}")
    if wget -q --method HEAD "${ddeb_url}/${pkg_path}/${package}" ; then
      :
    elif [ -n "${alt_url}" ]; then
      if wget -q --method HEAD "${alt_url}/${pkg_path}/${package}" ; then
        :
      else
        rm -f "${path}"
      fi
    else
      rm -f "${path}"
    fi
  done

  find downloads -name "${dbg_package_name}-dbg_*.*deb" | while read path; do
    package=$(basename "${path}")
    if wget -q --method HEAD "${url}/${pkg_path}/${package}" ; then
      :
    elif [ -n "${alt_url}" ]; then
      if wget -q --method HEAD "${alt_url}/${pkg_path}/${package}" ; then
        :
      else
        rm -f "${path}"
      fi
    else
      rm -f "${path}"
    fi
  done
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

rm -rf symbols debug tmp symbols*.zip error.log
mkdir -p downloads
mkdir -p symbols
mkdir -p tmp
mkdir -p debug

packages="
dconf-gsettings-backend main/d/d-conf dconf-gsettings-backend dconf-gsettings-backend main/d/dconf
firefox main/f/firefox
firefox-esr main/f/firefox-esr
glib-networking main/g/glib-networking
gvfs main/g/gvfs
libasound2 main/a/alsa-lib
libavutil[0-9][0-9] main/f/ffmpeg
libavcodec[0-9][0-9] main/f/ffmpeg
libc6 main/g/glibc
libcairo2 main/c/cairo
libdbus-1-3 main/d/dbus
libdbus-glib-1-2 main/d/dbus-glib
libepoxy0 main/libe/libepoxy
libevent-2.[0-9]-[0-9] main/libe/libevent libevent libevent-2.[0-9]-[0-9]
libfontconfig1 main/f/fontconfig
libfreetype6 main/f/freetype
libfribidi0 main/f/fribidi
libgdk-pixbuf2.0-0 main/g/gdk-pixbuf
libgl1-mesa-dri main/m/mesa
libgl1-mesa-glx main/m/mesa
libglib2.0-0 main/g/glib2.0
libglx-mesa0 main/m/mesa
libgtk-3-0 main/g/gtk+3.0
libicu[0-9][0-9] main/i/icu
libopus0 main/o/opus libopus
libpcre3 main/p/pcre3
libpcsclite1 main/p/pcsc-lite
libpng12-0 main/libp/libpng
libpng16-16 main/libp/libpng1.6
libnspr4 main/n/nspr
libpango-1.0-0 main/p/pango1.0
libproxy1-plugin-gsettings main/libp/libproxy
libproxy1v5 main/libp/libproxy
libpulse0 main/p/pulseaudio
libspeechd2 main/s/speech-dispatcher
libstdc++6 main/g/gcc-9 libstdc++6-9
libsystemd0 main/s/systemd
libthai0 main/libt/libthai
libvpx[0-9] main/libv/libvpx
libwayland-client0 main/w/wayland
libx11-6 main/libx/libx11
libx264-[0-9][0-9][0-9] main/x/x264
libx265-[0-9][0-9][0-9] main/x/x265
libxcb1 main/libx/libxcb
libxext6 main/libx/libxext
libxml2 main/libx/libxml2
libxvidcore4 main/x/xvidcore
opensc-pkcs11 main/o/opensc
zlib1g main/z/zlib
"

echo "${packages}" | while read line; do
    [ -z "${line}" ] && continue
    fetch ${line}
done

package_files=$(find downloads -name "*.deb" -type f)

for i in ${package_files}; do
  full_hash=$(sha256sum "${i}")
  hash=$(echo "${full_hash}" | cut -b 1-64)
  if ! grep -q ${hash} SHA256SUMS; then
    7z -y x "${i}" > /dev/null
    if [[ ${i} =~ -(dbg|dbgsym)_ ]]; then
      mkdir -p "debug/${i##downloads/}"
      tar -C "debug/${i##downloads/}" -x -a -f data.tar
    else
      mkdir -p "tmp/${i##downloads/}"
      tar -C "tmp/${i##downloads/}" -x -a -f data.tar
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
  crashes=$(supersearch --num=all --modules_in_stack=${module##symbols/})
  if [ -n "${crashes}" ]; then
   echo "${crashes}" | reprocess
  fi
done

echo "${packages}" | while read line; do
    [ -z "${line}" ] && continue
    purge $line
done
