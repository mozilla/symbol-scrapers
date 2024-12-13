#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

process_snap "firefox-snap-stable" "firefox" "mozilla-snaps"
process_snap "firefox-snap-stable-chemspill" "firefox" "mozilla-snaps"
process_snap "firefox-snap-esr" "firefox" "mozilla-snaps"
process_snap "firefox-snap-esr-128" "firefox" "mozilla-snaps"
process_snap "firefox-snap-esr-chemspill" "firefox" "mozilla-snaps"
process_snap "firefox-snap-beta" "firefox" "mozilla-snaps"
process_snap "firefox-snap-nightly" "firefox" "mozilla-snaps"
process_snap "firefox-snap-stable-core24" "firefox" "mozilla-snaps"
process_snap "firefox-snap-beta-core24" "firefox" "mozilla-snaps"

create_symbols_archive

upload_symbols

reprocess_crashes

remove_temp_files
