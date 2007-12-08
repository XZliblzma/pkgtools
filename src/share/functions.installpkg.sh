# functions.installpkg.sh - package installation
#
# See the file `COPYRIGHT' for copyright and license information.
#
# Requires: download gnupg
#
# This is somewhat different from other functions.*.sh files since
# this alters many global variables and the order of the functions
# is critical.
#
# This is called exactly once from installpkg/upgadepkg.
# It sets a few global variables:
#   installpkg_init <number_of_packs_to_be_installed>
#
# These need to be called *in this order* exactly once
# to prepare package for installation. They also set some
# global variables:
#   installpkg_checkname
#   installpkg_download_and_gnupg
#   installpkg_filelist
#
# Now we are ready to install the package to the filesystem. This
# function can be called more than once if needed (upgradepkg does
# that). This does not touch any global variables.
#   installpkg_install
#
# After the above functions, these can be called in any order.
# They don't touch any global variables:
#   installpkg_gnuinfo
#   installpkg_db
#
# This removes unneeded files from the system left by installpkg_*
# the above installpkg_* functions:
#   installpkg_cleanup
#
# These are miscellaneous functions that can be used safely everywhere: ;-)
#   installpkg_description
#   installpkg_banner
#
# Functions in this file read these global variables:
#   VERBOSE
#   VERIFY_GPG_LOCAL
#   VERIFY_GPG_DOWNLOADED
#   DOWNLOAD_ONLY
#
# Functions in this read and set these global variables:
#   PKG_COUNT
#   PKG_COUNT_TOTAL
#   NEW_KERNEL_INSTALLED
#   EXITSTATUS
#   PKG_FULLNAME
#   PKG_TYPE
#   IS_URL

# Setting set internal field separator to <newline> is essential for
# these functions. Be sure to make everything that uses this file to
# comply with this setting!
IFS='
'

# Called once from installpkg and upgradepkg before installing/upgrading
# any packages.
installpkg_init() {
# $1 = Number of packs to be installed
# $2 = Force GPG on or off (optional). Valid values are "1", "0" and "".
  PKG_COUNT=0
  PKG_COUNT_TOTAL=$1
  EXITSTATUS=0
  NEW_KERNEL_INSTALLED=no
  if [ -n "$2" ]; then
    VERIFY_GPG_DOWNLOADED=$2
    VERIFY_GPG_LOCAL=$2
  fi
}

# Check that the package name is valid and increment PKG_COUNT.
installpkg_checkname() {
# Exit status:
#   - 0 = All OK
#   - 3 = Does not end in .tgz, .tlz, .tbz or .tar.
#   - 4 = Not a regular non-empty file.
  PKG_COUNT=$(($PKG_COUNT + 1))
  PKG_FULLNAME=$(package_fullname "$PKG")
  PKG_TYPE=$(package_type "$PKG")
  PKG_BASENAME=$(package_basename "$PKG")
  # Check that the package exists, URLs are assumed to exist
  # (we will recheck the existence of the package later).
  if is_url_package "$PKG"; then
    IS_URL=1
  else
    IS_URL=0
    if [ ! -e "$PKG" ]; then
      [ "$VERBOSE" != "quiet" ] && echo "ERROR: File not found: $PKG"
      return 4
    elif [ ! -f "$PKG" -o ! -s "$PKG" ]; then
      [ "$VERBOSE" != "quiet" ] && echo "ERROR: Not a regular non-empty file: $PKG"
      return 4
    fi
  fi
  # Reject package if it does not end in .t??:
  if [ -z "$PKG_TYPE" ]; then
    if [ "$VERBOSE" != "quiet" ]; then
      echo "ERROR: Cannot install $PKG"
      echo "because the filename does not end in .tgz, .tlz, .tbz or .tar."
    fi
    return 3
  fi
  # Warn about non-standard package names:
  [ "$VERBOSE" != "quiet" ] && ! is_valid_package_name "$PKG" \
      && echo "WARNING: Non-standard package name"
  return 0
}

