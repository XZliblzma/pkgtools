# functions.common.sh - common functions used by pkgtools scripts
#
# See the file `COPYRIGHT' for copyright and license information.
#

# Take advantage of bash if available:
case "$-" in
  (*B*)
    # Setting pipefail improves error handling. It is not supported
    # by ash shell of BusyBox (interrupts the whole script):
    set -o pipefail > /dev/null 2> /dev/null
    ;;
esac

# All scripts in pkgtools expect umask 0022 but may need the original umask too:
OLD_UMASK=$(umask)
umask 0022

# This is to keep 'sort' fast:
export LC_ALL=C

# Make sure that PATH is sane:
export PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin

# tar-1.13 -- I think it is more comfortable to have tar-1.13 included
# in the package of pkgtools instead of tar package, because Tukaani has
# an extra patch for tar-1.13 which adds --no-overwrite-dir option.
TAR=tar-1.13-pkgtools

# Wget command:
WGET=wget

# Path to install-info command (WITHOUT '/' prefix):
INSTALL_INFO=usr/bin/install-info

# ash does not have $UID set by default:
[ -z "$UID" ] && UID=$(id -u)

# We do not want these to be set with environment variables:
unset POSIXLY_CORRECT MODE PKGTOOLS_LZMA

# GPG home:
export GNUPGHOME=/root/.gnupg

# Characters that are allowed in package filenames and directories in
# a repository. Do not edit unless you know what you are doing! The choice of
# these characters affect not only overall functionality but security.
ALLOWED_FILECHARS='[a-zA-Z0-9.!@_+-]'
ALLOWED_DIRCHARS='[]:[,/a-zA-Z0-9.!@_+-]'
#            These ]:[ are for Linuxpackages compatibility. :-(

# Check that directory specified with --root exists. If not, show error and exit.
check_root_dir_exists() {
  [ -d "$1" ] && return 0
  echo "The specified root directory does not exist: $1"
  exit 99
}

# Check that we are running with root priviledges. If not, quit.
check_is_run_by_root() {
  [ "$UID" = "0" ] && return 0
  echo "You must be root to use this command."
  exit 10
}

# Error message used by installpkg, removepkg and upgradepkg:
exit_no_packages_specified() {
  echo "Error: No packages specified on the command line."
  exit 99
}

# Error message used by many scripts, hopefully never needed:
exit_getopt_error() {
  echo "Fatal error parsing command line options."; exit 97
}

# '/path/to/foo-bar-0.12-i486-1.tgz' => 'foo-bar-0.12-i486-1'
package_fullname() {
  package_strip_extension "${1##*/}"
}

# Returns the basename of the package. E.g. '/path/to/foo-bar-0.12-i486-1.tgz' => 'foo-bar'
package_basename() {
  echo "$1" | sed '
      s,^.*/,,
      s,\.\(tgz\|tlz\|tbz\|tar\)$,,;s,-[^-]\+-[^-]\+-[^-]\+$,,'
}

# '/path/to/foo-bar-0.12-i486-1.tgz' => '0.12'
package_version() {
  echo "$1" | sed -n '
      s,^.*/,,
      s,^.*-\([^-]\+\)-[^-]\+-[^-]\+\.\(tgz\|tlz\|tbz\|tar\)$,\1,p'
}

# '/path/to/foo-bar-0.12-i486-1.tgz' => 'i486'
package_arch() {
  echo "$1" | sed -n '
      s,^.*/,,
      s,^.*-[^-]\+-\([^-]\+\)-[^-]\+\.\(tgz\|tlz\|tbz\|tar\)$,\1,p'
}

# '/path/to/foo-bar-0.12-i486-1.tgz' => '1'
package_buildversion() {
  echo "$1" | sed -n '
      s,^.*/,,
      s,^.*-[^-]\+-[^-]\+-\([^-]\+\)\.\(tgz\|tlz\|tbz\|tar\)$,\1,p'
}

