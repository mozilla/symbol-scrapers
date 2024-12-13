#!/bin/bash

API_ROOT="https://api.launchpad.net/devel"

function get_snaps()
{
  local search_term=$1
  local team=$2

  API_COMMAND="getByName"
  API_PARAM="name"
  find_url="${API_ROOT}/+snaps?ws.op=${API_COMMAND}&${API_PARAM}=${search_term}&owner=https://api.launchpad.net/devel/~${team}"
  curl -sSL "${find_url}" | jq -r '.self_link'
}

function get_all_builds()
{
  local snap_link=$1
  completed_builds=$(curl -sSL ${snap_link} | jq -r '.completed_builds_collection_link')
  curl -sSL ${completed_builds} | jq -r '.entries[] | .self_link'
}

function get_all_files()
{
  local one_build=$1
  getFileUrls="${one_build}/?ws.op=getFileUrls"
  curl -sSL ${getFileUrls} | jq -r '.[]'
}

function maybe_skip_if_sha256sums()
{
  local fname=$1
  local pkg_name=$2

  local file=$(basename $fname | sed -e "s/\./\\\./g")
  grep -q -G "${pkg_name},${file},[0-9]" SHA256SUMS
}

function get_valid_arches()
{
  echo i386 amd64 arm64
}

function is_diff_arch()
{
  local arch=$1
  local file=$2
  local this_arch=$(echo "$file" | rev | cut -d'_' -f1| rev | cut -d'.' -f1)
  test "${arch}" != "${this_arch}"
}

function maybe_skip_if_invalid_arch()
{
  local file=$(basename "$1")
  for arch in $(get_valid_arches);
  do
    if ! is_diff_arch ${arch} ${file}; then
      return 1
    fi
  done;
  return 0
}

function get_snap_and_debug_urls()
{
  local pkg_name=$1
  local team_name=$2

  for snap_link in $(get_snaps "${pkg_name}" "${team_name}");
  do
    for one_build in $(get_all_builds "${snap_link}");
    do
      if maybe_skip_if_sha256sums "${one_build}" "${pkg_name}"; then
        >&2 echo "Skipping ${one_build} (SHA256SUMS)"
        continue
      fi

      for one_file in $(get_all_files "${one_build}");
      do
        if maybe_skip_if_invalid_arch ${one_file}; then
          >&2 echo "Skipping ${one_file} (unsupported arch)"
          continue
        fi

        if [ -n "${one_file}" ]; then
          echo "${one_file}"
        fi
      done;
    done;
  done;
}

function fetch_packages()
{
  local pkg_name="${1}"
  sort packages_${pkg_name}.txt | while read -r line; do
     BUILDID=$(echo "$line" | sed -e 's/.*+build\///g' -e 's/\/+files.*//g');
     TARGET_FNAME=$(basename "$line" | sed -e "s/\.debug$/_${BUILDID}.debug/" | sed -e "s/\.snap$/_${BUILDID}.snap/")
     echo -e "$line\n out=$TARGET_FNAME";
  done | tee package_buildid_${pkg_name}.txt | aria2c --show-console-readout=false --summary-interval=0 --console-log-level=error --log-level=notice --log wget_packages_${pkg_name}.log -d downloads/${pkg_name} --auto-file-renaming=false -c -i -
  rev packages_${pkg_name}.txt | cut -d'/' -f1 | rev > package_names_${pkg_name}.txt
}

function verify_processed()
{
  local pkg_name="${1}"
  local failed=0
  for f in $(grep "complete" wget_packages_${pkg_name}.log | sed -e "s/.*downloads\/${pkg_name}\///g" | grep -F ".debug");
  do
    # We dont want regex to interfere with dots
    if grep -q -F "${pkg_name},${f}," SHA256SUMS; then
      echo "Downloaded ${f} was processed and added to SHA256SUMS"
    else
      echo "Downloaded ${f} was NOT PROCESSED and is MISSING FROM SHA256SUMS"
      local snap_file="downloads/${pkg_name}/${f%%.debug}.snap"
      if [ -f "${snap_file}" ]; then
        echo "Snap package was downloaded:"
        ls -hal "${snap_file}"
      else
        echo "Snap package ${f%%.debug}.snap was MISSING"
      fi
      failed=1
    fi
  done;

  if [ ${failed} -eq 1 ]; then
    exit 1
  fi;
}

function get_version()
{
  local package_name=$1
  local filename=$2

  version="${filename##${package_name}_}"
  version="${version%%.snap}"
  printf "${version}"
}

function get_debug_package()
{
  local filename=$1

  dbg="${filename%%.snap}.debug"
  printf "${dbg}"
}

