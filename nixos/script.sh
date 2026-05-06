#!/bin/sh

. $(dirname $0)/../common.sh

get_channels() {
  curl -fsSL 'https://prometheus.nixos.org/api/v1/query?query=channel_revision' | jq -r '
    .data.result[]
    | select(.metric.status != "unmaintained")
    | select(.metric.variant != "small")
    | "https://channels.nixos.org/\(.metric.channel)"
  '
}

get_store_paths_url() {
  local channel_url="$1"
  local release_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "${channel_url}")
  echo "${release_url%/}/store-paths.xz"
}

fetch_store_paths() {
  mkdir -p channels store-paths

  for channel_url in $(get_channels); do
    local index_url=$(get_store_paths_url "${channel_url}")
    local channel_name=$(basename "${channel_url}")
    local archive_path="store-paths/${channel_name}.xz"
    local text_path="store-paths/${channel_name}"

    ${WGET} -q -O "${archive_path}" "${index_url}"
    unxz -f "${archive_path}"
    grep -E '[a-z0-9]{32}-(firefox|thunderbird)-.*unwrapped' "${text_path}" |
      grep -Ev '(debug|symbols)' >> unfiltered-packages.txt || true
  done

  sort -u unfiltered-packages.txt | while read store_path; do
    local package_name=$(basename "${store_path}")
    if ! grep -q -F "${package_name}" SHA256SUMS; then
      echo "${store_path}"
    fi
  done > packages.txt
}

copy_store_path() {
  local store_path="$1"
  if grep -qx "${store_path}" seen-store-paths.txt 2>/dev/null; then
    echo "Already processed store path: ${store_path}"
    return 0
  fi
  nix-store --realise "${store_path}"
  echo "${store_path}" >> seen-store-paths.txt
}

fetch_debuginfo_for_build_id() {
  local build_id="$1"
  local build_dir="$2"
  mkdir -p "${build_dir}"
  local metadata=$(curl -fsSL "https://cache.nixos.org/debuginfo/${build_id}" || return 1)
  local archive=$(echo "${metadata}" | jq -r '.archive')
  local member=$(echo "${metadata}" | jq -r '.member')
  { [ -z "${archive}" ] || [ "${archive}" = "null" ]; } && return 1
  { [ -z "${member}" ] || [ "${member}" = "null" ]; } && return 1

  local nar_xz="${build_dir}/$(basename "${archive}")"
  local nar_path="${nar_xz%.xz}"
  local restore_dir="${build_dir}/restore"

  ${WGET} -q -O "${nar_xz}" "https://cache.nixos.org/${archive#../}"
  unxz -f "${nar_xz}" || return 1
  cat "${nar_path}" | nix-store --restore "${restore_dir}/out" >/dev/null 2>&1 || return 1

  local debuginfo_path="${restore_dir}/out/${member}"
  [ -f "${debuginfo_path}" ] || return 1
  echo "${debuginfo_path}"
}

write_symbol_file() {
  local binary_path="$1"
  local debuginfo_path="$2"
  local tmpfile=$(mktemp --tmpdir=tmp)

  if [ -n "${debuginfo_path}" ]; then
    ${DUMP_SYMS} --inlines "${binary_path}" "${debuginfo_path}" >"${tmpfile}" 2>error.log
  else
    ${DUMP_SYMS} --inlines "${binary_path}" >"${tmpfile}" 2>error.log
  fi

  if [ ! -s "${tmpfile}" ]; then
    echo "dump_syms produced empty output for ${binary_path}" >&2
    rm -f "${tmpfile}"
    return 1
  fi

  local debug_id=$(head -n1 "${tmpfile}" | cut -d' ' -f4)
  local filename=$(basename "${binary_path}")
  local soname

  mkdir -p "symbols/${filename}/${debug_id}"
  cp "${tmpfile}" "symbols/${filename}/${debug_id}/${filename}.sym"

  soname=$(get_soname "${binary_path}")
  if [ -n "${soname}" ] && [ "${soname}" != "${filename}" ]; then
    mkdir -p "symbols/${soname}/${debug_id}"
    cp "${tmpfile}" "symbols/${soname}/${debug_id}/${soname}.sym"
  fi

  rm -f "${tmpfile}"
}

process_elf() {
  local elf_path="$1"
  local build_id=$(get_build_id "${elf_path}")
  [ -n "${build_id}" ] || return 0
  if grep -qx "${build_id}" seen-buildids.txt 2>/dev/null; then
    return 0
  fi
  echo "${build_id}" >> seen-buildids.txt
  local debuginfo_path=$(fetch_debuginfo_for_build_id "${build_id}" "tmp/${build_id}" || true)
  write_symbol_file "${elf_path}" "${debuginfo_path}" || true
}

process_store_path() {
  local store_path="$1"

  copy_store_path "${store_path}"
  nix-store --query --requisites "${store_path}" | while read -r req; do
    [ -z "${req}" ] && continue
    copy_store_path "${req}"
    find "${req}" -type f \( -name '*.so' -o -perm /a+x \) 2>/dev/null | while read -r path; do
      if file "${path}" | grep -q ": *ELF"; then
        process_elf "${path}"
      fi
    done
  done
}

remove_temp_files() {
  rm -rf channels store-paths symbols tmp \
         crashes.list symbols.list packages.txt unfiltered-packages.txt \
         seen-buildids.txt seen-store-paths.txt error.log
}

echo "Cleaning up temporary files..."
remove_temp_files
mkdir -p symbols tmp

echo "Fetching packages..."
fetch_store_paths

echo "Processing packages..."
while read -r store_path; do
  [ -z "${store_path}" ] && continue
  process_store_path "${store_path}"
done < packages.txt

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
