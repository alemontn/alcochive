Name: alcochive
License: GPL-3.0
Version: 0.0.2
Release: 1%{?dist}
Summary: an archiver written in bash
BuildArch: noarch
Source0: %{name}-%{version}.tgz

Requires: bash

%description
%{summary}

%prep
%setup -q

%install
mkdir -p $RPM_BUILD_ROOT/usr/bin
mkdir -p $RPM_BUILD_ROOT/usr/lib/alcochive/compress.d
cp usr/bin/alar $RPM_BUILD_ROOT/usr/bin/alar
cp -a usr/lib/alcochive/compress.d/* $RPM_BUILD_ROOT/usr/lib/alcochive/compress.d/

%clean
rm -rf $RPM_BUILD_ROOT

%files
/usr/bin/alar
/usr/lib/alcochive/compress.d/brotli
/usr/lib/alcochive/compress.d/gzip
/usr/lib/alcochive/compress.d/lz4
/usr/lib/alcochive/compress.d/xz
/usr/lib/alcochive/compress.d/zstd
