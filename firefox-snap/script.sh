#!/bin/sh

export DEBUGINFOD_URLS="https://debuginfod.ubuntu.com/"

. $(dirname $0)/../common.sh
. $(dirname $0)/../launchpad.sh

process_snap "firefox-snap-stable" "firefox" "mozilla-snaps"
process_snap "firefox-snap-stable-chemspill" "firefox" "mozilla-snaps"
process_snap "firefox-snap-esr" "firefox" "mozilla-snaps"
process_snap "firefox-snap-esr-chemspill" "firefox" "mozilla-snaps"
process_snap "firefox-snap-beta" "firefox" "mozilla-snaps"
process_snap "firefox-snap-core22" "firefox" "mozilla-snaps"
process_snap "firefox-snap-nightly" "firefox" "mozilla-snaps"

zip_symbols

upload_symbols

reprocess_crashes

remove_temp_files
