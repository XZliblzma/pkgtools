# functions.dotnew.sh - handling of *.new files and new kernel messages
#
# See the file `COPYRIGHT' for copyright and license information.
#
# dotnew_cleanup
# dotnew_add <pkg_fullname>
# dotnew_print_new
# dotnew_print_kernel
#

# Remove the temporary files:
dotnew_cleanup() {
  rm -rf "$TMP/dotnew" "$TMP/dotnew.pkglist"
}

dotnew_add() {
# $1 = Full package name without extension (.t??); in practice
#      this should be $PKG_FULLNAME.
  if [ ! -f "$TMP/files.$1" ]; then
    echo "BUG in dotnew_add: filelist does not exist. Press enter."
    read foo
    return 97
  fi
  # Dump the list of all *.new files to the temp file. Believe me, it's
  # better to check if the files exist in dotnew_print.
  grep '\.new$' "$TMP/files.$1" >> "$TMP/dotnew"
  # The list of package names is used to check if a new kernel was installed:
  echo "$1" >> "$TMP/dotnew.pkglist"
}

# Print the list of new files with a short header:
dotnew_print_new() {
  if [ -f "$TMP/dotnew" ]; then
    (
      set -f
      IFS='
'
      [ -e "$TMP/dotnew.tmp" ] && rm -rf "$TMP/dotnew.tmp"
      for I in $(cat "$TMP/dotnew"); do
        [ -e "$ROOT/$I" ] && echo "/$I" >> "$TMP/dotnew.tmp"
      done
    )
    if [ -f "$TMP/dotnew.tmp" ]; then
      echo
      echo "Remember to check the new configuration files:"
      cat "$TMP/dotnew.tmp"
      rm -f "$TMP/dotnew.tmp"
    fi
  fi
}

dotnew_print_kernel() {
  if [ -f "$TMP/dotnew.pkglist" -a -z "$PKGTOOL_AS_INSTALLER" ]; then
    if [ -n "$(sed -n 's,^.*/,,
          /^kernel-headers-[^-]\+-[^-]\+-[^-]\+$/d
          /^kernel-source-[^-]\+-[^-]\+-[^-]\+/d
          /^kernel-/p' "$TMP/dotnew.pkglist")" ]; then
      echo
      echo "If you installed a new kernel, remember to check your boot loader"
      echo "configuration and in case of LILO run /sbin/lilo. If you are using"
      echo "another boot loader, such as GRUB, refer to its manual to learn how"
      echo "to select the new kernel at boot."
    fi
  fi
}

# End of functions.dotnew.sh

