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

URL="https://fedora.mirror.wearetriple.com/linux"
RELEASES="31 32 33"

get_package_urls() {
  local package_name=${1}
  local dbg_package_name="${package_name}-debuginfo"
  local url=${3:-$URL}

  grep -h -o "${url}.*/\(${package_name}-[0-9].*.x86_64.rpm\|${dbg_package_name}-[0-9].*.x86_64.rpm\)\"" index.html*| \
  cut -d'"' -f1
}

get_package_indexes() {
  local pkg_path=${2}
  local url=${3:-$URL}

  local everything_dir=""
  local packages_dir=""
  local tree_dir=""

  if [ -z "${3}" ]; then
    everything_dir="Everything"
    packages_dir="Packages"
    tree_dir="tree"
  fi

  for release in ${RELEASES}; do
    printf "${url}/releases/${release}/Everything/x86_64/os/Packages/${pkg_path}/\n"
    printf "${url}/releases/${release}/Everything/x86_64/debug/${tree_dir}/${packages_dir}/${pkg_path}/\n"
    printf "${url}/updates/${release}/${everything_dir}/x86_64/${packages_dir}/${pkg_path}/\n"
    printf "${url}/updates/${release}/${everything_dir}/x86_64/debug/${packages_dir}/${pkg_path}/\n"
    printf "${url}/updates/testing/${release}/${everything_dir}/x86_64/${packages_dir}/${pkg_path}/\n"
    printf "${url}/updates/testing/${release}/${everything_dir}/x86_64/debug/${packages_dir}/${pkg_path}/\n"
  done

  # 33 beta
  printf "${url}/development/33/${everything_dir}/x86_64/os/Packages/${pkg_path}/\n"
  printf "${url}/development/33/${everything_dir}/x86_64/debug/${tree_dir}/${packages_dir}/${pkg_path}/\n"

  # Rawhide
  printf "${url}/development/rawhide/${everything_dir}/x86_64/os/Packages/${pkg_path}/\n"
  printf "${url}/development/rawhide/${everything_dir}/x86_64/debug/${tree_dir}/${packages_dir}/${pkg_path}/\n"
}

fetch_packages() {
  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_indexes ${line}
  done | sort -u > indexes.txt

  wget -o wget.log --progress=dot:mega --compression=auto -k -i indexes.txt

  find . -name "index.html*" | while read path; do
    mv "${path}" "${path}.bak"
    xmllint  --nowarning --format --html --output "${path}" "${path}.bak"
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
alsa-lib a
at-spi2-atk a
at-spi2-core a
atk a
cairo c
dbus-glib d
dbus-libs d
dconf d
ffmpeg-libs f http://mirror.nl.leaseweb.net/rpmfusion/free/fedora
fontconfig f
freetype f
fribidi f
gdk-pixbuf2 g
glib2 g
glibc g
glib-networking g
gnome-vfs2 g
gtk2 g
gtk3 g
intel-media-driver i http://mirror.nl.leaseweb.net/rpmfusion/nonfree/fedora
libdrm l
libepoxy l
libevent l
libffi l
libICE l
libicu l
libpng12 l
libpng l
libproxy l
libSM l
libstdc++ l
libthai l
libvpx l
libwayland-client l
libx11 l
libxcb l
libXext l
libxml2 l
mesa-dri-drivers m
mesa-libEGL m
mesa-libgbm m
mesa-libGL m
mesa-vulkan-drivers m
nspr n
opus o
pango p
pcre p
pcsc-lite-libs p
pixman p
pulseaudio-libs p
speech-dispatcher s
systemd-libs s
x264-libs x http://mirror.nl.leaseweb.net/rpmfusion/free/fedora
x265-libs x http://mirror.nl.leaseweb.net/rpmfusion/free/fedora
xvidcore x http://mirror.nl.leaseweb.net/rpmfusion/free/fedora
zlib z
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