function unpack_package() {
  local package_name="${1}"
  local debug_package_name="${2}"
  unsquashfs -d packages "${package_name}"
  if [ $? -ne 0 ]; then
    printf "Failed to extract ${package_name}\n" 2>>error.log
  fi
  if [ -n "${debug_package_name}" ]; then
    unzip -d packages "${debug_package_name}"
    if [ $? -ne 0 ]; then
      printf "Failed to extract ${debug_package_name}\n" 2>>error.log
    fi
  fi
}

function add_package_to_list()
{
  local pkg_name=${1}
  local package_filename=$(basename "${2}")
  local package_size=$(stat -c"%s" "${2}")
  printf "${pkg_name},${package_filename},${package_size}\n" >> SHA256SUMS
  truncate --size 0 "${2}"
  truncate --size "${package_size}" "${2}"

  if [ -n "${3}" ]; then
    local debuginfo_package_filename=$(basename "${3}")
    local debuginfo_package_size=$(stat -c"%s" "${3}")
    printf "${pkg_name},${debuginfo_package_filename},${debuginfo_package_size}\n" >> SHA256SUMS
    truncate --size 0 "${3}"
    truncate --size "${debuginfo_package_size}" "${3}"
  fi
}

function remove_temp_files() {
  rm -rf symbols packages tmp symbols*.zip packages*.txt package_names*.txt
}

function process_snap_packages() {
  local package_name="${1}"
  local store_name="${2}"

  for arch in $(get_valid_arches); do
    find downloads/${package_name} -name "${store_name}*_[0-9]*_${arch}*.snap" -type f | while read package; do
      local package_filename="${package##downloads/${package_name}/}"
      local debug_filename=$(get_debug_package "${package_filename}")
      if ! maybe_skip_if_sha256sums "${package_filename}" "${pkg_name}" || ! maybe_skip_if_sha256sums "${debug_filename}" "${pkg_name}"; then
        local debuginfo_package=$(get_debug_package "${package}")
        local version=$(get_version "${store_name}" "${package_filename}")

        truncate --size=0 error.log

        if (zipinfo -l "${debuginfo_package}" | grep -q -c "usr/lib/debug/.build-id/"); then
          # Debug symbols generated "like on distro" so we need to extract
          if [ -n "${debuginfo_package}" ]; then
            unpack_package ${package} ${debuginfo_package}
          else
            echo "***** Could not find debuginfo for ${package_filename}"
            unpack_package ${package}
          fi

          find packages -type f | grep -v debug | while read path; do
            if file "${path}" | grep -q ": *ELF" ; then
              local debuginfo_path="$(find_debuginfo "${path}")"

              [ -z "${debuginfo_path}" ] && printf "Could not find debuginfo for ${path}\n" && continue

              local tmpfile=$(mktemp --tmpdir=tmp)
              printf "Writing symbol file for ${path} ${debuginfo_path} ... "
              ${DUMP_SYMS} --inlines "${path}" "${debuginfo_path}" 1> "${tmpfile}" 2>>error.log
              if [ -s "${tmpfile}" ]; then
                printf "done\n"
              else
                ${DUMP_SYMS} --inlines "${path}" > "${tmpfile}"
                if [ -s "${tmpfile}" ]; then
                  printf "done w/o debuginfo\n"
                else
                  printf "something went terribly wrong!\n"
                fi
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
        else
          echo -n "Processing ${package} ..."
          # Firefox ready-to-use debug symbols
          if [ -f "${debuginfo_package}" ]; then
            echo " ${debuginfo_package}"
            unzip -o -d symbols "${debuginfo_package}"
          else
            echo "!! NO ${debuginfo_package}"
          fi
        fi

        if [ -s error.log ]; then
          printf "***** error log for package ${package}\n"
          cat error.log
          printf "***** error log for package ${package} ends here\n"
        fi

        rm -rf packages
        add_package_to_list "${package_name}" "${package}" "${debuginfo_package}"
      else
        echo "maybe_skip_if_sha256sums ${package_filename} || maybe_skip_if_sha256sums ${debug_filename}"
      fi
    done
  done
}

function process_snap()
{
  local pkg_name=$1
  local store_name=$2
  local team_name=$3

  if [ ! -f SHA256SUMS ]; then
    echo "Please provide SHA256SUMS"
    exit 1
  fi

  mkdir -p tmp symbols

  echo "Processing ${pkg_name} published by ${team_name}"

  get_snap_and_debug_urls "${pkg_name}" "${team_name}" >> packages_${pkg_name}.txt

  fetch_packages "${pkg_name}"

  process_snap_packages "${pkg_name}" "${store_name}"

  verify_processed "${pkg_name}"
}
