#!/bin/sh

# Alpine doesn't have a debuginfod server yet
# export DEBUGINFOD_URLS=""

. $(dirname $0)/../common.sh

URL="http://dl-cdn.alpinelinux.org/alpine"

RELEASES="
edge
v3.19
v3.20
v3.21
v3.22
"

REPOS="
main
community
"

ARCHITECTURES="
aarch64
x86_64
"

# <package name> [<debug package name>]
PACKAGES="
alsa-lib
aom-libs
brotli-libs
busybox-binsh
cairo
cairo-gobject cairo
cups-libs
dbus-libs
dconf
ffmpeg-libavcodec
ffmpeg-libavutil
ffmpeg-libswresample
firefox
firefox-esr
fontconfig
freetype
fribidi
gdk-pixbuf
glib
graphite2
gtk+3.0
harfbuzz
icu-libs
lame-libs
libatk-1.0
libatk-bridge-2.0
libbsd
libbz2
libcrypto3
libdav1d
libdrm
libepoxy
libevent
libexpat
libffi
libgcc
libintl
libjpeg-turbo
libjxl
libmount
libpciaccess
libpng
libpulse
libssl3
libstdc++
libtheora
libva
libva-vdpau-driver
libvorbis
libvpx
libwebp
libwebpdemux
libwebpmux
libx11
libxau
libxbcommon
libxcb
libxcomposite
libxcursor
libxdamage
libxdmcp
libxext
libxfixes
libxft
libxi
libxinerama
libxrandr
libxrender
libxshmfence
libxxf86vm
llvm[0-9][0-9]-libs
mesa
mesa-dri-gallium mesa
mesa-egl mesa
mesa-gbm mesa
mesa-glapi mesa
mesa-gles mesa
mesa-gl mesa
mesa-osmesa mesa
mesa-va-gallium mesa
mesa-vdpau-gallium mesa
mesa-vulkan-ati mesa
mesa-vulkan-intel mesa
mesa-vulkan-layers mesa
mesa-vulkan-swrast mesa
mesa-xatracker mesa
musl
nspr
nss
opus
pango
pciutils-libs
pcre2
pipewire
pipewire-libs
pixman
rav1e-libs
scudo-malloc
sqlite-libs
wayland
wayland-libs-client wayland
wayland-libs-cursor wayland
wayland-libs-egl wayland
x264-libs
x265-libs
zlib
"

function get_release_regex() {
  local release_list=$(echo ${RELEASES} | tr ' ' '\|')
  printf "(${release_list})"
}

function get_repo_regex() {
  local repo_regex=$(echo ${REPOS} | tr ' ' '\|')
  printf "(${repo_regex})"
}

function get_architecture_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | tr ' ' '\|')
  printf "(${architecture_list})"
}

function fetch_indexes() {
  local release_regex=$(get_release_regex)
  local repo_regex=$(get_repo_regex)
  local architecture_regex=$(get_architecture_regex)

  local regex="${URL}/(${release_regex}/)?(${repo_regex}/)?(${architecture_regex}/)?$"
  ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive --accept-regex "${regex}" "${URL}/"
}

function get_package_urls() {
  truncate -s 0 all-packages.txt unfiltered-packages.txt

  find indexes -name index.html -exec xmllint --html --xpath '//a/@href' {} \; 2>xmllint_error.log | \
    grep -o "https\?://.*\.apk" | sort -u >> all-packages.txt

  echo "${PACKAGES}" | grep -v '^$' | while read line; do
    # Use percent encoding in package URLs, e.g. + -> %2B
    local package_name="$(echo ${line} | cut -d' ' -f1 | sed 's/\+/%2B/g')"
    grep -o "https\?://.*/${package_name}\(-dbg\)\?-[0-9].*\.apk" all-packages.txt >> unfiltered-packages.txt
  done
}

# Alpine packages have the same names across different architectures and distro
# versions, so we need to fetch them in separate directories to avoid each
# combination overwriting the others.
function fetch_packages() {
  echo "${RELEASES}" | while read release; do
    [ -z "${release}" ] && continue
    echo "${ARCHITECTURES}" | grep -v '^$' | while read architecture; do
      [ -z "${architecture}" ] && continue
      truncate -s 0 downloads.txt
      local download_folder="downloads/${release}/${architecture}"
      mkdir -p "${download_folder}"
      grep "${release}.*${architecture}" unfiltered-packages.txt | while read line; do
        local package_name=$(echo "${line}" | rev | cut -d'/' -f1 | rev)
        if ! grep -q "${release}.*${architecture}.*${package_name}" SHA256SUMS; then
          echo "${line}" >> downloads.txt
        fi
      done
      sort downloads.txt | ${WGET} -o wget_packages.log -P "${download_folder}" -c -i -
    done
  done
}

function get_version() {
  local package_name="${1}"
  local filename="${2}"

  local version="${filename##${package_name}-}"
  version="${version%%.apk}"
  printf "${version}"
}

function find_debuginfo_package() {
  local download_dir="${1}"
  local package_name="${2}"
  local version="${3}"
  find "downloads/${download_dir}" -name "${package_name}-dbg-${version}.apk" -type f
}

function unpack_package() {
  local package_name="${1}"
  local debug_package_name="${2}"
  mkdir packages
  gzip -d -c -q "${package_name}" | tar -C packages -x --warning=no-unknown-keyword
  if [ $? -ne 0 ]; then
    printf "Failed to extract ${package_name}\n" 2>>error.log
  fi
  if [ -n "${debug_package_name}" ]; then
    gzip -d -c -q "${debug_package_name}" | tar -C packages -x --warning=no-unknown-keyword
    if [ $? -ne 0 ]; then
      printf "Failed to extract ${debug_package_name}\n" 2>>error.log
    fi
  fi
}

function process_packages() {
  local download_dir="${1}"
  local package_name="${2}"
  local debug_package_name="${3:-${package_name}}"
  find "downloads/${download_dir}" -name "${package_name}-[0-9]*.apk" -type f | grep -v -e "-dbg-" | while read package; do
    local package_filename="$(basename ${package})"
    local version=$(get_version "${package_name}" "${package_filename}")
    local debuginfo_package=$(find_debuginfo_package "${download_dir}" "${debug_package_name}" "${version}")

    if [ -n "${debuginfo_package}" ]; then
      unpack_package ${package} ${debuginfo_package}
    else
      printf "***** Could not find debuginfo for ${package_filename}\n"
      unpack_package ${package}
    fi

    find packages -type f | grep -v debug | while read path; do
      if file "${path}" | grep -q ": *ELF" ; then
        local build_id=$(get_build_id "${path}")

        if [ -z "${build_id}" ]; then
          printf "Skipping ${path} because it does not have a GNU build id\n"
          continue
        fi

        local debuginfo_path="$(find_debuginfo "${path}" "${version}")"

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
echo "${RELEASES}" | while read release; do
  [ -z "${release}" ] && continue
  echo "${ARCHITECTURES}" | while read architecture; do
    [ -z "${architecture}" ] && continue
    echo "${PACKAGES}" | while read line; do
      [ -z "${line}" ] && continue
      echo "Processing ${release}/${architecture} ${line}"
      process_packages "${release}/${architecture}" ${line}
    done
  done
done

echo "Creating symbols archive..."
create_symbols_archive

echo "Uploading symbols..."
upload_symbols

echo "Reprocessing crashes..."
reprocess_crashes

echo "Updating sha256sums..."
cat unfiltered-packages.txt | sort -u | sed -e "s/$/,$(date "+%s")/" > SHA256SUMS

echo "Cleaning up temporary files..."
remove_temp_files
