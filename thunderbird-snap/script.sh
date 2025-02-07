#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

process_snap "thunderbird" "thunderbird" "desktop-snappers"
process_snap "thunderbird-stable-core24" "thunderbird" "desktop-snappers"
process_snap "thunderbird-beta" "thunderbird" "desktop-snappers"

create_symbols_archive

upload_symbols

reprocess_crashes

remove_temp_files
