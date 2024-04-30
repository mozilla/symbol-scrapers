#!/bin/bash

set -e

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

mkdir -p symbols/

SYMBOLS_TASK_ID="$1"
curl -f -o artifacts.json "https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/${SYMBOLS_TASK_ID}/artifacts"
for file in $(jq -r '.artifacts[].name' < artifacts.json); do
    if [[ "${file}" =~ ^public/build/target.crashreporter-symbols.* ]]; then
        base=$(basename "$file")
        curl -L -f -o "$base" "https://firefox-ci-tc.services.mozilla.com/api/queue/v1/task/${SYMBOLS_TASK_ID}/artifacts/${file}"
        unzip -d symbols/ "$base"
    fi
done

reprocess_crashes
