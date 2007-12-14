# functions.remove.sh - package removal
#
# See the file `COPYRIGHT' for copyright and license information.
#
# Extra credits from original removepkg:
# Conversion to 'comm' utility by Mark Wisdom.

remove_pkg() {
# $1 = full package name without path (foo-0.12-i486-1barney)
# $2 = remove/warn
# $3 = verbose/normal/quiet
  # Open a subshell. Then we don't need to worry about affecting
  # any variables or settings outside this function.
  (
    # Disable pathname expansion (we will enable it separately when needed)
    # and enable overwriting files with redirection:
    set -f +C
    # Set internal field separator to <newline>:
    IFS='
'
    # Verify ne number of arguments given:
    if [ $# != 3 ]; then
      echo "BUG in functions.remove.sh: Invalid number of arguments"
      echo "for remove_pkg() ($#). Press enter."
      read foo
      exit 97
    fi
    # Make sure we have been called with a valid package name:
    if [ ! -f "$ADM_DIR/packages/$1" ]; then
      echo "BUG remove_pkg() called with a non-existing package name:"
      echo "$1"
      echo "Press enter."
      read foo
      exit 97
    fi
    # Now we now we have a match, let's remove the package:
    [ "$2" = "remove" -a "$3" != "quiet" ] && echo "Removing package $1..."
    # Get the list of files (excluding symlinks) of the package being removed:
    sed '1,/^FILE LIST:$/d' "$ADM_DIR/packages/$1" \
        | sort -u > "$TMP/delete_list.$$"
    # Create list of files in other packages. We don't want to remove
    # duplicate files that exist in more other packs. ash doesn't support
    # !(foo) so we have to work around it.
    (
      cd "$ADM_DIR/packages" \
          && sed -s '1,/^FILE LIST:$/d' \
          $({ ls -A1; echo "$1"; } | sort | uniq -u) \
          > "$TMP/required_files.$$"
    )
    # If the package being removed has an install script, we need to
    # do the same for symlinks that we did for files already above:
    if [ -r "$ADM_DIR/scripts/$1" ]; then
      extract_links < "$ADM_DIR/scripts/$1" | sort -u > "$TMP/del_link_list.$$"
      (
        cd "$ADM_DIR/scripts" \
            && cat $({ ls -A1; echo "$1"; } | sort | uniq -u) \
            | extract_links > "$TMP/required_links.$$"
      )
      sort -u "$TMP/required_links.$$" "$TMP/required_files.$$" \
          > "$TMP/required_list.$$"
      # Warn about duplicate symlinks:
      if [ "$3" = "verbose" ]; then
        for LINK in $(comm -12 "$TMP/del_link_list.$$" "$TMP/required_list.$$")
          do
          if [ -L "$ROOT/$LINK" ]; then
            echo "  --> $ROOT/$LINK (symlink) was found in another package." \
                "Skipping."
          else
            echo "WARNING: Nonexistent $ROOT/$LINK (symlink) was found in" \
                "another package. Skipping."
          fi
        done
      fi
      # Delete unique symlinks:
      for LINK in $(comm -23 "$TMP/del_link_list.$$" "$TMP/required_list.$$")
        do
        if [ -L "$ROOT/$LINK" ]; then
          if [ "$2" = "remove" ]; then
            [ "$3" = "verbose" ] \
                && echo "  --> Deleting symlink $ROOT/$LINK" 1>&2
            echo -n "$ROOT/$LINK"
            echo -en '\0'
          else
            echo "  --> $ROOT/$LINK (symlink) would be deleted" 1>&2
          fi
        elif [ "$3" != "quiet" ]; then
          echo "  --> $ROOT/$LINK (symlink) no longer exists. Skipping." 1>&2
        fi
      done | xargs -0r rm -f
    else
      set +f
      cat "$ADM_DIR/scripts/"* | extract_links > "$TMP/required_links.$$"
      set -f
      sort -u "$TMP/required_links.$$" "$TMP/required_files.$$" \
          > "$TMP/required_list.$$"
    fi
    # Show list of missing duplicate files:
    if [ "$3" = "verbose" ]; then
      for FILE in $(comm -12 "$TMP/delete_list.$$" "$TMP/required_list.$$"); do
        if [ ! -d "$ROOT/$FILE" ]; then
          if [ -e "$ROOT/$FILE" ]; then
            echo "  --> $ROOT/$FILE was found in another package. Skipping."
          elif [ "${FILE%%/*}" != "install" ]; then
            echo "WARNING: Nonexistent $ROOT/$FILE was found in another" \
                "package. Skipping."
          fi
        fi
      done
    fi
    # Create the list of files unique to the package being removed:
    comm -23 "$TMP/delete_list.$$" "$TMP/required_list.$$" > "$TMP/uniq_list.$$"
    # Remove entries of info pages from GNU info's directory file:
    if [ "$2" = "remove" -a \
        \( -f "$ROOT/$INFO_DIR/dir" -o -f "$ROOT/$INFO_DIR/dir.gz" \) ]; then
      for FILE in $(grep "\\(\\|./\\)$INFO_DIR/." "$TMP/uniq_list.$$"); do
        "$ROOT/$INSTALL_INFO" --delete -- "$ROOT/$FILE" "$ROOT/$INFO_DIR/dir" \
            > /dev/null 2> /dev/null
      done
    fi
    # Delete files:
    for FILE in $(grep -v '/$' "$TMP/uniq_list.$$"); do
      if [ ! -d "$ROOT/$FILE" ]; then
        if [ -r "$ROOT/$FILE" ]; then
          if [ "$ROOT/$FILE" -nt "$ADM_DIR/packages/$1" ]; then
            echo "WARNING: $ROOT/$FILE changed after package installation." 1>&2
          fi
          if [ "$2" = "remove" ]; then
            [ "$3" = "verbose" ] \
                && echo "  --> Deleting $ROOT/$FILE" 1>&2
            echo -n "$ROOT/$FILE"
            echo -en '\0'
          else
            echo "  --> $ROOT/$FILE would be deleted" 1>&2
          fi
        elif [ "$3" != "quiet" ]; then
          echo "  --> $ROOT/$FILE no longer exists. Skipping." 1>&2
        fi
      fi
    done | xargs -0r rm -f
    # Delete cached man pages, if any:
    for FILE in $(sed -n 's,/man\(./[^/]*$\),/cat\1,p' "$TMP/uniq_list.$$"); do
      if [ -f "$ROOT/$FILE" ]; then
        if [ "$2" = "remove" ]; then
          [ "$3" = "verbose" ] \
              && echo "  --> Deleting $ROOT/$FILE (fmt man page)" 1>&2
          echo -n "$ROOT/$FILE"
          echo -en '\0'
        else
          echo "  --> $ROOT/$FILE (fmt man page) would be deleted" 1>&2
        fi
      fi
    done | xargs -0r rm -f
    # Delete empty directories:
    for DIR in $(sort -r "$TMP/uniq_list.$$" | grep '/$'); do
      # Check that it really is a directory:
      if [ ! -d "$ROOT/$DIR" -o -L "$ROOT/$DIR" ]; then
        [ "$3" != "quiet" ] \
            && echo "WARNING: Unique directory $ROOT/$DIR is not a directory"
        continue
      fi
      if [ "$2" = "remove" ]; then
        if rmdir "$ROOT/$DIR" > /dev/null 2> /dev/null; then
          [ "$3" = "verbose" ] \
              && echo "  --> Deleting empty directory $ROOT/$DIR"
        elif [ "$3" != "quiet" ]; then
          echo "WARNING: Unique directory $ROOT/$DIR contains new files"
        fi
      else
        echo "  --> $ROOT/$DIR (dir) would be deleted if empty"
      fi
    done
    rm -f "$TMP/delete_list.$$" "$TMP/required_files.$$" "$TMP/uniq_list.$$" \
          "$TMP/del_link_list.$$" "$TMP/required_links.$$" "$TMP/required_list.$$"
    if [ "$2" = "remove" ]; then
      [ ! -d "$ADM_DIR/removed_packages" ] && mkdir -m 0755 "$ADM_DIR/removed_packages"
      [ ! -d "$ADM_DIR/removed_scripts"  ] && mkdir -m 0755 "$ADM_DIR/removed_scripts"
      mv -f "$ADM_DIR/packages/$1" "$ADM_DIR/removed_packages"
      [ -r "$ADM_DIR/scripts/$1" ] &&  mv -f "$ADM_DIR/scripts/$1" "$ADM_DIR/removed_scripts"
      # Create a log entry:
      log_line "Removed: $1"
    fi
  # Close the subshell and redirect stderr to stdout:
  ) 2>&1
  return 0
}

# End of functions.remove.sh

