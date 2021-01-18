#!/bin/bash
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

function get_soname {
  local path="${1}"
  local soname=$(objdump -p "${path}" | grep "^  SONAME *" | cut -b24-)
  if [ -n "${soname}" ]; then
    printf "${soname}"
  fi
}

function purge {
  package_name="${1}"
  package_url="${2}"
  find tarballs -name "${package_name}*.tar.*" | while read path; do
    package=$(basename "${path}")
    if wget -q --method HEAD "${package_url}${package}" ; then
      :
    else
      rm -f "${path}"
    fi
  done
}

rm -rf symbols* tmp
mkdir -p symbols
mkdir -p tarballs
mkdir -p tmp

cd tarballs
packages="
https://www.archlinux.org/packages/core/x86_64/glib2/download/
https://www.archlinux.org/packages/core/x86_64/glibc/download/
https://www.archlinux.org/packages/core/x86_64/libffi/download/
https://www.archlinux.org/packages/core/x86_64/nspr/download/
https://www.archlinux.org/packages/extra/x86_64/amdvlk/download/
https://www.archlinux.org/packages/extra/x86_64/atk/download/
https://www.archlinux.org/packages/extra/x86_64/at-spi2-atk/download/
https://www.archlinux.org/packages/extra/x86_64/at-spi2-core/download/
https://www.archlinux.org/packages/extra/x86_64/cairo/download/
https://www.archlinux.org/packages/extra/x86_64/dconf/download/
https://www.archlinux.org/packages/extra/x86_64/ffmpeg/download/
https://www.archlinux.org/packages/extra/x86_64/gdk-pixbuf2/download/
https://www.archlinux.org/packages/extra/x86_64/gtk3/download/
https://www.archlinux.org/packages/extra/x86_64/gvfs/download/
https://www.archlinux.org/packages/extra/x86_64/libdrm/download/
https://www.archlinux.org/packages/extra/x86_64/libglvnd/download/
https://www.archlinux.org/packages/extra/x86_64/libibus/download/
https://www.archlinux.org/packages/extra/x86_64/libice/download/
https://www.archlinux.org/packages/extra/x86_64/libpulse/download/
https://www.archlinux.org/packages/extra/x86_64/libsm/download/
https://www.archlinux.org/packages/extra/x86_64/libstdc++5/download/
https://www.archlinux.org/packages/extra/x86_64/libva/download/
https://www.archlinux.org/packages/extra/x86_64/libva-mesa-driver/download/
https://www.archlinux.org/packages/extra/x86_64/libva-vdpau-driver/download/
https://www.archlinux.org/packages/extra/x86_64/libx11/download/
https://www.archlinux.org/packages/extra/x86_64/libxcb/download/
https://www.archlinux.org/packages/extra/x86_64/libxext/download/
https://www.archlinux.org/packages/extra/x86_64/mesa/download/
https://www.archlinux.org/packages/extra/x86_64/numactl/download/
https://www.archlinux.org/packages/extra/x86_64/pixman/download/
https://www.archlinux.org/packages/extra/x86_64/vulkan-intel/download/
https://www.archlinux.org/packages/extra/x86_64/vulkan-radeon/download/
https://www.archlinux.org/packages/extra/x86_64/wayland/download/
"
wget -o ../wget.log --progress=dot:mega -c --content-disposition ${packages}
tarballs=$(ls)
cd ..

for i in ${tarballs}; do
  full_hash=$(sha256sum "tarballs/${i}")
  hash=$(echo "${full_hash}" | cut -b 1-64)
  if ! grep -q ${hash} SHA256SUMS; then
    tar -C tmp -x -a -f "tarballs/${i}"
    echo "${full_hash}" >> SHA256SUMS
  fi
done

find tmp -name "*.so*" -type f | while read library; do
  if file "${library}" | grep -q "ELF 64-bit LSB shared object" ; then
    library_basename=$(basename "${library}")
    debugid=$("${DUMP_SYMS}" "${library}" | head -n 1 | cut -b 21-53)
    filename=$(basename "${library}")
    mkdir -p "symbols/${filename}/${debugid}"
    "${DUMP_SYMS}" "${library}" > "symbols/${filename}/${debugid}/${filename}.sym"
    soname=$(get_soname "${library}")
    if [ -n "${soname}" ]; then
      if [ "${soname}" != "${filename}" ]; then
        mkdir -p "symbols/${soname}/${debugid}"
        cp "symbols/${filename}/${debugid}/${filename}.sym" "symbols/${soname}/${debugid}/${soname}.sym"
      fi
    fi
  fi
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
    res=$(curl -H "auth-token: ${SYMBOLS_API_TOKEN}" --form "${myfile}=@${myfile}" https://symbols.mozilla.org/upload/)
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

purge "amdvlk-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "atk-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "at-spi2-atk" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "at-spi2-core" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "cairo-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "dconf-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "ffmpeg-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "gdk-pixbuf2-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "glib2-" "http://mirror.f4st.host/archlinux/core/os/x86_64/"
purge "glibc-" "http://mirror.f4st.host/archlinux/core/os/x86_64/"
purge "gtk3-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "gvfs-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libdrm-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libffi-" "http://mirror.f4st.host/archlinux/core/os/x86_64/"
purge "libglvnd-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libibus-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libice-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libpulse-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libsm-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libstdc++5-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libva-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libva-mesa-driver-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libva-vdpau-driver-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libx11-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libxcb-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libxext-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "mesa-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "nspr-" "http://mirror.f4st.host/archlinux/core/os/x86_64/"
purge "numactl-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "pixman-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "vulkan-intel-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "vulkan-radeon-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "wayland-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