# Download the package, if an URL is given. Verify GPG signature. Extract
# the list of files to a temporary file $TMP/files.$(package_fullname "$1").
installpkg_download_and_gnupg() {
# Expects VERIFY_GPG_DOWNLOADED and VERIFY_GPG_LOCAL being set.
# Sets COMPRESSED and UNCOMPRESSED and possibly NEW_KERNEL_INSTALLED=yes.
# Exit status:
#   - 0 = All OK
#   - 1 = Package corrupt
#   - 5 = wget returned an error
# If GnuPG is used, also these exit statuses are used:
#   - 20 = no signature file was found
#   - 21 = GPG signature verification failed
#   - 22 = GPG signature has been created using an unknown key,
#          or other error from gpgv.
#
  # Handle HTTP and FTP:
  if [ "$IS_URL" = "1" ]; then
    download_package "$PKG" "$VERIFY_GPG_DOWNLOADED" "$VERBOSE" || return 5
    PKG=$RETURN_VALUE  # download_package sets RETURN_VALUE
  fi

  # Verify the GPG signature:
  if [ \( "$VERIFY_GPG_DOWNLOADED" = "1" -a "$IS_URL" = "1" \) \
      -o \( "$VERIFY_GPG_LOCAL" = "1" -a "$IS_URL" = "0" \) ]; then
    # Simple signature file integrity check:
    if [ ! -f "$PKG.asc" ]; then
      if [ "$VERBOSE" != "quiet" ]; then
        echo "No signature file for $PKG_FULLNAME.$PKG_TYPE was found."
        echo "To install anyway, use --no-gpg to disable signature checking."
      fi
      return 20
    fi
    gnupg_verify_signature "$PKG"
    local GPG_EXITSTATUS=$?
    case $GPG_EXITSTATUS in
      0) # Signature OK, no action required.
        ;;
      *) # Error detected, do not install the package.
        [ "$VERBOSE" != "quiet" -a "$DOWNLOAD_ONLY" != "yes" ] \
            && echo "Refusing to install the package."
        return $((GPG_EXITSTATUS + 20))
        ;;
    esac
  fi
  return 0
}

installpkg_filelist() {
  # - Check that we have a proper tool needed to uncompress the package
  # - Get filelist and store it to $TMP/files.$PKG_FULLNAME
  # - Calculate uncompressed size of the package and set it
  #   to variable UNCOMPRESSED
  # - Check compressed size of the package and set it to variable COMPRESSED
  # Check do we have the needed uncompression software available:
  case "$PKG_TYPE" in
    tgz)   check_cmd gunzip ;;
    tlz)   check_cmd_lzma ;; # For transition to the new lzma tool
    tbz)   check_cmd bunzip2 ;;
    *)     true ;;
  esac
  if [ $? != 0 ]; then
    echo "Unable to install the package because of missing uncompression tool."
    return 6
  fi
  mknod "$TMP/fifo1.$$" p
  mknod "$TMP/fifo2.$$" p
  # WARNING: Parallel execution, be very careful if you need to edit this.
  ( uncompress_pkg "$PKG" \
    | tee "$TMP/fifo1.$$" \
    | $TAR tf - 1> "$TMP/files.$PKG_FULLNAME" 2> /dev/null
    echo $? > "$TMP/fifo2.$$" ) &
  UNCOMPRESSED=$(wc -c < "$TMP/fifo1.$$" | tr -d ' ')
  local ERRORCODE=$(cat "$TMP/fifo2.$$")
  # End of parallel code.
  rm -f "$TMP/fifo1.$$" "$TMP/fifo2.$$"
  # Maybe this check below for corrupted archives could be improved?
  if [ "$ERRORCODE" != "0" -o "$UNCOMPRESSED" = "0" \
      -o ! -s "$TMP/files.$PKG_FULLNAME" ]; then
    rm -f "$TMP/files.$PKG_FULLNAME" # Remove the filelist of a corrupted pack.
    # If the package is downloaded with wget (now or earlier), we'll remove it from cache:
    [ "$IS_URL" = "1" ] && rm -f -- "$PKG"
    [ "$VERBOSE" != "quiet" ] && echo "ERROR: Package is corrupt: $PKG"
    return 1 # Package corrupt
  fi
  # Set uncompressed and compressed sizes of the package:
  UNCOMPRESSED=$((UNCOMPRESSED / 1024))
  COMPRESSED=$(($(ls -lL "$PKG" | tr -s ' ' | cut -f 5 -d ' ') / 1024))
  return 0
}

