#!/bin/sh

. $(dirname $0)/../common.sh

URL="https://www.techpowerup.com"
AMD_PATH="download/amd-radeon-graphics-drivers/"
AMD_SYMBOL_SERVER="SRV*store*https://msdl.microsoft.com/download/symbols;SRV*store*https://download.amd.com/dir/bin"
INTEL_PATH="download/intel-graphics-drivers/"
INTEL_SYMBOL_SERVER="SRV*store*https://msdl.microsoft.com/download/symbols;SRV*store*https://software.intel.com/sites/downloads/symbols"
NVIDIA_PATH="download/nvidia-geforce-graphics-drivers/"
NVIDIA_SYMBOL_SERVER="SRV*store*https://msdl.microsoft.com/download/symbols;SRV*store*https://driver-symbols.nvidia.com"

# Maximum number of drivers we'll process in one go, we don't want to put too
# much load on TechPowerUp's resources.
max_left_to_process=10

# The first arguent is the path used to fetch the drivers, the second is the
# symbol server to be used when dumping the symbols
function fetch_and_process_drivers() {
  local url="${URL}/${1}"
  local symbol_server="${2}"
  touch index.html

  count=$(wc -l < SHA256SUMS)

  # Sometimes we get an empty response so try multiple times
  while [ $(stat -c%s index.html) -eq 0 ]; do
    curl -s --output index.html "${url}"
  done

  local driver_name=""
  local driver_id=""
  grep -o "\(name=\"id\" value=\"[0-9]\+\"\|<div class=\"filename\".*\)" index.html | while read line; do
    # Odd lines contain the filename and even lines the ID
    if [ -z "${driver_name}" ]; then
      driver_name=$(echo "${line}" | cut -d'>' -f2 | cut -d'<' -f1)
    else
      driver_id=$(echo "${line}" | cut -d'"' -f4)

      if ! grep -q "${driver_name}" SHA256SUMS; then
        if [ "${max_left_to_process}" -le 0 ]; then
          break
        fi

        # We haven't seen this driver yet, process it
        server_id=$(curl -s "${url}" -d "id=${driver_id}" | grep -m 1 -o "name=\"server_id\" value=\"[0-9]\+\"" | cut -d'"' -f4)
        location=$(curl -s -i "${url}" -d "id=${driver_id}&server_id=${server_id}" | grep "^location:" | tr -d "\r" | cut -d' ' -f2)
        curl -s --output-dir downloads --remote-name "${location}"
        7zz -otmp x "downloads/${driver_name}"
        find tmp -iname "*.dll" | while read file; do
          if file "${file}" | grep -q -v "Mono/.Net"; then
            "${DUMP_SYMS}" --check-cfi --inlines --store symbols --symbol-server "${symbol_server}" --verbose error "${file}"
          fi
        done
        rm -rf tmp "downloads/${driver_name}"
        add_driver_to_list "${driver_name}"

        max_left_to_process=$((max_left_to_process - 1))
      fi

      # Move on to the next driver
      driver_name=""
      driver_id=""
    fi
  done

  # We're done
  rm -f index.html

  count=$(($(wc -l < SHA256SUMS) - count))
  max_left_to_process=$((max_left_to_process - count))
}

function remove_temp_files() {
  rm -rf downloads store symbols tmp symbols*.zip
}

function add_driver_to_list() {
  local driver_name="${1}"
  local driver_date=$(date "+%s")
  printf "${driver_name},${driver_date}\n" >> SHA256SUMS
}

mkdir -p downloads symbols

fetch_and_process_drivers "${AMD_PATH}" "${AMD_SYMBOL_SERVER}"
fetch_and_process_drivers "${INTEL_PATH}" "${INTEL_SYMBOL_SERVER}"
fetch_and_process_drivers "${NVIDIA_PATH}" "${NVIDIA_SYMBOL_SERVER}"

create_symbols_archive

upload_symbols

reprocess_crashes

remove_temp_files
