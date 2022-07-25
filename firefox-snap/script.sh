#!/bin/sh

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

process_snap "firefox" "mozilla-snaps"

zip_symbols

upload_symbols

reprocess_crashes

remove_temp_files
