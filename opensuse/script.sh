#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.opensuse.org/"

. $(dirname $0)/../common.sh

URL="https://download.opensuse.org"
URL2="https://ftp.gwdg.de/pub/linux/misc/packman/suse"
URL3="https://download.nvidia.com/opensuse"

RELEASES="
15.5
15.6
16.0
tumbleweed
"

ARCHITECTURES="
x86_64
"

function get_release_regex() {
  local release_list=$(echo ${RELEASES} | tr ' ' '\|')
  printf "(${release_list})"
}

function get_release_name_regex() {
  printf "("
  for release in ${RELEASES}; do
    if [ "${release}" = "tumbleweed" ]; then
      printf "openSUSE_Tumbleweed|"
    else
      printf "openSUSE_Leap_${release}|"
    fi
  done
  printf "openSUSE_Factory)"
}

function get_architecture_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | tr ' ' '\|')
  printf "(${architecture_list})"
}

function get_architecture_escaped_regex() {
  local architecture_list=$(echo ${ARCHITECTURES} | sed -e "s/ /\\\|/")
  printf "\(${architecture_list}\)"
}

function fetch_indexes() {
  local architecture_regex=$(get_architecture_regex)
  local release_regex=$(get_release_regex)

  local url="${URL}"
  local regex="${url}/(debug/)?(update/)?(distribution/)?(leap/)?(${release_regex}(-test)?/)?(repo/)?((oss|debug)/)?(${architecture_regex}/)?$"
  ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive -l 8 --accept-regex "${regex}" "${url}/"

  local release_name_regex=$(get_release_name_regex)
  regex="${url}/(repositories/)?((mozilla|mozilla%3A)/)?(Factory/)?(${release_name_regex}(_debug)?/)?(${architecture_regex}/)?$"
  ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive --accept-regex "${regex}" "${url}/"

  url="${URL2}"
  regex="${url}/(${release_name_regex}/)?(Essentials/)?(${architecture_regex}/)?$"
  ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive --accept-regex "${regex}" "${url}/"

  url="${URL3}"
  regex="${url}/(leap/)?(${release_regex}/)?(${architecture_regex}/)?$"
  ${WGET} -o wget_indexes.log --directory-prefix indexes --convert-links --recursive --accept-regex "${regex}" "${url}/"
}

function get_package_urls() {
  truncate -s 0 all-packages.txt unfiltered-packages.txt

  find indexes -name index.html -exec xmllint --html --xpath '//a/@href' {} \; 2>xmllint_error.log | \
    grep -o "https\?://.*\.rpm" | grep -v -- "-32bit-" | sort -u >> all-packages.txt

  local architecture_escaped_regex=$(get_architecture_escaped_regex)
  echo "${PACKAGES}" | grep -v '^$' | cut -d' ' -f2 | while read package; do
    grep -o "https\?://.*/${package}\(-debuginfo\)\?-[0-9].*\.${architecture_escaped_regex}\.rpm" all-packages.txt >> unfiltered-packages.txt
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

function remove_temp_files() {
  rm -rf all-packages.txt crashes.list downloads downloads.txt indexes \
         packages symbols symbols.list tmp unfiltered-packages.txt \
         xmllint_error.log
}

echo "Cleaning up temporary files..."
remove_temp_files
mkdir -p downloads indexes symbols tmp

PACKAGES="
alsa
apitrace-wrappers
at-spi2-atk-gtk2
at-spi2-core
dbus-1-glib
firefox-esr
fontconfig
glibc
glib-networking
gnome-vfs2
gsettings-backend-dconf
intel-media-driver
intel-vaapi-driver
libasound2
libatk-1_0-0
libatk-bridge-2_0-0
libavcodec[0-9][0-9]
libavfilter[0-9]
libavformat[0-9][0-9]
libavresample[0-9]
libavutil[0-9][0-9]
libcairo2
libcloudproviders0
libcups2
libdbus-1-3
libdconf1
libdrm2
libdrm_amdgpu1
libdrm_intel1
libdrm_nouveau2
libdrm_radeon1
libepoxy0
libevent-2_1-7
libexpat1
libfam0-gamin
libffi8
libfreetype6
libfribidi0
libgbm1
libgcc_s1
libgdk_pixbuf-2_0-0
libgio-2_0-0
libgio-fam
libglib-2_0-0
libglvnd
libgobject-2_0-0
libgtk-2_0-0
libgtk-3-0
libhwy1
libibus-1_0-5
libICE6
libicu[0-9][0-9]
libigdgmm12
libjemalloc2
libnuma1
libnvidia-egl-wayland1
libnvidia-egl-x111
libopus0
libp11-kit0
libpango-1_0-0
libpcre1
libpcre2-8-0
libpcslite1
libpipewire-0_3-0
libpixman-1-0
libpng12-0
libpng16-16
libpostproc[0-9][0-9]
libproxy1
libproxy1
libproxy1-config-kde
libpulse0
libSM6
libsoftokn3
libsqlite3-0
libstdc++6
libswresample[0-9]
libswscale[0-9]
libsystemd0
libthai0
libva2
libva-vdpau-driver
libvpx4
libvulkan1
libvulkan_intel
libvulkan_radeon
libwayland-client0
libX11-6
libx264-[0-9][0-9][0-9]
libx265-[0-9][0-9][0-9]
libxcb1
libXext6
libxkbcommon0
libxml2-2
libxvidcore4
libz1
libzvbi0
Mesa-dri
Mesa-dri-nouveau
Mesa-gallium
Mesa-libEGL1
Mesa-libGL1
Mesa-libva
MozillaFirefox
MozillaThunderbird
mozilla-nspr
mozilla-nss
nvidia-compute-G[0-9][0-9]
nvidia-gl-G[0-9][0-9]
nvidia-glG[0-9][0-9]
nvidia-utils-G[0-9][0-9]
nvidia-video-G[0-9][0-9]
openCryptoki-64bit
opensc
p11-kit
pipewire-spa-plugins-0_2
speech-dispatcher
x11-video-nvidiaG[0-9][0-9]
"

echo "Fetching packages..."
fetch_indexes
get_package_urls
fetch_packages

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
  done
}

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
