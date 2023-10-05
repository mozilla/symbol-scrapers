#!/bin/bash

export LC_ALL=C

unalias -a

cpu_count=$(grep -c ^processor /proc/cpuinfo)
declare -r artifact_filename="target.crashreporter-symbols.zip"

function is_taskcluster()
{
  if [ -z "${TASK_ID}" ]; then
    echo "Not running on TC"
    return 1
  else
    echo "Running on TC: ${TASK_ID}"
    return 0
  fi
}

function download_taskcluster_secret()
{
  local secret_name=$1
  if [ -z "${secret_name}" ]; then
    echo "No CRASHSTATS_SECRET, aborting"
    exit 1
  fi

  local url="http://taskcluster/secrets/v1/secret/${secret_name}"
  curl -sSL -H "Content-Type: application/json" "${url}" | jq -r '.secret.token'
}

function upload_symbols_directly()
{
  local myfile="${artifact_filename}"
  printf "Uploading ${myfile}\n"
  while : ; do
    res=$(curl -H "auth-token: ${SYMBOLS_API_TOKEN}" --form ${myfile}=@${myfile} https://symbols.mozilla.org/upload/)
    if [ -n "${res}" ]; then
      echo "${res}"
      break
    fi
  done
}

function get_build_id {
  eu-readelf -n "${1}" | grep "^    Build ID:" | cut -b15-
}

function find_debuginfo() {
  local buildid=$(get_build_id "${1}")
  local prefix=$(echo "${buildid}" | cut -b1-2)
  local suffix=$(echo "${buildid}" | cut -b3-)
  local debuginfo=$(find packages -path "*/${prefix}/${suffix}*.debug" | head -n1)

  if [ -z "${debuginfo}" ]; then
    local path="${1##packages/}"
    debuginfo=$(find packages -path "*/debug/${path}" -type f)
  fi

  # this was from opensuse's find_debug_info
  if [ \( -z "${debuginfo}" \) -a \( -d "packages/usr/lib/debug" \) ]; then
    debuginfo=$(find "packages/usr/lib/debug" -name $(basename "${1}")-"${2}".debug -type f | head -n 1)
  fi

  if [ -z "${debuginfo}" ]; then
    debuginfo=$(debuginfod-find debuginfo "${buildid}" 2>/dev/null)

    if [ $? -ne 0 ]; then
      debuginfo="" # Discard debuginfod-find output on failure
    fi
  fi

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
  zip -r -9 "../${artifact_filename}" .
  cd ..
}

function unpack_rpm_package() {
  mkdir packages
  if [ -n "${1}" ]; then
    rpm2cpio "${1}" | cpio --quiet -i -d -D packages
  fi

  if [ -n "${2}" ]; then
    rpm2cpio "${2}" | cpio --quiet -i -d -D packages
  fi
}

function upload_symbols()
{
  if is_taskcluster; then
    # When we are running on taskcluster, repackage everything to
    # /builds/worker/artifacts/target.crashreporter-symbols.zip
    mv "${artifact_filename}" "/builds/worker/artifacts/${artifact_filename}"
    ls -hal "/builds/worker/artifacts/${artifact_filename}"
  else
    # Otherwise perform the upload ourselves
    upload_symbols_directly
  fi
}

function reprocess_crashes()
{
  if ! is_taskcluster; then
    find symbols -name "*.sym" -type f > symbols.list

    touch crashes.list
    cat symbols.list | while read symfile; do
      debug_id=$(head -n1 "${symfile}" | cut -d' ' -f4)
      module_name=$(head -n2 "${symfile}" | tail -n1 | cut -d' ' -f4)
      if [ -z "${module_name}" ]; then
        module_name=$(head -n1 "${symfile}" | cut -d' ' -f5-)
      fi
      crashes=$(supersearch --num=all --modules_in_stack="${module_name}/${debug_id}")
      if [ $? -ne 0 ]; then
        echo "Error doing supersearch: aborting"
        exit 1
      fi
      echo "${crashes}" >> crashes.list
    done

    sort -u crashes.list > crashes.list.sorted
    mv -f crashes.list.sorted crashes.list

    if [ -n "$(cat crashes.list)" ]; then
      cat crashes.list | reprocess --sleep 5
      if [ $? -ne 0 ]; then
        echo "Error doing reprocesss: aborting"
        exit 1
      fi
    fi
  fi
}

function update_sha256sums() {
  # We store the package names along with the current date, we will use these dates
  # in the future but for the time being we just need a package-name,number format.
  cat unfiltered-packages.txt | rev | cut -d'/' -f1 | rev | sed -e "s/$/,$(date "+%s")/" > SHA256SUMS
}

if [ -z "${DUMP_SYMS}" ]; then
  printf "You must set the \`DUMP_SYMS\` enviornment variable before running the script\n"
  exit 1
fi

# If we are not running on TaskCluster ensure we have what is needed to perform
# upload later

if ! is_taskcluster; then
  if [ -z "${SYMBOLS_API_TOKEN}" ]; then
    printf "You must set the \`SYMBOLS_API_TOKEN\` enviornment variable before running the script\n"
    exit 1
  fi
  if [ -z "${CRASHSTATS_API_TOKEN}" ]; then
    printf "You must set the \`CRASHSTATS_API_TOKEN\` enviornment variable before running the script\n"
    exit 1
  fi
fi