# It is safe to run this function more than once. That is done from upgradepkg.
installpkg_install() {
  if [ ! -f "$PKG" ]; then
    echo
    echo "Possible BUG in functions.installpkg.sh:"
    echo "File does not exist: $PKG"
    echo "It is also possible that the package got removed by another process,"
    echo "which is also a bad thing(TM). Press enter."
    read foo
    exit 97
  fi
  local FILE
  # Make sure we're not installing files on top of existing symbolic links:
  (
    set -f
    for FILE in $(grep -v '/$' "$TMP/files.$PKG_FULLNAME"); do
      [ -L "$ROOT/$FILE" ] && { echo -n "$ROOT/$FILE"; echo -en '\0'; }
    done | xargs -0r rm -f
  )
  # Explode the package to the filesystem. Check for existence of $TAR and
  # fall back to tar-1.13 or even tar if needed. I'm trying to make it
  # possible to downgrade back to Slack's original pkgtools using upgradepkg.
  # NEW: In contrast to Slackware, we don't redirect all messages from
  # tar to /dev/null. It's nice to know what happened if something goes wrong.
  if type $TAR > /dev/null 2> /dev/null; then
    uncompress_pkg "$PKG" | $TAR -xlUpf - --no-overwrite-dir -C "$ROOT/" # > /dev/null 2> /dev/null
  elif type tar-1.13 > /dev/null 2> /dev/null; then
    uncompress_pkg "$PKG" | tar-1.13 -xlUpf - -C "$ROOT/" # > /dev/null 2> /dev/null
  else
    uncompress_pkg "$PKG" | tar -xUpf - -C "$ROOT/" # > /dev/null 2> /dev/null
  fi
  if [ $? != 0 ]; then
    # NEW: We don't abort installation even if tar reports an error.
    # This is to improve compatibility with Slackware pkgtools, which
    # also ignore errors. We at least show the errors and a warning. :-)
    # upgradepkg in Slackware 11.0 has a little more extra checks, but
    # it still ignores this error condition.
    echo
    echo 'WARNING: tar returned an error!'
    echo
#    installpkg_cleanup # Remove temp files since we are unable to continue.
#    echo
#    echo "FATAL ERROR: Extracting files to the filesystem failed."
#    echo "This should never happen unless you disk became full."
#    echo "Press enter to quit."
#    read foo
#    return 7
  fi
  # Show the package description:
  if [ "$VERBOSE" != "quiet" -a -z "$1" ]; then
    if [ $(installpkg_description "$ROOT/install/slack-desc" | wc -l) -gt 0 ]; then
      echo
      echo ".-----------------------------------------------------------------------------."
      installpkg_description "$ROOT/install/slack-desc" | uniq | sed '
              s/\t//g
              s/^[^: ]*:/|/
              ${
                /^| *$/d
              }
              s/$/                                                                                /
              s/^\(.\{78\}\).*$/\1|/'
      echo "'-----------------------------------------------------------------------------'"
      echo
    else
      echo "WARNING: Package has no description."
    fi
  fi
  # Run ldconfig only when needed. This is a major speed up if and only if we
  # are installing only package(s) that do not have any libs. If you are unsure
  # about the regex in grep command look at the output of "ldconfig -p".
  [ -x "$ROOT/sbin/ldconfig" ] \
      && grep -q '/lib[^/]*\.so' "$TMP/files.$PKG_FULLNAME" \
      && chroot "$ROOT/" /sbin/ldconfig
  # Execute doinst.sh:
  if [ -f "$ROOT/install/doinst.sh" ]; then
    [ "$VERBOSE" != "quiet" ] && echo "Executing install script for $PKG_FULLNAME..."
#     ( cd "$ROOT/" ; sh install/doinst.sh -install )
    # This makes doinst.sh scripts having lots of symlinks much faster
    # especially on older computers. I'm not aware of any breakage that this
    # could do in practice but still, this isn't trivially safe.  --Larhzu
    # Update: The original version wasn't bullet proof. If a symlink points
    # to itself causing "Too many levels of symbolic links" error, [ -L foo ]
    # returns true but [ -e foo ] returns false. *sigh*
    ( cd "$ROOT/"
      sed 's#^( cd \([^ ;]\+\) ; rm -rf \([^ )]\+\) )$#\[ -L \1/\2 -o -e \1/\2 \] \&\& rm -rf \1/\2#
           s#^( cd \([^ ;]\+\) ; ln -sf \([^ )]\+\) \([^ )]\+\) )$#ln -sf \2 \1/\3#' \
        install/doinst.sh | sh -s -- -install
    )
  fi
  return 0
}

