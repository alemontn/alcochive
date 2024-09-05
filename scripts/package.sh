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
  # git repos will always have the '.git' directory
  if [ ! -d .git ]
  then
    fatal "this command must be ran in the root of the git repo"
  fi

  # the script has already been ran once before
  if [ -d build ]
  then
    echo "removing build directory"
    # removing as root because some of the permissions
    # are changed to root for when it is extracted to
    # the root directory
    sudo rm -rfv build
  fi

  # capture current directory
  buildDir="$PWD"/build
  echo "build directory is $buildDir"

  mkdir -pm755 build/ar build/out
  cd build

  ln -s .. source

  cd ar
  mkdir -p usr/bin
  mkdir -p usr/lib/alcochive/compress.d

  install -m755 "$buildDir"/source/alar.sh usr/bin/alar

  for compress in "$buildDir"/source/compress.d/*
  do
    install -m755 "$compress" usr/lib/alcochive/compress.d/
  done

  echo "changing permissions"

  # when using gh runner, owner will be 'runner:docker'
  # which doesn't exist, so can't be set by `chown`
  # when extracting
  sudo chown -R root:root .

  cd "$buildDir"
}

function makeDebianPkg()
{
  echo "building debian package"
  structures

  mkdir -pm755 deb/build/DEBIAN

  # debian control file
  cp "$buildDir"/source/alcochive.control deb/build/DEBIAN/control
  # copy everything that is neede for packaging
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

  # create a compressed archive
  # the bundle only supports ZSTD compressed archives
  # so don't try to change this to anything else like
  # gzip or xz

  "$buildDir"/source/alar.sh -z zstd -c . -v \
    >"$buildDir"/out/alcochive.alzr \
    2>"$buildDir"/alar.log

  # join bundle & archive
  cat "$buildDir"/source/scripts/bundle.sh \
      "$buildDir"/out/alcochive.alzr \
        >"$buildDir"/out/alcochive.bundle

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
