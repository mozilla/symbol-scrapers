#!/bin/bash
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

function purge {
  package_name="${1}"
  package_url="${2}"
  find tarballs -name "${package_name}*.tar.xz" | while read path; do
    package=$(basename "${path}")
    if wget -q --method HEAD "${package_url}${package}" ; then
      :
    else
      rm -vf "${path}"
    fi
  done
}

rm -rvf symbols* tmp
mkdir -p symbols
mkdir -p tarballs
mkdir -p tmp

cd tarballs
packages="
https://www.archlinux.org/packages/core/x86_64/glib2/download/
https://www.archlinux.org/packages/core/x86_64/glibc/download/
https://www.archlinux.org/packages/extra/x86_64/dconf/download/
https://www.archlinux.org/packages/extra/x86_64/gtk3/download/
https://www.archlinux.org/packages/extra/x86_64/libpulse/download/
https://www.archlinux.org/packages/extra/x86_64/libstdc++5/download/
https://www.archlinux.org/packages/extra/x86_64/libx11/download/
https://www.archlinux.org/packages/extra/x86_64/libxcb/download/
https://www.archlinux.org/packages/extra/x86_64/libxext/download/
https://www.archlinux.org/packages/extra/x86_64/mesa/download/
https://www.archlinux.org/packages/extra/x86_64/wayland/download/
"
wget -c --content-disposition ${packages}
tarballs=$(ls)
cd ..

for i in ${tarballs}; do
  full_hash=$(sha256sum "tarballs/${i}")
  hash=$(echo "${full_hash}" | cut -b 1-64)
  if ! grep -q ${hash} SHA256SUMS; then
    tar -C tmp -x -a -v -f "tarballs/${i}"
    echo "${full_hash}" >> SHA256SUMS
  fi
done

find tmp -name "*.so*" -type f | while read library; do
  if file "${library}" | grep -q "ELF 64-bit LSB shared object" ; then
    library_basename=$(basename "${library}")
    debugid=$("${DUMP_SYMS}" "${library}" | head -n 1 | cut -b 21-53)
    mkdir -p "symbols/${library_basename}/${debugid}"
    "${DUMP_SYMS}" "${library}" > "symbols/${library_basename}/${debugid}/${library_basename}.sym"
    cp -v "${library}" "symbols/${library_basename}/${debugid}/${library_basename}"
  fi
done

cd symbols
zip_count=1
total_size=0
find . -mindepth 2 -type d | while read path; do
  size=$(du -s -b "${path}" | cut -f1)
  zip -r "../symbols${zip_count}.zip" "${path##./}"
  total_size=$((total_size + size))
  if [[ ${total_size} -gt 500000000 ]]; then
    zip_count=$((zip_count + 1))
    total_size=0
  fi
done
cd ..

find . -name "*.zip" | while read myfile; do
  printf "Uploading ${myfile}\n"
  while : ; do
    res=$(curl -H "auth-token: ${SYMBOLS_API_TOKEN}" --form "${myfile}=@${myfile}" https://symbols.mozilla.org/upload/)
    if [ -n "${res}" ]; then
      echo "${res}"
      break
    fi
  done
done

find symbols -mindepth 2 -maxdepth 2 -type d | while read module; do
  crashes=$(supersearch --num=all --modules_in_stack=${module##symbols/})
  if [ -n "${crashes}" ]; then
   echo "${crashes}" | reprocess
  fi
done

purge "glib2-" "http://mirror.f4st.host/archlinux/core/os/x86_64/"
purge "glibc-" "http://mirror.f4st.host/archlinux/core/os/x86_64/"
purge "dconf-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "gtk3-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libpulse-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libstdc++5-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libx11-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libxcb-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "libxext-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "mesa-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
purge "wayland-" "http://mirror.f4st.host/archlinux/extra/os/x86_64/"
