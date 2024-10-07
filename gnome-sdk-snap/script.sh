#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

process_snap "gnome-3-38-2004-sdk" "gnome-3-38-2004-sdk" "desktop-snappers"
process_snap "gnome-42-2204-sdk" "gnome-42-2204-sdk" "desktop-snappers"

create_symbols_archive

upload_symbols

reprocess_crashes

remove_temp_files
