#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/"

. $(dirname $0)/../common.sh

URL="https://fedora.mirror.wearetriple.com/linux"
RELEASES="40 41 42 test/42_Beta"

get_package_urls() {
  local package_name=${1}
  local dbg_package_name="${package_name}-debuginfo"
  local url=${3:-$URL}

  find . -name "index.html*" -exec grep -h -o "${url}.*/\(${package_name}-[0-9].*.x86_64.rpm\|${dbg_package_name}-[0-9].*.x86_64.rpm\)\"" {} \; | \
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
    printf "${url}/development/${release}/Everything/x86_64/os/Packages/${pkg_path}/\n"
    printf "${url}/development/${release}/Everything/x86_64/debug/${tree_dir}/${packages_dir}/${pkg_path}/\n"
  done

  # Rawhide
  printf "${url}/development/rawhide/Everything/x86_64/os/Packages/${pkg_path}/\n"
  printf "${url}/development/rawhide/Everything/x86_64/debug/${tree_dir}/${packages_dir}/${pkg_path}/\n"
}

fetch_packages() {
  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_indexes ${line}
  done | sort -u > indexes.txt

  sort indexes.txt | ${WGET} -o wget_packages_urls.log -k -i -

  find . -type f -name "index.html*" | while read path; do
    mv "${path}" "${path}.bak"
    xmllint --nowarning --format --html --output "${path}" "${path}.bak" 2>/dev/null
    rm -f "${path}.bak"
  done

  echo "${1}" | while read line; do
    [ -z "${line}" ] && continue
    get_package_urls ${line} >> unfiltered-packages.txt
  done

  touch packages.txt
  cat unfiltered-packages.txt | while read line; do
    package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
    if ! grep -q -F "${package_name}" SHA256SUMS; then
      echo "${line}" >> packages.txt
    fi
  done

  find . -name "index.html*" -exec rm -f {} \;

  sort packages.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
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

function remove_temp_files() {
  rm -rf downloads symbols packages debug-packages tmp \
         symbols*.zip indexes.txt packages.txt unfiltered-packages.txt \
         crashes.list symbols.list
}

remove_temp_files
mkdir -p downloads symbols tmp

packages="
alsa-lib a
apitrace-libs a
at-spi2-atk a
at-spi2-core a
atk a
cairo c
cups-libs c
dbus-glib d
dbus-libs d
dconf d
expat e
ffmpeg-libs f https://mirror.nl.leaseweb.net/rpmfusion/free/fedora
firefox f
fontconfig f
freetype f
fribidi f
gamin g
gdk-pixbuf2 g
glib2-fam g
glib2 g
glibc g
glib-networking g
gnome-vfs2 g
gtk2 g
gtk3 g
highway h
ibus-libs i
intel-gmmlib i
intel-media-driver i https://mirror.nl.leaseweb.net/rpmfusion/nonfree/fedora
jemalloc j
libcloudproviders l
libdrm l
libepoxy l
libevent l
libffi l
libgcc l
libglvnd-devel l
libglvnd-egl l
libglvnd-glx l
libglvnd l
libICE l
libicu l
libpng12 l
libpng l
libproxy l
libSM l
libstdc++ l
libthai l
libva l
libva-vdpau-driver l
libvpx l
libwayland-client l
libX11 l
libX11-xcb l
libxcb l
libXext l
libxkbcommon l
libxml2 l
llvm-libs l
llvm[0-9][0-9]-libs l
mesa-dri-drivers m
mesa-libEGL m
mesa-libgbm m
mesa-libGL m
mesa-va-drivers m
mesa-vulkan-drivers m
nspr n
nss n
nss-util n
numactl-libs n
opencryptoki-libs o
opus o
p11-kit p
pango p
pcre p
pcre2 p
pcsc-lite-libs p
pipewire-libs p
pixman p
pulseaudio-libs p
speech-dispatcher s
systemd-libs s
thunderbird t
x264-libs x https://mirror.nl.leaseweb.net/rpmfusion/free/fedora
x265-libs x https://mirror.nl.leaseweb.net/rpmfusion/free/fedora
xorg-x11-drv-nvidia-[0-9][0-9][0-9]xx-libs x https://mirror.nl.leaseweb.net/rpmfusion/nonfree/fedora
xorg-x11-drv-nvidia-libs x https://mirror.nl.leaseweb.net/rpmfusion/nonfree/fedora
xvidcore x https://mirror.nl.leaseweb.net/rpmfusion/free/fedora
zlib z
zvbi z
"

fetch_packages "${packages}"

function process_packages() {
  local package_name="${1}"
  find downloads -name "${package_name}-[0-9]*.rpm" -type f | grep -v debuginfo | while read package; do
    local package_filename="${package##downloads/}"
    local version=$(get_version "${package_name}" "${package_filename}")
    local debuginfo_package=$(find_debuginfo_package "${package_name}" "${version}")

    if [ -n "${debuginfo_package}" ]; then
      unpack_rpm_package ${package} ${debuginfo_package}
    else
      printf "***** Could not find debuginfo for ${package_filename}\n"
      unpack_rpm_package ${package}
    fi

    find packages -type f | grep -v debug | while read path; do
      if file "${path}" | grep -q ": *ELF" ; then
        local debuginfo_path="$(find_debuginfo "${path}")"

        truncate -s 0 error.log
        local tmpfile=$(mktemp --tmpdir=tmp)
        printf "Writing symbol file for ${path} ${debuginfo_path} ... "
        if [ -n "${debuginfo_path}" ]; then
          ${DUMP_SYMS} --inlines "${path}" "${debuginfo_path}" 1> "${tmpfile}" 2> error.log
        else
          ${DUMP_SYMS} --inlines "${path}" 1> "${tmpfile}" 2> error.log
        fi

        if [ -s "${tmpfile}" -a -z "${debuginfo_path}" ]; then
          printf "done w/o debuginfo\n"
        elif [ -s "${tmpfile}" ]; then
          printf "done\n"
        else
          printf "something went terribly wrong!\n"
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
  done
}

echo "${packages}" | while read line; do
  [ -z "${line}" ] && continue
  process_packages ${line}
done

create_symbols_archive

upload_symbols

reprocess_crashes

update_sha256sums

remove_temp_files
