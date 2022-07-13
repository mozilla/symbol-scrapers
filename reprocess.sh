#!/bin/bash

. $(dirname $0)/common.sh

unset TASK_ID

SYMBOLS_ARCHIVE_URL="$1"
SYMBOLS_ARCHIVE=$(basename "${SYMBOLS_ARCHIVE_URL}")

wget "${SYMBOLS_ARCHIVE_URL}"

mkdir -p symbols/
unzip -d symbols/ "${SYMBOLS_ARCHIVE}"

reprocess_crashes
