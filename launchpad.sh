#!/bin/bash

API_ROOT="https://api.launchpad.net/devel"

function get_snaps()
{
  local store_name=$1
  local team=$2

  # "${API_ROOT}/+snaps?ws.op=findByOwner&owner=https://api.launchpad.net/devel/~${TEAM}"
  find_url="${API_ROOT}/+snaps?ws.op=findByStoreName&store_name=${store_name}&owner=https://api.launchpad.net/devel/~${team}"
  curl -sSL "${find_url}" | jq -r '.entries[] | .self_link'
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
  local file=$(basename $1)
  grep -q -G "${file},[0-9]" SHA256SUMS
}

function get_snap_and_debug_urls()
{
  local store_name=$1
  local team_name=$2

  for snap_link in $(get_snaps "${store_name}" "${team_name}");
  do
    for one_build in $(get_all_builds "${snap_link}");
    do
      if maybe_skip_if_sha256sums ${one_build}; then
        echo "Skipping ${one_build}"
        continue
      fi

      for one_file in $(get_all_files "${one_build}");
      do
        if [ -n "${one_file}" ]; then
          echo "${one_file}"
        fi
      done;
    done;
  done;
}

function fetch_packages()
{
  sort packages.txt | wget -o wget_packages.log --progress=dot:mega -P downloads -c -i -
  rev packages.txt | cut -d'/' -f1 | rev > package_names.txt
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
  local package_filename=$(basename "${1}")
  local package_size=$(stat -c"%s" "${1}")
  printf "${package_filename},${package_size}\n" >> SHA256SUMS
  truncate --size 0 "${1}"
  truncate --size "${package_size}" "${1}"

  if [ -n "${2}" ]; then
    local debuginfo_package_filename=$(basename "${2}")
    local debuginfo_package_size=$(stat -c"%s" "${2}")
    printf "${debuginfo_package_filename},${debuginfo_package_size}\n" >> SHA256SUMS
    truncate --size 0 "${2}"
    truncate --size "${debuginfo_package_size}" "${2}"
  fi
}

function remove_temp_files() {
  rm -rf symbols packages tmp symbols*.zip packages.txt package_names.txt
}

function process_snap_packages() {
  local package_name="${1}"

  for arch in i386 amd64; do
    find downloads -name "${package_name}*_[0-9]*_${arch}.snap" -type f | while read package; do
      local package_filename="${package##downloads/}"
      local debug_filename=$(get_debug_package "${package_filename}")
      if ! maybe_skip_if_sha256sums "${package_filename}" || ! maybe_skip_if_sha256sums "${debug_filename}"; then
        local debuginfo_package=$(get_debug_package "${package}")
        local version=$(get_version "${package_name}" "${package_filename}")

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
            echo "${debuginfo_package}"
            unzip -d symbols "${debuginfo_package}"
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
        add_package_to_list "${package}" "${debuginfo_package}"
      fi
    done
  done
}

function process_snap()
{
  local store_name=$1
  local team_name=$2

  if [ ! -f SHA256SUMS ]; then
    echo "Please provide SHA256SUMS"
    exit 1
  fi

  mkdir -p tmp symbols

  get_snap_and_debug_urls "${store_name}" "${team_name}" >> packages.txt

  fetch_packages

  process_snap_packages "${store_name}"
}
