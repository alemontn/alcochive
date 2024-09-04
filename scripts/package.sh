#!/usr/bin/env bash

set -o "errexit"

function fatal()
{
  local red=$(echo -ne '\e[1;31m') \
        none=$(echo -ne '\e[0m')

  echo $red"error (fatal):"$none "$@"
  exit 1
}

function structures()
{
  if [ ! -d .git ]
  then
    fatal "this command must be ran in the root of the git repo"
  fi

  if [ -d build ]
  then
    echo "removing build directory"
    rm -rfv build
  fi

  buildDir="$PWD"/build
  echo "build directory is $buildDir"

  mkdir -pm755 build/ar build/out
  cd build

  ln -s .. source

  cd ar
  mkdir -p usr/bin

  install -m755 "$buildDir"/source/alar.sh usr/bin/alar

  cd "$buildDir"
}

function makeDebianPkg()
{
  echo "building debian package"
  structures

  mkdir -pm755 deb/build/DEBIAN

  cp "$buildDir"/source/alcochive.control deb/build/DEBIAN/control
  cp -a "$buildDir"/ar/* deb/build

  cd deb/build
  dpkg-deb --root-owner-group --build "$PWD" &> "$buildDir"/deb.log

  cd ..
  mv *.deb "$buildDir"/out
}

function makeBundle()
{
  echo "building bundle"
  structures

  cd "$buildDir"/ar

  cat "$buildDir"/source/scripts/bundle.sh >"$buildDir"/out/alcochive.bundle

  # stupidly long command for creating archive
  "$buildDir"/source/alar.sh -c $(find -type f -print0 | xargs -0 ls -1 | sed "s|^./||") |
    gzip -1 >>"$buildDir"/out/alcochive.bundle

  chmod +x "$buildDir"/out/alcochive.bundle
}

case "${1,,}" in
  "deb")
    makeDebianPkg
    ;;
  "rpm")
    makeFedoraPkg
    ;;
  "bundle")
    makeBundle
    ;;
esac
