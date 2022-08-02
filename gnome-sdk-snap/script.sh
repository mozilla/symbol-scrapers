#!/bin/sh

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

process_snap "gnome-3-38-2004-sdk" "desktop-snappers"

zip_symbols

upload_symbols

reprocess_crashes

remove_temp_files
