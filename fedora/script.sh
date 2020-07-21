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

cpu_count=$(grep -c ^processor /proc/cpuinfo)

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
libva-vdpau-driver l
libvpx l
libwayland-client l
libX11 l
libX11-xcb l
libxcb l
libXext l
libxml2 l
libva l
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
