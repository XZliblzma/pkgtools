# functions.pkgtool_misc.sh - miscellaneous features of pkgtool
#
# See the file `COPYRIGHT' for copyright and license information.
#

install_packages() {
# $1 = source directory (optional)
  # If no directory is specified, ask it from the user:
  if [ "$1" = "" ]; then
    dialog --title "SELECT SOURCE DIRECTORY" --inputbox "Please enter the name of the directory that \
you wish to install packages from. To install from current directory just press enter." 10 50 2> "$TMP/tmpanswer"
    [ $? != 0 ] && return
    SOURCE_DIR=$(cat "$TMP/tmpanswer")
    [ -z "$SOURCE_DIR" ] && SOURCE_DIR=$(pwd)
  else
    SOURCE_DIR=$1
  fi
  # Create a temporary repository:
  rm -rf "$REPO_DIR/Custom@"
  mkdir "$REPO_DIR/Custom@"
  touch "$REPO_DIR/Custom@/PACKAGES.TXT" "$REPO_DIR/Custom@/itemhelp"
  ls -1 "$SOURCE_DIR" | sed -n "/^$ALLOWED_FILECHARS\+$/!d;/^.*\.\(tgz\|tlz\|tbz\|tar\)$/p" \
      > "$REPO_DIR/Custom@/longnames"
  if [ ! -s "$REPO_DIR/Custom@/longnames" ]; then
    show_msg "The selected directory has no packages to browse." "NO PACKAGES TO BROWSE"
    rm -rf "$REPO_DIR/Custom@"
    return 1
  fi
  echo "$SOURCE_DIR" > "$REPO_DIR/Custom@/address"
  sed -n 'p;=' "$REPO_DIR/Custom@/longnames" \
      | sed 'N;s/\n/%/' \
      | sed -n 's/^\([^%]*\)\.\(tgz\|tlz\|tbz\|tar\)%\([0-9]*\)$/\1%\3/p' \
      | sort > "$REPO_DIR/Custom@/shortnames"
  repository_open "Custom@"
  rm -rf "$REPO_DIR/Custom@"
  return 0
}

setup_scripts() {
  echo 'dialog --title "SELECT SYSTEM SETUP SCRIPTS" --item-help --checklist \
  "Please use the spacebar to select the setup scripts to run.  Hit enter when you \
are done with selecting the scripts." 20 76 12 \' > "$TMP/setupscr"
  for script in "$ADM_DIR/setup/setup."* ; do
    BLURB=`grep '#BLURB' "$script" | cut -b8-`
    if [ "$BLURB" = "" ]; then
      BLURB="\"\""
    fi
    echo " \"`basename "$script" | cut -f2- -d .`\" $BLURB \"no\" $BLURB \\" >> "$TMP/setupscr"
  done
  echo "2> \"$TMP/return\"" >> "$TMP/setupscr"
  . "$TMP/setupscr"
  if [ "$(cat "$TMP/return")" != "" ]; then
    # Run each script:
    for script in $(cat "$TMP/return") ; do
      scrpath=$ADM_DIR/setup/setup.`echo "$script" | tr -d \"`
      rootdevice=$(mount | sed 's/ .*$//;q')
      ( COLOR=on ; cd "$ROOT/" ; . "$scrpath" / "$rootdevice" )
    done
  fi
  rm -f "$TMP/return" "$TMP/setupscr"
}

purge_cache() {
  local FULL PARTITIAL
  FULL=$(cd "$PACKAGE_CACHE_DIR" && du -shc *.tgz *.tlz *.tbz *.tar \
      2> /dev/null | sed -n '$s/\t.*$//p')
#   # This uses version sort of ls. It's very good but not perfect, it is
#   # possible that this will include wrong versions of some weirdly named packs:
#   PARTITIAL=$(cd "$PACKAGE_CACHE_DIR" && ls -vr1 | sed -n'
#       h
#       :loop
#       g
#       N
#       s,^\(.*\)-[^-]*-[^-]*-[^-]*\n\1-\([^-]*-[^-]*-[^-]*\)$,\1-\2,p
#       t loop
#       D' | xargs du -shc 2> /dev/null | sed -n '$s/\t.*$//p')
  if [ "$MODE" = "dialog" ]; then
    dialog --title "EMPTY PACKAGE CACHE?" --defaultno --yesno \
"Removing all the cached package files will free $FULL \
of disk space. $PARTITIAL This will not affect the installed packages. \
Are you sure you want to empty the package cache now?" 8 48
    [ $? != 0 ] && return
  fi
  show_info "Clearing package cache..."
  ( cd "$PACKAGE_CACHE_DIR" && rm -f *.tgz *.tlz *.tbz *.tar *.t??.asc > /dev/null 2> /dev/null )
}

