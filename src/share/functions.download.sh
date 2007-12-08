# functions.download.sh - wrappers for wget
#
# See the file `COPYRIGHT' for copyright and license information.
#
# download <URL> <target_filename>
# download_package <URL> <gpg:1|0> <verbosity> ; sets RETURN_VALUE
#

download() {
  (
    # WGET_FLAGS will not be splitted correctly without this:
    unset IFS
    # trap is ignored by busybox but I hope we can live with it. Without trap
    # Ctrl-c would break execution of the whole script instead of only wget.
    trap "rm -f \"$2\"; exit 1" INT
    # Here's a race condition between rm and wget. However, it's not worth
    # fixing. You should never ever point $PACKAGE_CACHE_DIR to a world
    # writable directory because then anyone could exploit it to install
    # their own packages and that would be *much* bigger problem than
    # some symlink exploits. The same applies, of course, to group writable
    # directories; allow only those who already have root access to write
    # to the directory $PACKAGE_CACHE_DIR.
    rm -f "$2" > /dev/null 2> /dev/null
    $WGET $WGET_FLAGS -O "$2" -- "$1"
    WGET_EXITSTATUS=$?
    [ $WGET_EXITSTATUS != 0 ] && rm -f "$2"
    return $WGET_EXITSTATUS
  )
}

download_package() {
# $1 = URL
# $2 = Use GPG: "0" or "1"
# $3 = Verbosity: "quiet" or "normal"
  # Set some basic variables:
  local FILE=
  local BASENAME=$(basename "$1")
  # Look from cache first:
  if [ -f "$PACKAGE_CACHE_DIR/$BASENAME" \
      -a -s "$PACKAGE_CACHE_DIR/$BASENAME" ]; then
    FILE="$PACKAGE_CACHE_DIR/$BASENAME"
  fi
  if [ "$2" = "1" ]; then
    # If the package was found from cache, we can accept also a cached
    # signature. Otherwise the signature should be redownloaded even
    # if it exists in the cache.
    if [ -n "$FILE" -a -f "$FILE.asc" -a -s "$FILE.asc" ]; then
      [ "$3" != "quiet" ] && echo "GPG signature file found in cache: $FILE.asc"
    else
      [ "$3" != "quiet" ] && echo "Downloading GPG signature: $BASENAME.asc"
      download "$1.asc" "$PACKAGE_CACHE_DIR/$BASENAME.asc"
      if [ $? != 0 ]; then
        [ "$3" != "quiet" ] && echo "Downloading GPG signature failed: $BASENAME.asc"
        return 2
      fi
    fi
  fi
  if [ -n "$FILE" ]; then
    [ "$3" != "quiet" ] && echo "Package found in cache: $FILE"
    RETURN_VALUE=$FILE
    return 0
  fi
  # No package found in cache.
  [ "$3" != "quiet" ] && echo "Downloading the package: $BASENAME"
  download "$1" "$PACKAGE_CACHE_DIR/$BASENAME"
  if [ $? != 0 ]; then
    [ "$3" != "quiet" ] && echo "Downloading the package $BASENAME failed."
    return 1
  fi
  RETURN_VALUE="$PACKAGE_CACHE_DIR/$BASENAME"
  return 0
}

# End of functions.download.sh