installpkg_gnuinfo() {
  local FILE INFO_DIR
  # Update the GNU info directory:
  if [ -x "$ROOT/$INSTALL_INFO" ]; then
    # Instead of just updating we need to rebuild the whole info directory if:
    # - package itself contains "dir" or "dir.gz"
    # - neither "dir" or "dir.gz" exist on the filesystem
    # - both "dir" and "dir.gz" exist on the filesystem
    # On the next line you can set which directories are scanned for info files:
    for INFO_DIR in usr/info usr/share/info; do
      [ ! -d "$ROOT/$INFO_DIR" ] && continue
      if [ \( -f "$ROOT/$INFO_DIR/dir" -a -f "$ROOT/$INFO_DIR/dir.gz" \) \
          -o \( ! -f "$ROOT/$INFO_DIR/dir" -a ! -f "$ROOT/$INFO_DIR/dir.gz" \) ] \
          || grep -q "^\\(\\|\\./\\)$INFO_DIR/dir\\(\\|\\.gz\\)$" "$TMP/files.$PKG_FULLNAME"; then
        [ "$VERBOSE" != "quiet" ] && echo "Rebuilding the GNU info directory file: $ROOT/$INFO_DIR/dir"
        rm -f "$ROOT/$INFO_DIR/dir" "$ROOT/$INFO_DIR/dir.gz"
        (
          set +f
          for FILE in "$ROOT/$INFO_DIR/"*; do
            "$ROOT/$INSTALL_INFO" -- "$FILE" "$ROOT/$INFO_DIR/dir" \
                > /dev/null 2> /dev/null
          done
        )
        if [ -f "$ROOT/$INFO_DIR/dir" ]; then
          if type gzip > /dev/null 2> /dev/null; then
            # No need for 'gzip -9' because next install-info will compress
            # with default settings anyway.
            gzip "$ROOT/$INFO_DIR/dir"
            # Write a log file entry:
            log_line "Recreated GNU info directory file: /$INFO_DIR/dir.gz"
          else
            log_line "Recreated GNU info directory file: /$INFO_DIR/dir"
          fi
        fi
      else
        # Add each new file in /usr/info to the info directory. Note that info
        # files are sometimes somewhere else than /usr/info. Those info files
        # are not handled by installpkg (at least not yet, should them?).
        (
          set -f
          for FILE in $(grep "^\\(\\|\\./\\)$INFO_DIR/." "$TMP/files.$PKG_FULLNAME"); do
            "$ROOT/$INSTALL_INFO" -- "$ROOT/$FILE" "$ROOT/$INFO_DIR/dir" \
                > /dev/null 2> /dev/null
          done
        )
      fi
    done
  fi
  return 0
}

installpkg_db() {
  local DB_PACKAGE="$ADM_DIR/packages/$PKG_FULLNAME"
  local DB_SCRIPT="$ADM_DIR/scripts/$PKG_FULLNAME"
  # Write the package file database entry:
  [ -e "$DB_PACKAGE" ] && rm -f "$DB_PACKAGE"
  echo "PACKAGE NAME:     $PKG_FULLNAME" > "$DB_PACKAGE"
  printf "COMPRESSED PACKAGE SIZE:   %7d K\n" "$COMPRESSED" >> "$DB_PACKAGE"
  printf "UNCOMPRESSED PACKAGE SIZE: %7d K\n" "$UNCOMPRESSED" >> "$DB_PACKAGE"
  echo "PACKAGE LOCATION: $(absolute_path "$PKG")" >> "$DB_PACKAGE"
  echo "PACKAGE DESCRIPTION:" >> "$DB_PACKAGE"
  installpkg_description "$ROOT/install/slack-desc" >> "$DB_PACKAGE" 2> /dev/null
  echo "FILE LIST:" >> "$DB_PACKAGE"
  # If the pack doesn't conform to Slackware(R) specifications,
  # this will fix it on the fly:
  echo './' >> "$DB_PACKAGE"
  sed '\#^\./$#d; s#^\./##' "$TMP/files.$PKG_FULLNAME" >> "$DB_PACKAGE"
  # Copy doinst.sh to package database:
  if [ -f "$ROOT/install/doinst.sh" ]; then
    cp "$ROOT/install/doinst.sh" "$DB_SCRIPT"
    chmod 0755 "$DB_SCRIPT"
  fi
  return 0
}

installpkg_cleanup() {
  [ "$IS_URL" = "1" -a "$KEEP_DOWNLOADED" = "0" ] \
      && rm -f "$PKG" "$PKG.asc"
  # $ROOT/install is a reserved location for the package system.
  [ -d "$ROOT/install" ] && rm -rf "$ROOT/install"
  # Other temporary files:
  rm -f "$TMP/files.$PKG_FULLNAME"
  return 0
}

installpkg_description() {
  [ ! -f "$1" ] && return 0
  grep "^$PKG_BASENAME:" "$1" 2> /dev/null
  [ "$PKG_FULLNAME" != "$PKG_BASENAME" ] \
      && grep "^$PKG_FULLNAME:" "$1" 2> /dev/null
}

installpkg_banner() {
  # Assuming a terminal with at least 80 columns.
  local COUNTER="$PKG_COUNT/$PKG_COUNT_TOTAL"
  local PADDING_LEFT=
  local PADDING_RIGHT='------------------------------------------------------------------------'
  local MESSAGE="$1                                                                        "
  while [ ${#PADDING_LEFT} != ${#COUNTER} ]; do
    PADDING_LEFT=${PADDING_LEFT}-
    PADDING_RIGHT=${PADDING_RIGHT%'-'}
  done
  while [ ${#MESSAGE} != ${#PADDING_RIGHT} ]; do
    MESSAGE=${MESSAGE%?}
  done
  echo
  echo ".-${PADDING_LEFT}-.-${PADDING_RIGHT}-."
  echo "| ${COUNTER} | ${MESSAGE} |"
  echo "'-${PADDING_LEFT}-'-${PADDING_RIGHT}-'"
}

# End of functions.installpkg.sh