# Returns package type which can be "tgz", "tlz", "tbz", "tar" or "".
# Empty means invalid package name/type.
package_type() {
  case "$1" in
    *.tgz)  echo tgz ;;
    *.tlz)  echo tlz ;;
    *.tbz)  echo tbz ;;
    *.tar)  echo tar ;;
    *)      return 1 ;;
  esac
  return 0
}

# '/path/to/foo-bar-0.12-i486-1.tgz' => '/path/to/foo-bar-0.12-i486-1'
package_strip_extension() {
  case "$1" in
    *.tgz)  echo "${1%.tgz}" ;;
    *.tlz)  echo "${1%.tlz}" ;;
    *.tbz)  echo "${1%.tbz}" ;;
    *.tar)  echo "${1%.tar}" ;;
    *)      echo "$1"; return 1 ;;
  esac
  return 0
}

# Returns true (zero) if the argument is an URL to a package file:
is_url_package() {
  case "$1" in
    # If it begins with http:// or ftp:// and...
    "http://"*|"ftp://"*)
      case "$1" in
        # ...ends in .tgz, .tlz, .tbz or .tar...
        *.tgz|*.tlz|*.tbz|*.tar)
          # ...return true:
          return 0
          ;;
      esac
      ;;
  esac
  # Not a valid URL to a package file. Return false:
  return 1
}

# Returns true (zero) if the given package name conforms to Slackware
# specifications.
is_valid_package_name() {
  [ -n "$(echo "$1" | sed -n \
      's,^.*/,,; s,^[^-].*-[^-]\+-[^-]\+-[^-]\+\.\(tgz\|tlz\|tbz\|tar\)$,&,p')" -a \
      -n "$(echo "$1" | sed -n "s,^.*/,,; /^$ALLOWED_FILECHARS\+$/p")"  ]
}

# Extracts symlinks from doinst.sh style script. Reads stdin and outputs to stdout.
extract_links() {
  sed -n "
      # Original Slackware style symlinks:
      s,^( *cd \([^ ;]\+\) *; *rm -rf \([^ )]\+\) *) *$,\1/\2,p
      # New style quoted symlinks:
      /^rm -rf -- '.*' #Symlink#$/{
        # Remove quotes:
        s,^rm -rf -- '\(.*\)' #Symlink#$,\1,
        # Replace quoted quotes with quotes: :-)
        s,'\\\\'',',g
        p
      }"
}

# Extracts the package filenames from PACKAGES.TXT:
packagestxt2filelist() {
# $1 = PACKAGES.TXT or equivalent file.
  sed -n '/^PACKAGE NAME: /{
            # LOCATION is not necessarily immediatelly after NAME:
            N;N;N
            s/^PACKAGE NAME: *\([^ ]\+\) *\(\nPACKAGE .*\)\{0,1\}\nPACKAGE LOCATION: *\([^ ]\+\) *\(\n.*$\|$\)/\3\/\1/p
          }
      ' "$1" | sed -n "
          /$ALLOWED_DIRCHARS\+\/$ALLOWED_FILECHARS\+/"'{
            s/^\.\/\([^ ]*-[^-/ ]*-[^-/ ]*-[^-/ ]*\)\.\(tgz\|tlz\|tbz\|tar\)$/\1.\2/p
          }
      ' | sort -u
}

# Check if a command is available:
check_cmd() {
  type "$1" > /dev/null 2> /dev/null && return 0
  echo "ERROR: Command \`$1' was not found from your system."
  return 1
}

# Check the type of lzma executable. This is for transition from
# SDK's LZMA_Alone to Ville Koskinen's gzip-like user interface.
check_cmd_lzma() {
  lzma --help > /dev/null 2> /dev/null
  case $? in
    0)    PKGTOOLS_LZMA=new; return 0 ;; # FIXME? Assumes that unlzma exists.
    1)    PKGTOOLS_LZMA=old; return 0 ;;
    *)    PKGTOOLS_LZMA=none; return 1 ;;
  esac
}

