#!/bin/sh

set -e
umask 0022

if [ ! -f utils/create_pkgtools_tar.sh ]; then
	echo 'Please run the script in the top-level directory.'
	exit 1
fi

. ./utils/version.sh

TMP=$(mktemp -d)
trap "rm -rf \"$TMP\"" 0

chmod 0755 "$TMP"
mkdir -p "$TMP"/{bin,etc/pkgtools,install,sbin,var/log/setup/tmp} \
	"$TMP/usr"/{bin,doc/pkgtools-tukaani_$VERSION,lib,man/man{1,8},sbin,share/pkgtools}
chmod 0700 "$TMP/var/log/setup/tmp"

cd src
cp -v --preserve=timestamps doc/* "$TMP/usr/doc/pkgtools-tukaani_$VERSION"
cp -v --preserve=timestamps man/man1/* "$TMP/usr/man/man1"
cp -v --preserve=timestamps man/man8/* "$TMP/usr/man/man8"
gzip -9r "$TMP/usr/man"
cp -v --preserve=timestamps share/* "$TMP/usr/share/pkgtools"
cp -v --preserve=timestamps bin/* "$TMP/usr/bin"
cp -v --preserve=timestamps sbin/* "$TMP/usr/sbin"
cp -v --preserve=timestamps etc/* "$TMP/etc/pkgtools"
cp -v --preserve=timestamps var/* "$TMP/var/log/setup"
cp -v --preserve=timestamps install/* "$TMP/install"
sed -i "s/@VERSION@/$VERSION/g" "$TMP/usr/sbin/pkgtool"
cd ..

rm -f _pkgtools.tar.gz
tar cf - -C "$TMP" --owner=root --group=root . | gzip -9 > _pkgtools.tar.gz
