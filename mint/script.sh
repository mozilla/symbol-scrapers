#!/bin/sh

. $(dirname $0)/../common.sh

URL="http://packages.linuxmint.com/pool"

get_package_urls() {
  url="${URL}/upstream/f/firefox/"
  wget -o wget.log --progress=dot:mega -k "${url}"

  find . -name "index.html*" -exec grep -o "${url}\firefox-mozsymbols_.*_\(i386\|amd64\).deb\"" {} \; | cut -d'"' -f1
  find . -name "index.html*" -exec rm -f {} \;
}

fetch_packages() {
  get_package_urls ${line} >> packages.txt
  sed -i -e 's/%2b/+/g' packages.txt
  sort packages.txt | wget -o wget.log --progress=dot:mega -P downloads -c -i -
  rev packages.txt | cut -d'/' -f1 | rev > package_names.txt
}

function add_package_to_list() {
  local package_size=$(stat -c"%s" "${1}")
  local package_filename=$(basename "${1}")
  printf "${package_filename},${package_size}\n" >> SHA256SUMS
  truncate --size 0 "${1}"
  truncate --size "${package_size}" "${1}"
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
      add_package_to_list "${filename}"
    fi
  done
}

function remove_temp_files() {
  rm -rf symbols packages tmp symbols*.zip packages.txt package_names.txt
}

function generate_fake_packages() {
  cat SHA256SUMS | while read line; do
    local package_name=$(echo ${line} | cut -d',' -f1)
    local package_size=$(echo ${line} | cut -d',' -f2)
    truncate --size "${package_size}" "downloads/${package_name}"
  done
}

remove_temp_files
mkdir -p downloads
generate_fake_packages

fetch_packages
process_packages
remove_temp_files