integrity_check_do_it() {
  local ERRORFOUND
  unset ERRORFOUND
  ls -1 "$ADM_DIR/packages" > "$TMP/pkglist"
  sed -n '/-upgraded-[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9],[0-9][0-9]:[0-9][0-9]:[0-9][0-9]$/p' \
      "$TMP/pkglist" > "$TMP/upgradefailed"
  sort "$TMP/pkglist" "$TMP/upgradefailed" \
      | uniq -u \
      | sed "/^$ALLOWED_FILECHARS\+$/d" \
      > "$TMP/illegalchars"
  sort "$TMP/pkglist" "$TMP/upgradefailed" "$TMP/illegalchars" \
      | uniq -u \
      | sed '/^.*-[^-]*-[^-]*-[^-]*$/d' \
      > "$TMP/nonstandard"
  ls -1 "$ADM_DIR/scripts" > "$TMP/scripts"
  sed 's/$/%%%%%/' "$TMP/pkglist" \
      | sort - "$TMP/scripts" \
      | sed -n '
          /%%%%%$/!{
            h
            N
            s/^\(.*\)\n\1%%%%%//
            t
            g
            p
          }
      ' > "$TMP/scriptproblems"
  if [ -s "$TMP/upgradefailed" ]; then
    echo "# These packages have been left when upgradepkg has hit a fatal error"
    echo "# or it has been interrupted by the user. These leftovers can probably"
    echo "# be removed safely. When in doubt try 'removepkg --warn' first."
    cat "$TMP/upgradefailed"
    echo
    ERRORFOUND=yes
  fi
  if [ -s "$TMP/illegalchars" ]; then
    echo "# These package names contain illegal characters:"
    cat "$TMP/illegalchars"
    echo
    ERRORFOUND=yes
  fi
  if [ -s "$TMP/nonstandard" ]; then
    echo "# These package names do not match the Slackware standard."
    echo "# This error is not serious as it will only prevent pkgtool"
    echo "# detecting if updated versions are available."
    cat "$TMP/nonstandard"
    echo
    ERRORFOUND=yes
  fi
  if [ -s "$TMP/scriptproblems" ]; then
    echo "# The package install scripts below do not have a matching package"
    echo "# installed. This error is not serious but it should never happen."
    echo "# The fix is easy: just remove the files listed below. They are in"
    echo "# the directory $ADM_DIR/scripts."
    cat "$TMP/scriptproblems"
    echo
    ERRORFOUND=yes
  fi
  rm -f "$TMP/pkglist" "$TMP/upgradefailed" "$TMP/illegalchars" \
        "$TMP/nonstandard" "$TMP/scripts" "$TMP/scriptproblems"
  if [ "$ERRORFOUND" != "yes" ]; then
    echo "# No errors were found."
    echo
    return 0
  fi
  return 1
}

integrity_check() {
  if [ "$MODE" = "cmdline" ]; then
    echo
    echo "# Checking the package database integrity..."
    echo
    integrity_check_do_it
  else
    integrity_check_do_it > "$TMP/tmpanswer"
    if [ $? != 0 ]; then
      dialog --title "RESULTS OF THE DATABASE INTEGRITY CHECK" --exit-label Back --textbox "$TMP/tmpanswer" 17 76
    else
      dialog --title "RESULTS OF THE DATABASE INTEGRITY CHECK" --ok-label Back --msgbox \
          "No errors were found." 5 50
    fi
  fi
}

# End of functions.pkgtool_misc.sh