# Uncompress a file to stdout:
uncompress_pkg() {
  case "$1" in
    *.tlz|*.lzma)
      # Reset PKGTOOLS_LZMA if we are installing/upgrading
      # the lzma package:
      case "$1" in (lzma-*) PKGTOOLS_LZMA= ;; esac
      # Check which lzma command we are using:
      [ -z "$PKGTOOLS_LZMA" ] && check_cmd_lzma
      case "$PKGTOOLS_LZMA" in
                # -d is only temporarily here
        new)    unlzma -dc "$1" 2> /dev/null ;;
        old)    lzma d -si -so < "$1" 2> /dev/null ;;
        *)      echo 'BUG in uncompress_pkg!' 1>&2 ;;
      esac
      ;;
    *.tbz|*.bz2)
      # Use bunzip2 instead of bzip2 for BusyBox compatibility:
      bunzip2 -c "$1" 2> /dev/null
      ;;
    *.tar)
      cat "$1" 2> /dev/null
      ;;
    *)
      # For explodepkg compatibility we default to tgz.
      # Do no add -f as it does not work with busybox.
      gunzip -c "$1" 2> /dev/null
      ;;
  esac
}

# Compress a file from stdin to stdout:
compress_pkg() {
  case "$1" in
    tgz)
      gzip -9
      ;;
    tlz)
      [ -z "$PKGTOOLS_LZMA" ] && check_cmd_lzma
      case "$PKGTOOLS_LZMA" in
        new)    lzma -c $LZMA_FLAGS 2> /dev/null ;;
        old)    lzma e -a1 -si -so 2> /dev/null ;;
        *)      echo 'BUG in compress_pkg!' 1>&2 ;;
      esac
      ;;
    tbz)
      bzip2 -9
      ;;
    tar)
      cat
      ;;
  esac
}

# Print the absolute path to a file/directory:
absolute_path() {
  local dir=$(dirname "$1")
  [ "x$dir" = "x-" ] && dir="./-"
  dir=$(cd -- "$dir" 2> /dev/null && pwd)
  [ -z "$dir" ] && return 1
  echo "$dir/$(basename "$1")"
  return 0
}

# Reads config file, initalizes some commonly used variables and creates
# package database directories and files if they do not already exist.
# Note: This function must called *after* the ROOT is set!
initialize_variables_and_package_database() {
  PACKAGE_CACHE_DIR=/var/cache/packages
  KEEP_DOWNLOADED=1
  WGET_FLAGS="--passive-ftp"
  BLACKLIST_FILE=/etc/pkgtools/blacklist
  [ -f /etc/pkgtools/config ] && . /etc/pkgtools/config
  [ ! -f "$BLACKLIST_FILE" ] && BLACKLIST_FILE=/dev/null
  ADM_DIR=$ROOT/var/log
  TMP=$ADM_DIR/setup/tmp
  REPO_DIR=$ADM_DIR/setup/repositories
  [ "$ROOT" != "" ] && export ROOT
  for I in  "$ADM_DIR/packages" \
            "$ADM_DIR/scripts" \
            "$ADM_DIR/removed_packages" \
            "$ADM_DIR/removed_scripts" \
            "$REPO_DIR" \
            "$PACKAGE_CACHE_DIR"
    do
    if [ ! -d "$I" ]; then
      rm -rf "$I"
      mkdir -m 0755 -p "$I"
    fi
  done
  # $TMP has different default permissions:
  if [ ! -d "$TMP" ]; then
    rm -rf "$TMP"
    mkdir -m 0700 -p "$TMP"
  fi
}

# Load functions from /usr/share/pkgtools/functions.$1.sh.
include() {
  local function_dir=/usr/share/pkgtools
  if [ ! -f "$function_dir/functions.$1.sh" ]; then
    echo "FATAL ERROR: $function_dir/functions.$1.sh not found." 2>&1
    exit 97
  fi
  . "$function_dir/functions.$1.sh"
  PKGTOOLS_INCLUDED_FUNCTIONS="$PKGTOOLS_INCLUDED_FUNCTIONS $1 "
}

# End of functions.common.sh

