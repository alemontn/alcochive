#!/usr/bin/env bash

# source common code for scripts
. "./scripts/common.sh.in"
. "./package.conf"

gitRequired

function structures()
{
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
  install -m755 "$buildDir"/source/scripts/common.sh.in usr/lib/alcochive/common.sh

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
  cp "$buildDir"/source/pkg/alcochive.control deb/build/DEBIAN/control
  # copy everything that is neede for packaging
  cp -a "$buildDir"/ar/* deb/build

  cd deb/build
  dpkg-deb --root-owner-group --build "$PWD" &> "$buildDir"/deb.log

  cd ..
  mv *.deb "$buildDir"/out/
}

function makeFedoraPkg()
{
  echo "building fedora package"
  structures

  mkdir -pm755 rpm/rpmbuild
  mkdir rpm/rpmbuild/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

  cp "$buildDir"/source/pkg/alcochive.spec rpm/rpmbuild/SPECS/

  cd "$buildDir"/rpm

  mkdir alcochive-$version
  cp -a "$buildDir"/ar/* alcochive-$version

  tar -H "ustar" -c alcochive-$version |
    gzip -1 >rpmbuild/SOURCES/alcochive-$version.tgz

  cd rpmbuild
  HOME="$buildDir"/rpm rpmbuild -bb SPECS/* &>"$buildDir"/rpm.log
  mv ./RPMS/noarch/*.rpm "$buildDir"/out/
}

function makeArchPkg()
{
  echo "building arch package"
  structures

  mkdir -m755 arch

  cd "$buildDir"/ar
  tar -H "ustar" -c . | gzip -1 >"$buildDir"/arch/alcochive-$version.tar.gz

  cd "$buildDir"/arch

  cp "$buildDir"/source/pkg/alcochive.pkgbuild PKGBUILD
  makepkg -s

  mv *.pkg.tar.zst "$buildDir"/out/alcochive.pkg.tar.zst
}

function makeBundle()
{
  function _rd()
  {
    echo "$@" >>"$buildDir"/out/alcochive.bundle
  }

  function _addFileLength()
  {
    shLength+=$(wc -l "$buildDir"/source/"$1" | cut -d' ' -f1)
  }

  echo "building bundle"
  structures

  cd "$buildDir"/ar

  # create a compressed archive
  # the bundle only supports ZSTD compressed archives
  # so don't try to change this to anything else like
  # gzip or xz

  sudo "$buildDir"/source/alar.sh -z zstd -c . -v \
    >"$buildDir"/out/alcochive.alzr \
    2>"$buildDir"/alar.log

  declare -i shLength=0

  _addFileLength "scripts/common.sh.in"
  _addFileLength "scripts/bundle.sh.in"
  _addFileLength "package.conf"

  shLength+=11

  # shebang to make sure we are running from bash
  _rd "#!/usr/bin/env bash"
  _rd
  _rd "shLength=$shLength"
  _rd "rmList=(${fileList[@]})"
  _rd
  _rd 'function spec()'
  _rd '{'
  _rd '  cat <<EOL'
  _rd "$(<"$buildDir"/source/package.conf)"
  _rd 'EOL'
  _rd '}'

  # join bundle & archive
  cat "$buildDir"/source/scripts/common.sh.in \
      "$buildDir"/source/scripts/bundle.sh.in \
      "$buildDir"/out/alcochive.alzr \
        >>"$buildDir"/out/alcochive.bundle

  chmod +x "$buildDir"/out/alcochive.bundle
}

case "${1,,}" in
  "deb")
    fileRequired "./pkg/alcochive.control"
    makeDebianPkg
    ;;
  "rpm")
    fileRequired "./pkg/alcochive.spec"
    makeFedoraPkg
    ;;
  "arch")
    fileRequired "./pkg/alcochive.pkgbuild"
    makeArchPkg
    ;;
  "bundle")
    fileRequired "./scripts/bundle.sh.in"
    makeBundle
    ;;
esac
