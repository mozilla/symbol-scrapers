#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

for branch in $(get_branches "mozilla-snaps"); do
    process_snap "${branch}" "firefox" "mozilla-snaps"
done

create_symbols_archive

upload_symbols

reprocess_crashes

remove_temp_files
