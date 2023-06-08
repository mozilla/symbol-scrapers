#!/bin/bash

local_dir=$(dirname $0)
pkgs_dir=${local_dir}/packages/

app_name=
commit=

function setup_flatpak()
{
  XDG_DATA_HOME=${pkgs_dir} flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
}

function install_flatpak_and_deps()
{
  local full_name=$1

  app_name=$(XDG_DATA_HOME=${pkgs_dir} flatpak remote-info --user -r flathub ${full_name} | sed -e 's/^runtime\///g' -e 's/^app\///g')
  commit=$(XDG_DATA_HOME=${pkgs_dir} flatpak remote-info --user -c flathub ${full_name})

  if maybe_skip_if_sha256sums "${app_name}" "${commit}" ; then
    echo "Skipping ${app_name}:${commit} (SHA256SUMS)"
    return
  fi

  XDG_DATA_HOME=${pkgs_dir} flatpak install --user --include-sdk --include-debug ${full_name} --noninteractive
}

function maybe_skip_if_sha256sums()
{
  local pkg=$1
  local hash=$2
  grep -q -G "${pkg},${hash}" SHA256SUMS
}

function get_pkg_hash()
{
  local package_name="${1}"
  local package_hash=$(basename `find ${pkgs_dir}/flatpak/runtime/${package_name}/ -mindepth 1 -maxdepth 1 -type d`)
  echo "${package_hash}"
}

function add_package_to_list()
{
  local package_name="${1}"
  local package_hash="${2}"
  printf "${package_name},${package_hash}\n" >> SHA256SUMS
}

function process_flatpak_package() {
  find ${pkgs_dir}/flatpak/runtime/ -mindepth 3 -maxdepth 3 -type d | while read package_full; do
    pkg_ver=$(echo "${package_full}" | rev | cut -d '/' -f 1 | rev)
    pkg_arch=$(echo "${package_full}" | rev | cut -d '/' -f 2 | rev)
    pkg_name=$(echo "${package_full}" | rev | cut -d '/' -f 3 | rev)
    package="${pkg_name}/${pkg_arch}/${pkg_ver}"
    package_hash=$(get_pkg_hash "${package}")
    if maybe_skip_if_sha256sums "${package}" "${package_hash}" ; then
      echo "Skipping ${package} (SHA256SUMS)"
      continue
    fi

    find ${pkgs_dir}/flatpak/runtime/${package} -name "*.debug" -type f | while read path; do
      truncate --size=0 error.log
          filename=$(basename "${path}")
	  if [ "${filename}" = "[.debug" ]; then
            echo "Skipping [.debug since it will make socorro choke"
	    continue
	  fi
          if file "${path}" | grep -q ": *ELF" ; then
            local tmpfile=$(mktemp --tmpdir=tmp)
            printf "Writing symbol file for ${path} ... "
            ${DUMP_SYMS} --inlines "${path}" 1> "${tmpfile}" 2>>error.log
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

      if [ -s error.log ]; then
        printf "***** error log for package ${package}\n"
        cat error.log
        printf "***** error log for package ${package} ends here\n"
      fi

    done
    #rm -rf packages
    add_package_to_list "${package}" "${package_hash}"
  done
}

function remove_temp_files() {
  rm -rf symbols packages tmp symbols*.zip packages.txt package_names.txt
}

function process_flatpak()
{
  local store_name=$1
  shift

  local extra_deps=$@

  if [ ! -f SHA256SUMS ]; then
    echo "Please provide SHA256SUMS"
    exit 1
  fi

  mkdir -p tmp symbols

  echo "Will install ${store_name}"
  echo "Extra deps ${extra_deps}"

  setup_flatpak

  install_flatpak_and_deps "${store_name}"

  for dep in ${extra_deps};
  do
    install_flatpak_and_deps "${dep}"
  done;

  process_flatpak_package

  if [ -n "${app_name}" -a -n "${commit}" ]; then
    add_package_to_list "${app_name}" "${commit}"
  else
    echo "Missing app_name (${app_name}) or commit (${commit}). Not normal."
    exit 1
  fi
}
