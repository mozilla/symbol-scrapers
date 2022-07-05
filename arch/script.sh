#!/bin/bash

. $(dirname $0)/../common.sh

function get_soname {
  local path="${1}"
  local soname=$(objdump -p "${path}" | grep "^  SONAME *" | cut -b24-)
  if [ -n "${soname}" ]; then
    printf "${soname}"
  fi
}

function generate_fake_packages() {
  cat SHA256SUMS | while read line; do
    local package_name=$(echo ${line} | cut -d',' -f1)
    local package_size=$(echo ${line} | cut -d',' -f2)
    truncate --size "${package_size}" "tarballs/${package_name}"
  done
}

function add_package_to_list() {
  local package_filename=$(basename "${1}")
  local package_size=$(stat -c"%s" "${1}")
  printf "${package_filename},${package_size}\n" >> SHA256SUMS
  truncate --size 0 "${1}"
  truncate --size "${package_size}" "${1}"
}

rm -rf symbols* tmp
mkdir -p symbols tarballs tmp
generate_fake_packages

cd tarballs
packages="
https://archlinux.org/packages/community/x86_64/intel-media-driver/download/
https://archlinux.org/packages/core/x86_64/dbus/download/
https://archlinux.org/packages/core/x86_64/gcc-libs/download/
https://archlinux.org/packages/core/x86_64/glib2/download/
https://archlinux.org/packages/core/x86_64/glibc/download/
https://archlinux.org/packages/core/x86_64/libffi/download/
https://archlinux.org/packages/core/x86_64/nspr/download/
https://archlinux.org/packages/extra/x86_64/amdvlk/download/
https://archlinux.org/packages/extra/x86_64/atk/download/
https://archlinux.org/packages/extra/x86_64/at-spi2-atk/download/
https://archlinux.org/packages/extra/x86_64/at-spi2-core/download/
https://archlinux.org/packages/extra/x86_64/cairo/download/
https://archlinux.org/packages/extra/x86_64/dbus-glib/download/
https://archlinux.org/packages/extra/x86_64/dconf/download/
https://archlinux.org/packages/extra/x86_64/ffmpeg/download/
https://archlinux.org/packages/extra/x86_64/gdk-pixbuf2/download/
https://archlinux.org/packages/extra/x86_64/gtk3/download/
https://archlinux.org/packages/extra/x86_64/gvfs/download/
https://archlinux.org/packages/extra/x86_64/libdrm/download/
https://archlinux.org/packages/extra/x86_64/libglvnd/download/
https://archlinux.org/packages/extra/x86_64/libibus/download/
https://archlinux.org/packages/extra/x86_64/libice/download/
https://archlinux.org/packages/extra/x86_64/libpulse/download/
https://archlinux.org/packages/extra/x86_64/libsm/download/
https://archlinux.org/packages/extra/x86_64/libspeechd/download/
https://archlinux.org/packages/extra/x86_64/libstdc++5/download/
https://archlinux.org/packages/extra/x86_64/libva/download/
https://archlinux.org/packages/extra/x86_64/libva-mesa-driver/download/
https://archlinux.org/packages/extra/x86_64/libva-vdpau-driver/download/
https://archlinux.org/packages/extra/x86_64/libx11/download/
https://archlinux.org/packages/extra/x86_64/libxcb/download/
https://archlinux.org/packages/extra/x86_64/libxext/download/
https://archlinux.org/packages/extra/x86_64/libxkbcommon/download/
https://archlinux.org/packages/extra/x86_64/mesa/download/
https://archlinux.org/packages/extra/x86_64/numactl/download/
https://archlinux.org/packages/extra/x86_64/nvidia-utils/download/
https://archlinux.org/packages/extra/x86_64/pcre2/download/
https://archlinux.org/packages/extra/x86_64/pixman/download/
https://archlinux.org/packages/extra/x86_64/vulkan-intel/download/
https://archlinux.org/packages/extra/x86_64/vulkan-radeon/download/
https://archlinux.org/packages/extra/x86_64/wayland/download/
"
wget -o ../wget.log --progress=dot:mega -c --content-disposition ${packages}
tarballs=$(ls)
cd ..

find tarballs -type f | while read path; do
  tarball_filename=$(basename ${path})
  if ! grep -q -F "${tarball_filename}" SHA256SUMS; then
    tar -C tmp -x -a -f "${path}"
    add_package_to_list "${path}"
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

rm -rf tmp

zip_symbols

upload_symbols

reprocess_crashes
