#!/bin/bash

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

function zip_symbols() {
  cd symbols
  zip -r -9 "../${artifact_filename}" .
  cd ..
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
    find symbols -mindepth 2 -maxdepth 2 -type d | while read module; do
      module_name=${module##symbols/}
      crashes=$(supersearch --num=all --modules_in_stack=${module_name})
      if [ -n "${crashes}" ]; then
       echo "${crashes}" | reprocess
      fi
    done
  fi
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
