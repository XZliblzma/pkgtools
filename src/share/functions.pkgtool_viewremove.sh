# functions.pkgtool_viewremove.sh - View and Remove in pkgtool
#
# See the file `COPYRIGHT' for copyright and license information.

format_list_of_installed_packages() {
  if ls "$ADM_DIR/packages" > /dev/null 2> /dev/null; then
    cd "$ADM_DIR/packages"
    { grep '^PACKAGE DESCRIPTION:$' -Z -H -m1 -A1 *; echo; } \
        | sed -n '
            h
            n
            /\x00/{
              h
              n
            }
            x
            s/  */ /g
            s/ $//
            s/[\"`$]/\\&/g
            s/\(.*\)\x00\([^:]*:\)\? *\(.*\)/ "\1" "\3" /
            p'
  fi
}

view_installed_package_contents() {
  dialog --title "CONTENTS OF PACKAGE: $1" --no-shadow --exit-label Back \
      --textbox "$ADM_DIR/packages/$1" 0 0 2> /dev/null
}

view_packages() {
  unset DEFITEM
  dialog --title "SCANNING" --infobox "Please wait while \
Pkgtool scans your system to determine which packages you have \
installed and prepares a list for you." 0 0
  (
    echo 'dialog $DEFITEM --menu "Please select the package you wish to view." 20 76 13 \'
    format_list_of_installed_packages | sed 's/$/\\/'
    echo "2> \"$TMP/return\""
  ) > "$TMP/viewscr"
  while : ; do
    . "$TMP/viewscr"
    [ $? != 0 ] && break
    DEFITEM="--default-item $(cat "$TMP/return")"
    view_installed_package_contents "$(cat "$TMP/return")"
  done
  rm -f "$TMP/return" "$TMP/viewscr" "$TMP/tmpmsg"
}

remove_list() {
  dialog --title "SCANNING" --infobox "Please wait while Pkgtool scans \
your system to determine which packages you have installed and prepares \
a list for you." 0 0
  rm -f "$LOG"
  ( umask 0077; echo -n > "$LOG" )
  format_list_of_installed_packages > "$TMP/tmp_instlist"
  sed 's/$/off \\/' "$TMP/tmp_instlist" > "$TMP/tmpargs"
  unset DEFITEM
  while : ; do
    dialog $DEFITEM --title "SELECT PACKAGES TO REMOVE" --separate-output --help-button \
--help-label Details --help-status --checklist "Use the spacebar to select packages to \
delete, and the UP/DOWN arrow keys to scroll up and down through the entire list." \
20 76 12 --file "$TMP/tmpargs" 2> "$TMP/tmpanswer"
    EXITSTATUS=$?
    if [ $EXITSTATUS = 2 ]; then
      DEFITEM=$(sed '1s/HELP //;q' "$TMP/tmpanswer")
      view_installed_package_contents "$DEFITEM"
      DEFITEM="--default-item $DEFITEM"
      sed -n 's/^ "\([^ ]*\)" .*$/\1/p' "$TMP/tmp_instlist" > "$TMP/tmp_a"
      sed 1d "$TMP/tmpanswer" \
          | comm -2 "$TMP/tmp_a" - \
          | sed 's/^\t.*$/"on"/;s/^[^"].*$/"off"/' \
          > "$TMP/tmp_b"
      paste -d ' ' "$TMP/tmp_instlist" "$TMP/tmp_b" \
          | sed 's/$/\\/' \
          > "$TMP/tmpargs"
    else
      if [ $EXITSTATUS = 0 -a -s "$TMP/tmpanswer" ]; then
      remove_packages $(cat "$TMP/tmpanswer")   # Package names better not have spaces.
        dialog --title "PACKAGE REMOVAL COMPLETE" --defaultno --yes-label Delete --no-label Keep \
--yesno "The packages have been removed. A complete log of the files that were \
removed has been created: $TMP/PKGTOOL.REMOVED.\n\n\
Do you like to keep the log file or delete it immediatelly?" 11 54
        [ $? != 0 ] && break
      fi
      rm -f "$TMP/PKGTOOL.REMOVED"
      break
    fi
  done
  rm -f "$TMP/tmp_instlist" "$TMP/tmp_a" "$TMP/tmp_b"
}

remove_packages() {
  local pkg_name
  for pkg_name
  do
    if [ -r "$ADM_DIR/packages/$pkg_name" ]; then
      dialog --title "PACKAGE REMOVAL IN PROGRESS" --cr-wrap --infobox \
"\nRemoving package $pkg_name.\n\
\n\
Since each file must be checked \
against the contents of every other installed package to avoid wiping out \
areas of overlap, this process can take quite some time. If you'd like to \
watch the progress, flip over to another virtual console and type:\n\
\n\
tail -f $TMP/PKGTOOL.REMOVED\n" 13 60
      removepkg --verbose "$pkg_name" >> "$LOG" 2> /dev/null
    else
      echo "No such package: $pkg_name. Can't remove." >> "$LOG"
    fi
  done
}

# End of functions.pkgtool_viewremove.sh

