#!/bin/sh

. $(dirname $0)/../common.sh
. $(dirname $0)/../flatpak.sh

process_flatpak                                                        \
	"org.mozilla.firefox/x86_64/stable"                            \
	"org.freedesktop.Platform.GL.Debug.default/x86_64/22.08"       \
	"org.freedesktop.Platform.GL.Debug.default/x86_64/22.08-extra" \
	"org.freedesktop.Platform.GL.Debug.default/x86_64/23.08"       \
	"org.freedesktop.Platform.GL.Debug.default/x86_64/23.08-extra" \
	"org.freedesktop.Platform.GL.Debug.default/x86_64/24.08"       \
	"org.freedesktop.Platform.GL.Debug.default/x86_64/24.08-extra"

create_symbols_archive

upload_symbols

reprocess_crashes

remove_temp_files
