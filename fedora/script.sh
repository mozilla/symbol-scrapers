#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.fedoraproject.org/"

. $(dirname $0)/../common.sh

URLS="
https://fedora.mirror.wearetriple.com/linux
https://ftp-stud.hs-esslingen.de/pub/Mirrors/rpmfusion.org/free/fedora/
https://ftp-stud.hs-esslingen.de/pub/Mirrors/rpmfusion.org/nonfree/fedora/
"

RELEASES="
rawhide
41
42
42_Beta
"

ARCHITECTURES="
aarch64
x86_64
"

# <package folder> <package name>
PACKAGES="
alsa-lib a
apitrace-libs a
atk a
at-spi2-atk a
at-spi2-core a
cairo c
cups-libs c
dbus-glib d
dbus-libs d
dconf d
egl-wayland e
expat e
ffmpeg-libs f
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
intel-media-driver i
jemalloc j
libavcodec-free l
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
libva-nvidia-driver l
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
pcre2 p
pcre p
pcsc-lite-libs p
pipewire-libs p
pixman p
pulseaudio-libs p
speech-dispatcher s
systemd-libs s
thunderbird t
x264-libs x
x265-libs x
xorg-x11-drv-nvidia-[0-9][0-9][0-9]xx-cuda-libs x
xorg-x11-drv-nvidia-[0-9][0-9][0-9]xx-libs x
xorg-x11-drv-nvidia-[0-9][0-9][0-9]xx x
xorg-x11-drv-nvidia-[0-9][0-9][0-9]xx-xorg-libs x
xorg-x11-drv-nvidia-cuda-libs x
xorg-x11-drv-nvidia-libs x
xorg-x11-drv-nvidia x
xorg-x11-drv-nvidia-xorg-libs x
xvidcore x
zlib z
zvbi z
"

function get_release_regex() {
  local release_list=$(echo ${RELEASES} | tr ' ' '\|')
  printf "(${release_list})"
}

function get_architecture_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | tr ' ' '\|')
  printf "(${architecture_list})"
}

function get_architecture_escaped_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | sed -e "s/ /\\\|/")
  printf "\(${architecture_list}\)"
}

function get_package_folder_regex() {
  local package_folder_list=$(echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f2 | sort -u | tr '\n' '\|')
  printf "(${package_folder_list%%|})"
}

function fetch_indexes() {
  local release_regex=$(get_release_regex)
  local architecture_regex=$(get_architecture_regex)
  local package_folder_regex=$(get_package_folder_regex)

  echo "${URLS}" | while read url; do
    [ -z "${url}" ] && continue
    local regex="${url}/((releases|updates|development)/)?(testing/)?(test/)?(${release_regex}/)?(Everything/)?(${architecture_regex}/)?((os|debug)/)?(tree/)?(Packages/)?(${package_folder_regex}/)?$"
    ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive -l 9 --accept-regex "${regex}" "${url}/"
  done
}

function get_package_urls() {
  truncate -s 0 all-packages.txt unfiltered-packages.txt

  find indexes -name index.html -exec xmllint --html --xpath '//a/@href' {} \; 2>xmllint_error.log | \
    grep -o "https\?://.*\.rpm" | sort -u >> all-packages.txt

  local architecture_escaped_regex=$(get_architecture_escaped_regex)
  # Use percent encoding in package URLs, e.g. + -> %2B
  echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f1 | sed 's/\+/%2B/g' | while read package; do
    grep -o "https\?://.*/${package}\(-debuginfo\)\?-[0-9].*\.fc..\.${architecture_escaped_regex}\.rpm" all-packages.txt >> unfiltered-packages.txt
  done
}

function fetch_packages() {
  truncate -s 0 downloads.txt
  cat unfiltered-packages.txt | while read line; do
    local package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
    if ! grep -q -F "${package_name}" SHA256SUMS; then
      echo "${line}" >> downloads.txt
    fi
  done

  sort downloads.txt | ${WGET} -o wget_packages.log -P downloads -c -i -
}

function get_version() {
  local package_name="${1}"
  local filename="${2}"

  local version="${filename##${package_name}-}"
  version="${version%%.rpm}"
  printf "${version}"
}

function find_debuginfo_package() {
  local package_name="${1}"
  local version="${2}"
  find downloads -name "${package_name}-debuginfo-${version}.rpm" -type f
}

function process_packages() {
  local package_name="${1}"
  for arch in ${ARCHITECTURES}; do
    find downloads -name "${package_name}-[0-9]*.${arch}.rpm" -type f | grep -v debuginfo | while read package; do
      local package_filename="${package##downloads/}"
      local version=$(get_version "${package_name}" "${package_filename}")
      printf "package_name = ${package_name} version = ${version}\n"
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
          local debugid=$(head -n 1 "${tmpfile}" | cut -d' ' -f4)
          local filename="$(basename "${path}")"
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
  done
}

function remove_temp_files() {
  rm -rf all-packages.txt crashes.list downloads downloads.txt indexes \
         packages symbols symbols.list tmp unfiltered-packages.txt \
         xmllint_error.log
}

echo "Cleaning up temporary files..."
remove_temp_files
mkdir -p downloads indexes symbols tmp

echo "Fetching packages..."
fetch_indexes
get_package_urls
fetch_packages

echo "Processing packages..."
echo "${PACKAGES}" | while read line; do
  [ -z "${line}" ] && continue
  echo "Processing ${line}"
  process_packages ${line}
done

echo "Creating symbols archive..."
create_symbols_archive

echo "Uploading symbols..."
upload_symbols

echo "Reprocessing crashes..."
reprocess_crashes

echo "Updating sha256sums..."
update_sha256sums

echo "Cleaning up temporary files..."
remove_temp_files
