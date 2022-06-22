#!/bin/sh
unalias -a

if [ -z "${DUMP_SYMS}" ]; then
  printf "You must set the \`DUMP_SYMS\` enviornment variable before running the script\n"
  exit 1
fi

if [ -z "${SYMBOLS_API_TOKEN}" ]; then
  printf "You must set the \`SYMBOLS_API_TOKEN\` enviornment variable before running the script\n"
  exit 1
fi

if [ -z "${CRASHSTATS_API_TOKEN}" ]; then
  printf "You must set the \`CRASHSTATS_API_TOKEN\` enviornment variable before running the script\n"
  exit 1
fi

URL="http://packages.linuxmint.com/pool"

get_package_urls() {
  url="${URL}/upstream/f/firefox/"
  wget -o wget.log --progress=dot:mega -k "${url}"

  grep -h -o "${url}\firefox-mozsymbols_.*_\(i386\|amd64\).deb\"" index.html* | cut -d'"' -f1
  rm -f index.html*
}

fetch_packages() {
  get_package_urls ${line} >> packages.txt
  sed -i -e 's/%2b/+/g' packages.txt
  sort packages.txt | wget -o wget.log --progress=dot:mega -P downloads -c -i -
  rev packages.txt | cut -d'/' -f1 | rev > package_names.txt
}

# Empties a file but retains its apparent size so that it doesn't get
# downloaded again.
function truncate_file() {
    size=$(stat -c"%s" "${1}")
    truncate --size 0 "${1}"
    truncate --size "${size}" "${1}"
}

process_packages() {
  find downloads -regex "downloads/firefox-mozsymbols_.*.deb" -type f  | while read path; do
    filename="$(basename ${path})"
    if ! grep -q -F "${filename}" SHA256SUMS; then
      mkdir -p debug symbols
      data_file=$(ar t "${path}" | grep ^data)
      ar x "${path}" && \
      tar -C "debug" -x -a -f "${data_file}"
      if [ $? -ne 0 ]; then
        printf "Failed to extract ${filename}\n"
        continue
      fi
      symbols_archive="$(find debug/ -name "firefox-*.crashreporter-symbols.zip")"
      unzip -q -d symbols "${symbols_archive}"
      rm -f data.tar* control.tar* debian-binary

      # Upload
      curl -H "auth-token: ${SYMBOLS_API_TOKEN}" --form $(basename ${symbols_archive})=@${symbols_archive} https://symbols.mozilla.org/upload/

      # Reprocess
      find symbols -mindepth 2 -maxdepth 2 -type d | while read module; do
        module_name=${module##symbols/}
        crashes=$(supersearch --num=all --modules_in_stack=${module_name})
        if [ -n "${crashes}" ]; then
         echo "${crashes}" | reprocess
        fi
      done

      rm -rf debug symbols
      echo "${filename}" >> SHA256SUMS
      truncate_file "${path}"
    fi
  done
}

purge_old_packages() {
  find downloads | while read line; do
    name=$(echo "${line}" | cut -d'/' -f2)

    if ! grep -q ${name} package_names.txt; then
      rm -vf "downloads/${name}"
    fi
  done
}

remove_temp_files() {
  rm -rf symbols packages tmp symbols*.zip packages.txt package_names.txt
}

remove_temp_files
mkdir -p downloads

fetch_packages
process_packages
purge_old_packages
remove_temp_files
