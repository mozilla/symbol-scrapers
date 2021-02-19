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

process_packages() {
  find downloads -regex "downloads/firefox-mozsymbols_.*.deb" -type f  | while read path; do
    filename="$(basename ${path})"
    if ! grep -q -F "${filename}" SHA256SUMS; then
      7z -y x "${path}" > /dev/null
      mkdir -p debug symbols
      tar -C "debug" -x -a -f data.tar
      symbols_archive="$(find debug/ -name "firefox-*.crashreporter-symbols.zip")"
      unzip -q -d symbols "${symbols_archive}"

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

rm -rf debug symbols wget.log packages.txt package_names.txt
mkdir -p downloads

fetch_packages
process_packages
purge_old_packages
