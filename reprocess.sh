#!/bin/bash

. $(dirname $0)/common.sh

if [ -z "${TASK_ID}" ]; then
  echo "Expected a TaskCluster TASK_ID."
  exit 1
fi

unset TASK_ID

set +x
export CRASHSTATS_API_TOKEN=$(download_taskcluster_secret "${CRASHSTATS_SECRET}")

if [ -z "${CRASHSTATS_API_TOKEN}" ]; then
  echo "No token, aborting."
  exit 1
fi

SYMBOLS_ARCHIVE_URL="$1"
SYMBOLS_ARCHIVE=$(basename "${SYMBOLS_ARCHIVE_URL}")

wget "${SYMBOLS_ARCHIVE_URL}"

mkdir -p symbols/
unzip -d symbols/ "${SYMBOLS_ARCHIVE}"

reprocess_crashes
