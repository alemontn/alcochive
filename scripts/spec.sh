#!/usr/bin/env bash

. "./scripts/common.sh.in"

gitRequired
fileRequired "./package.conf" && . "./package.conf"

function makeSpec()
{
  function _deb()
  {
    debianDepends="$(
      for dependency in "${depends[@]}"
      do
        echo -n "$dependency, "
      done
    )"
    debianDepends="${debianDepends%, }"

    echo "Package: $name"
    echo "License: $licenseSpdx"
    echo "Version: $fullVersion"
    echo "Section: utils"
    echo "Priority: optional"
    echo "Architecture: all"
    echo "Maintainer: $maintainer"
    echo "Description: $description"
    echo "Depends: $debianDepends"

    echo "generated debian control" >&2
  }

  function _rpm()
  {
    echo "Name: $name"
    echo "License: $licenseSpdx"
    echo "Version: $version"
    echo "Release: 1%{?dist}"
    echo "Summary: $description"
    echo "BuildArch: noarch"
    echo "Source0: %{name}-%{version}.tgz"
    echo
    echo "Requires: ${depends[@]}"
    echo
    echo "%description"
    echo "%{summary}"
    echo
    echo "%prep"
    echo "%setup -q"
    echo
    echo "%install"
    echo "$(
      for dir in "${dirList[@]}"
      do
        echo "mkdir -p \$RPM_BUILD_ROOT/$dir"
      done
      for file in "${fileList[@]}"
      do
        echo "cp -a $file \$RPM_BUILD_ROOT/$file"
      done
    )"
    echo
    echo "%clean"
    echo "rm -rf \$RPM_BUILD_ROOT"
    echo
    echo "%files"
    echo "$(
      for file in "${fileList[@]}"
      do
        echo "/$file"
      done
    )"

    echo "generated fedora spec" >&2
  }

  function _pkgbuild()
  {
    echo "# Maintainer: $maintainer"
    echo "pkgname=$name"
    echo "pkgver=$version"
    echo "pkgrel=1"
    echo "pkgdesc=\"$description\""
    echo "arch=(any)"
    echo "url=\"$repo\""
    echo "license=('$licenseSpdx')"
    echo "depends=(${depends[@]})"
    echo "source=(\$pkgname-\$pkgver.tar.gz)"
    echo "noextract=()"
    echo "sha256sums=('SKIP')"
    echo
    echo "package() {"
    echo "  cd \"\$srcdir\""
    echo "  cp -a usr \"\$pkgdir\""
    echo "}"

    echo "generated arch pkgbuild" >&2
  }

  case "$1" in
    "deb")
      _deb >./pkg/alcochive.control
      ;;
    "rpm")
      _rpm >./pkg/alcochive.spec
      ;;
    "arch")
      _pkgbuild >./pkg/alcochive.pkgbuild
      ;;
    "")
      _deb >./pkg/alcochive.control
      _rpm >./pkg/alcochive.spec
      _pkgbuild >./pkg/alcochive.pkgbuild
      ;;
    *)
      fatal "$1" "unknown target - use one of ['deb', 'rpm', 'arch'] or none to generate all"
      ;;
  esac
}

mkdir -pm755 ./pkg/
makeSpec "$1"
