# functions.explode.sh
#
# See the file `COPYRIGHT' for copyright and license information.
#
# explode <path/to/packagefile.ext>
# explode_deb <path/to/filename.deb>
# explode_rpm <path/to/filename.rpm>
#

explode() {
  case "$1" in
    *.rpm)  explode_rpm "$1" ;;
    *.deb)  explode_deb "$1" ;;
    *)      uncompress_pkg "$1" | $TAR xvf - ;;
  esac
  return $?
}

explode_deb() {
  local files=$(ar t "$1" 2> /dev/null)
  if [ $? != 0 -o -z "$files" ]; then
    echo "Not a valid Debian binary package."
    return 1
  fi
  # We use "tar" instead of $TAR (tar-1.13).
  case "$files" in
    *data.tar.gz*)  ar p "$1" data.tar.gz | gunzip | tar xvf - ;;
    *data.tar.bz2*) ar p "$1" data.tar.gz | bunzip2 | tar xvf - ;;
    *)              echo "Unrecognized deb file: $1"; return 1 ;;
  esac
  return $?
}

# The code in this function was originally written by Jeff Johnson.
# Slightly modified for use in pkgtools.
explode_rpm() {
  local pkg o sigsize gz
  pkg=$1
  o=104
  set -- $(od -j $o -N 8 -t u1 -- "$pkg")
  sigsize=$((8 + 16 *
      (256 * (256 * (256 * $2 + $3) + $4) + $5) +
      (256 * (256 * (256 * $6 + $7) + $8) + $9)))
  o=$((o + sigsize + (8 - (sigsize % 8)) % 8 + 8))
  set -- $(od -j $o -N 8 -t u1 -- "$pkg")
  o=$((o + 8 + 16 *
      (256 * (256 * (256 * $2 + $3) + $4) + $5) +
      (256 * (256 * (256 * $6 + $7) + $8) + $9)))
  comp=$(dd if="$pkg" ibs=$o skip=1 count=1 2>/dev/null \
      | dd bs=3 count=1 2> /dev/null)
  gz="$(echo -en '\037\0213')"
  case "$comp" in
    BZh)      dd if="$pkg" ibs=$o skip=1 2>/dev/null | bunzip2 | cpio -ivdm ;;
    "$gz"*)   dd if="$pkg" ibs=$o skip=1 2>/dev/null | gunzip | cpio -ivdm ;;
    *)        echo "Unrecognized rpm file: $pkg"; return 1 ;;
  esac
  [ $? != 0 ] && return 1
  # The directories that are not listed in the RPM file are always created
  # "chmod 0700" by cpio. We will reset those directories to "chmod 0755".
  # Unfortunately we cannot detect without extra help from cpio if the
  # package had some directories that shouldn't be world readable.
  find . -type d -perm 700 -exec chmod 755 {} \;
  return 0
}

# End of functions.explode.sh

