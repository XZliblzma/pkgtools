# functions.pkgtool_repository.sh - pkgtool repository handling
#
# See the file `COPYRIGHT' for copyright and license information.
#
# Thanks to Ville Koskinen for this script which generates a function tree:
# http://w-ber.ormgas.com/code/sh_functions.pl
# This tree hopefully clarifies the structure of the repository functions.
# FIXME: Needs to be updated.
#
# repository_list                                     Show the list of repos; Open/Edit/Cancel
# |- repository_prompt_name                           New/Edit/Delete
# |   |- repository_validate_nickname
# |   `- repository_validate_uri
# `- repository_open                                  Ask for filter; Diskset view
#     |- repository_update                            Download/Copy & process FILELIST.TXT & PACKAGES.TXT
#     |   `- repository_update_cp                     Wrapper choosing between 'download' and 'cp'.
#     |- repository_create_updatelist                 List all packages excluding pasture/ and testing/.
#     |- diskset_description                          Look for diskset description from disksets.txt.
#     |- repository_actions                           Install/Download/Update/SelectAll
#     |   |- repository_update
#     |   |- repository_create_updatelist
#     |   `- repository_actions_install
#     |       |- repository_create_install_list       Creates the list of the packages to install/download
#     `- repository_browse                            Package list view
#         |- repository_create_packagelist_script     Temporary files for each diskset and dialog parameters.
#         |   |- repository_filter_leave_any
#         |   |- repository_filter_remove_blacklisted
#         |   `- repository_filter_remove_exact
#         `- repository_actions
#             |- repository_update
#             |- repository_create_updatelist
#             `- repository_actions_install
#                 `- repository_create_install_list

repository_update_cp() {
# $1 source file/URL ; $2 = target filename
# This function tries to hide complexity between gzipped and not gzipped
# file being copied/downloaded. If UPDATE_CP_GZIPPED=1 and $1.gz isn't
# found, we automatically try if $1 (uncompressed file) is found. Further
# calls won't try to access gzipped files anymore unless someone sets
# UPDATE_CP_GZIPPED back to 1.
  case "$UPDATE_CP_GZIPPED-$IS_URL" in
    0-0)  cp "$1" "$2" > /dev/null 2> /dev/null ;;
    0-1)  download "$1" "$2" ;;
    1-0)  cp "$1.gz" "$2.gz" > /dev/null 2> /dev/null && gunzip "$2.gz" > /dev/null 2> /dev/null ;;
    1-1)  download "$1.gz" "$2.gz" && gunzip "$2.gz" > /dev/null 2> /dev/null ;;
  esac
  # The exit status of cp/wget/gunzip passes here:
  if [ $? != 0 ]; then
    if [ "$UPDATE_CP_GZIPPED" = "1" ]; then
      # No $1.gz was found. First make sure that no broken files are left:
      rm -f "$2" "$2.gz"
      # Try again but look for uncompressed file:
      UPDATE_CP_GZIPPED=0
      repository_update_cp "$1" "$2"
      return $?
    fi
    # Error even when copying/downloading uncompressed file.
    # Clean up and return an error:
    rm -f "$2"
    return 1
  fi
  return 0
}

repository_update() {
# $1 = Repo nickname
  local IS_URL PKGTXT
  if [ "$1" = "" -o ! -d "$REPO_DIR/$1" ]; then
    show_msg "Repository does not exist: $1" "ERROR"
    return 1
  fi
  REPOURI=$(cat "$REPO_DIR/$1/address")
  if is_url_dir "$REPOURI"; then
    [ "$MODE" = "dialog" ] && clear
    echo ".-------------------------------------."
    echo "| Downloading the package information |"
    echo "'-------------------------------------'"
    IS_URL=1
  else
    show_info "Copying files..." "PLEASE WAIT"
    IS_URL=0
  fi
  # It is important that there are no old files:
  rm -f "$TMP/PACKAGES.TXT.$1."*
  # Assume that we can use gzipped files. repository_update_cp will
  # unset this automatically if gzipped files are not found.
  UPDATE_CP_GZIPPED=1
  # Download PACKAGES.TXT from the main directory:
  repository_update_cp "$REPOURI/PACKAGES.TXT" "$TMP/PACKAGES.TXT.$1.main"
  if [ $? != 0 ]; then
    if [ "$IS_URL" = "1" ]; then
      show_textmode_error_message
    else
      show_msg "Unable to copy PACKAGES.TXT.gz or PACKAGES.TXT from $REPOURI." "ERROR"
    fi
    return 1
  fi
  # Now try to autodetect if this is an official Slackware repository (or
  # a very similar repository). If it is, we need PACKAGES.TXTs from extra/,
  # testing/, pasture/ and patches/. If some files are missing, we simply
  # ignore all errors.
  if [ "$(sed -n '5{p;q}' "$TMP/PACKAGES.TXT.$1.main")" = "in the ./slackware/ directory." ]; then
    # Checksums file in slackware/ is smaller than in the root dir:
    repository_update_cp "$REPOURI/slackware/CHECKSUMS.md5" "$TMP/CHECKSUMS.md5.$1.main"
    for PKGTXT in extra testing pasture contrib patches; do
      repository_update_cp "$REPOURI/$PKGTXT/PACKAGES.TXT" "$TMP/PACKAGES.TXT.$1.$PKGTXT" \
          && repository_update_cp "$REPOURI/$PKGTXT/CHECKSUMS.md5" "$TMP/CHECKSUMS.md5.$1.$PKGTXT"
    done
  else
    # Not official or a similar repo, pick the checksums file from the root
    # directory (error is ignored):
    repository_update_cp "$REPOURI/CHECKSUMS.md5" "$TMP/CHECKSUMS.md5.$1.main"
  fi
  # As a last step download the new ChangeLog.txt (error ignored):
  repository_update_cp "$REPOURI/ChangeLog.txt" "$REPO_DIR/$1/ChangeLog.txt"
  # Now we should have good PACKAGES.TXT and possibly also CHECKSUMS.md5.
  show_info "Processing package information..." "PLEASE WAIT"
  rm -f "$REPO_DIR/$1/longnames" "$REPO_DIR/$1/shortnames"* "$REPO_DIR/$1/PACKAGES.TXT" "$REPO_DIR/$1/MD5"
  cat "$TMP/PACKAGES.TXT.$1."* > "$REPO_DIR/$1/PACKAGES.TXT"
  rm -f "$TMP/PACKAGES.TXT.$1."*
  # Extract package directories and names from PACKAGES.TXT. Filter off
  # pkgtools except if it's Tukaani pkgtools. This is to prevent accidental
  # downgrading of pkgtools.
  if [ -z "$PKGTOOL_AS_INSTALLER" ]; then
    packagestxt2filelist "$REPO_DIR/$1/PACKAGES.TXT" | sed '
            h
            s,\(^\|/\)pkgtools-\([^-/]*\)-[^-/]*-[^-/]*$,\2,
            T
            s,tukaani,,
            t success
            d
            :success
            g' \
        > "$REPO_DIR/$1/longnames"
  else
    # If we are used as an installer, we really do not want to
    # skip installing non-Tukaani pkgtools!
    packagestxt2filelist "$REPO_DIR/$1/PACKAGES.TXT" > "$REPO_DIR/$1/longnames"
  fi
  if [ ! -s "$REPO_DIR/$1/longnames" ]; then
    show_msg "No package information was found." "ERROR"
    rm -f "$REPO_DIR/$1/PACKAGES.TXT"
    return 1
  fi
  # Detect repository type: Official (or similar) or Other
  if grep -q '^slackware/' "$REPO_DIR/$1/longnames"; then
    # Official repository: We don't want to install vulnerable packages
    # so merge 'slackware' to contain all 'patches':
    grep '^slackware/' "$REPO_DIR/$1/longnames" > "$TMP/$1.slackware"
    for I in $(grep '^patches/' "$REPO_DIR/$1/longnames"); do
      sed -i "s/\(slackware\/[a-zA-Z]*\)\/$( \
          package_basename "$I")-[^-]*-[^-]*-[^-]*$/\1\/..\/..\/patches\/packages\/$( \
          basename "$I")/" "$TMP/$1.slackware"
    done
    # Now 'slackware' and 'patches' are merged. Add rest of the packages
    # from other directories and write new $REPO_DIR/$1/longnames:
    sed '/^\(slackware\|patches\)\//d' "$REPO_DIR/$1/longnames" >> "$TMP/$1.slackware"
    rm -f "$REPO_DIR/$1/longnames"
    mv "$TMP/$1.slackware" "$REPO_DIR/$1/longnames"
    # Split disk set listings to different files:
    sed -n 'p;=' "$REPO_DIR/$1/longnames" | sed 'N;s/\n/%/' > "$TMP/$1.numbered"
    for I in $(sed -n 's/^\(slackware\/\|\)\([^/]*\)\/.*$/\2/p' "$REPO_DIR/$1/longnames" | uniq); do
      sed -n '/\(^'$I'\|\/'$I'\)\//{s/.*\/\([^/]*\)\.\(tgz\|tlz\|tbz\|tar\)%\([0-9]*\)$/\1%\3/p}' \
          "$TMP/$1.numbered" | sort -u > "$REPO_DIR/$1/shortnames.$I"
    done
    rm -f "$TMP/$1.numbered"
  else
    # Make it possible to use "slackware", "extra", "testing" and "patches"
    # as separate repos. This is a bit rough guess, but let's hope it
    # doesn't break pkgtool for many users.
    case ${REPOURI##*/} in (slackware|extra|testing|patches)
      sed -i "s|^${REPOURI##*/}/||" "$REPO_DIR/$1/longnames" ;;
    esac
    # Unofficial repositories will be shown in a one long listing:
    sed -n 'p;=' "$REPO_DIR/$1/longnames" \
        | sed 'N;s/\n/%/' \
        | sed -n 's/^.*\/\([^/]*\)\.\(tgz\|tlz\|tbz\|tar\)%\([0-9]*\)$/\1%\3/p' \
        | sort \
        > "$REPO_DIR/$1/shortnames"
  fi
  # Convert CHECKSUMS.md5 to the nicest format in our point of view:
  sed -n 's#^\([0-9a-fA-F]\{32\}\) \+\(\./\)*\(.*/\)\([^/ ]\+\)\.\(tgz\|tlz\|tbz\|tar\)$#\4.\5 \1#p' \
      "$TMP/CHECKSUMS.md5.$1."* > "$REPO_DIR/$1/MD5"
  rm -f "$TMP/CHECKSUMS.md5.$1."*
  # No need to leave empty MD5 file:
  [ ! -s "$REPO_DIR/$1/MD5" ] && rm -f "$REPO_DIR/$1/MD5"
  # Parse PACKAGES.TXT. This can be tricky with unofficial repositories
  # as they tend to be lower quality than official ones. :-/
  sed -n 's/^PACKAGE NAME: *\([^: ]*\)\.\(tgz\|tlz\|tbz\|tar\) *$/\1:/p' \
      "$REPO_DIR/$1/PACKAGES.TXT" > "$TMP/$1.tmp1"
  sed -n 's/^PACKAGE SIZE (compressed): *\([0-9]*\).*$/[\1 K;/p' "$REPO_DIR/$1/PACKAGES.TXT" > "$TMP/$1.tmp2"
  sed -n 's/^PACKAGE SIZE (uncompressed): *\([0-9]*\).*$/\1 K]/p' "$REPO_DIR/$1/PACKAGES.TXT" > "$TMP/$1.tmp3"
  sed -n '/^PACKAGE DESCRIPTION: *$/{
            n
            s/[\"`$]/\\&/g
            s/^[^:]*: *\(.*\)$/\1/
            p
          }
      ' "$REPO_DIR/$1/PACKAGES.TXT" > "$TMP/$1.tmp4"
  paste -d ' ' "$TMP/$1.tmp1" "$TMP/$1.tmp4" "$TMP/$1.tmp2" "$TMP/$1.tmp3" | sort -u > "$REPO_DIR/$1/itemhelp"
  rm -f "$TMP/$1."*
  if [ "$MODE" = "cmdline" ]; then
    echo "Database updated: $1"
  elif [ "$MODE" = "dialog" -a -s "$REPO_DIR/$1/ChangeLog.txt" ]; then
    dialog --title "CHANGELOG VIEWER: $1" --exit-label Continue --no-shadow \
        --textbox "$REPO_DIR/$1/ChangeLog.txt" 0 0
  fi
  return 0
}

repository_create_install_list() {
# $1 = Repo nickname ; $2 = "install_all" (optional) Install all packages
# instead of only selected. This is used by command line options.
# Creates $TMP/$1.install which has relative paths to packages to be installed.
  local I J
  rm -f "$TMP/$1.install_numbers"
  if [ "$2" = "install_all" ]; then
    mv "$TMP/$1.singlelist.0" "$TMP/$1.install_numbers"
  elif [ -f "$TMP/$1.singlelist.0" ]; then
    paste -d ' ' "$TMP/$1.singlelist.3" "$TMP/$1.singlelist.0" \
        | sed -n 's/^"on" //p' > "$TMP/$1.install_numbers"
  else
    for I in "$TMP/$1.shortnames"*.0; do
      if [ "$I" = "$TMP/$1.shortnames*.0" ]; then
        show_msg "No packages selected." "ERROR"
        return 1
      fi
      J=$(echo "$I" | sed 's/\..$//')
      paste -d ' ' "$J.3" "$J.0" \
          | sed -n 's/^"on" //p' \
          >> "$TMP/$1.install_numbers"
    done
  fi
  # Pick the package names matching the package numbers in "longnames":
  sed = "$REPO_DIR/$1/longnames" \
      | sed 'N;s/\n/ /' \
      | sort -n - "$TMP/$1.install_numbers" \
      | sed -n '/^[0-9]*$/{n;s/^[0-9]* //p}' \
      > "$TMP/$1.install_names"
  # Unless we are used as installed, make sure that glibc-solibs is
  # installed before any other packages and pkgtools is upgraded as
  # the very last package. Those who insist that UPGRADE.TXT says
  # that sed should be upgraded at the beginning too, the reason was
  # that Slack 9.1->10.0 upgraded sed from 3.xx to 4.xx which supported
  # quite a few new features which could be needed by newer pkgtools or
  # other packaging related scripts.
  if [ -n "$PKGTOOL_AS_INSTALLER" ]; then
    mv -f "$TMP/$1.install_names" "$TMP/$1.install"
  else
    sed -n '/\(^\|\/\)glibc-solibs-[^-]*-[^-]*-[^-]*$/p' \
        "$TMP/$1.install_names" > "$TMP/$1.install"
    sed -n '
          /\(^\|\/\)pkgtools-[^-]*-[^-]*-[^-]*$/{
            $!{
              h
              b
            }
          }
          /\(^\|\/\)glibc-solibs-[^-]*-[^-]*-[^-]*$/!p
          ${
            g
            /pkgtools/p
          }
        ' "$TMP/$1.install_names" \
        >> "$TMP/$1.install"
  fi
  rm -f "$TMP/$1.install_numbers" "$TMP/$1.install_names"
  return 0
}

repository_actions_install() {
# $1 = repo nickname ; $2 = "install" or "download" ;
# $3 = "install_all" (optional) Install all packages instead of only
# selected. This is used by command line options.
  local J IS_URL EXITSTATUS FILE GPG BASENAME
  local MD5=
  # Maybe this is too multimedia but at least it is simple. ;-)
  local INSTALL_TIME=$(date +%s)
  # Remove possibly existing old list of *.new files:
  dotnew_cleanup
  # Create list of packages to install ($TMP/$1.install):
  repository_create_install_list "$1" "$3" || return 0
  PKG_COUNT_TOTAL=$(wc -l < "$TMP/$1.install" | tr -d ' ') # tr is needed with busybox
  PKG_COUNT=0
  [ -f "$REPO_DIR/$1/gpg" ] && GPG=1 || GPG=0
  # Initialize the list of succeeded installations/downloads:
  : > "$TMP/successful.$1"
  for J in $(cat "$TMP/$1.install"); do
    PKG_COUNT=$((PKG_COUNT + 1))
    BASENAME=$(basename "$J")
    if is_url_package "$REPOURI/$J"; then
      IS_URL=1
      FILE="$PACKAGE_CACHE_DIR/$BASENAME"
    else
      IS_URL=0
      FILE="$REPOURI/$J"
    fi
    # Show an appropriate message that we are downloading/installing a package:
    if [ "$MODE" = "dialog" ]; then
      # Parse description from PACKAGES.TXT and make it exactly 13 lines long.
      # Then add package size information as 14th line.
      sed -n "/^PACKAGE NAME: *$BASENAME *$/,/^$/{
                /^$/q
                s/^[^: ]*: \{0,1\}//
                p
              }
          " "$REPO_DIR/$1/PACKAGES.TXT" | sed -n '
              /^PACKAGE /!p
              /^PACKAGE /{
                s/^PACKAGE SIZE (compressed): *\([0-9]*\).*$/Size: Compressed: \1 K/
                s/^PACKAGE SIZE (uncompressed): *\([0-9]*\).*$/, Uncompressed: \1 K./
                /^PACKAGE .*$/d
                H
                s/^PACKAGE .*$//
              }
              ${
                g
                s/\n//g
                p
              }
          ' | sed -n '
              $!p
              ${
                s/^/\n\n\n\n\n\n\n\n\n\n\n\n\n/p
              }
          ' | sed -n '
              1,13p
              $p
          ' > "$TMP/tmpargs"
      if [ "$IS_URL" = "1" ]; then
        clear
        echo "$PKG_COUNT/$PKG_COUNT_TOTAL: $BASENAME"
        echo "==============================================================================="
        uniq "$TMP/tmpargs"
        echo "==============================================================================="
      else
        dialog --title "$PKG_COUNT/$PKG_COUNT_TOTAL: $BASENAME" --infobox "$(cat "$TMP/tmpargs")" 0 0
      fi
    elif [ "$MODE" = "cmdline" ]; then
      echo "$PKG_COUNT/$PKG_COUNT_TOTAL: $BASENAME"
    fi
    # Search the MD5 checksum and store it to MD5 variable:
    [ -f "$REPO_DIR/$1/MD5" ] && MD5=$(sed -n "/^$(echo "$J" \
        | sed 's,^.*/,,;s/\./\\./g') /{s/^.* //p;q}" "$REPO_DIR/$1/MD5")
    # 1) First download the package to the cache.
    if [ "$IS_URL" = "1" ]; then
      while :; do
        download_package "$REPOURI/$J" "$GPG"
        if [ $? != 0 ]; then
          # Something went wrong:
          [ "$MODE" != "dialog" ] && break 2 # Quit if non-interactive
          while :; do
            echo -n "Retry, Skip or Quit? [R/s/q] "
            read REPLY
            case "$REPLY" in
              r|R|'') rm -f "$FILE"; continue 2 ;;
              s|S)  continue 3 ;;
              q|Q)  break 3 ;;
            esac
          done
        fi
        # 2a) Verify the MD5 sum of a downloaded package.
        [ "$MODE" != "quiet" ] && echo -n "Verifying the MD5 checksum..."
        if [ ${#MD5} = 32 ]; then
          if [ "$(md5sum < "$FILE" | cut -f 1 -d ' ')" = "$MD5" ]; then
            [ "$MODE" != "quiet" ] && echo " OK"
          else
            [ "$MODE" != "quiet" ] && echo " FAILED"
            [ "$MODE" != "dialog" ] && break 2 # Quit if non-interactive
            while :; do
              echo -n "Redownload, Skip or Quit? [R/s/q] "
              read REPLY
              case "$REPLY" in
                r|R|'') rm -f "$FILE"; continue 2 ;;
                s|S)  continue 3 ;;
                q|Q)  break 3 ;;
              esac
            done
          fi
        else
          echo " N/A"
        fi
        # 3a) Verify the GPG signature.
        [ "$GPG" != "1" ] && break # GPG disabled
        gnupg_verify_signature "$FILE"
        EXITSTATUS=$?
        [ $EXITSTATUS = 0 ] && break # Signature OK
        # Lazy repo admins might create repos that do not have MD5 sums
        # but have GPG signatures. If MD5 sum wasn't available, it is
        # possible that the GPG error is because of broken download.
        # In this case we give the user an option to redownload.
        if [ ${#MD5} != 32 ]; then
          echo "One possible reason for failing signature check is that the downloaded"
          echo "package file is corrupt, because there is no MD5 checksum available."
          while :; do
            echo -n "Redownload, Skip or Quit? [R/s/q] "
            read REPLY
            case "$REPLY" in
              r|R|'') rm -f "$FILE"; continue ;;
              s|S)  continue 2 ;;
              q|Q)  break 2 ;;
            esac
          done
        else
          echo "Aborting because of GPG error. Press enter to return to the menu."
          read REPLY
          break 2
        fi
        break # This while..done loop should never hit this line.
      done
    else # IS_URL=0
      # 2b) Verify MD5 sum of a package on the local disk.
      if [ ${#MD5} = 32 ]; then
        [ "$MODE" = "cmdline" ] && echo -n "Verifying the MD5 checksum..."
        if [ "$(md5sum < "$FILE" | cut -f 1 -d ' ')" != "$MD5" ]; then
          [ "$MODE" = "cmdline" ] && echo " FAILED"
          [ "$MODE" != "dialog" ] && break
          dialog --title "MD5 CHECKSUM MISMATCH" \
              --yes-label Skip --no-label Quit --yesno \
              "The MD5 sum of the package $BASENAME did not match. \
This means that either the package is corrupt or CHECKSUMS.md5 has invalid \
information. Do you want to skip this package or quit?" 12 60 \
              && continue
          break
        fi
        [ "$MODE" = "cmdline" ] && echo " OK"
      fi
      # 3b) Verify the GPG signature.
      if [ "$GPG" = "1" ]; then
        if [ "$MODE" = "cmdline" ]; then
          gnupg_verify_signature "$FILE"
        else
          gnupg_verify_signature "$FILE" quiet
        fi
        if [ $? != 0 ]; then
          if [ "$MODE" = "dialog" -a ${#MD5} != 32 ]; then
            dialog --title "GPG SIGNATURE VERIFICATION FAILED" \
                --yes-label Skip --no-label Quit --yesno \
                "pkgtool was unable to verify the GPG signature of the package \
$BASENAME. One possible reason for failing signature check is that \
the downloaded package file is corrupt, because there is no MD5 checksum \
available. Anyway, pkgtool refuses to install this package.\n\n\
Do you want to skip this package or quit installing packages?" 13 60 \
                && continue 2
          else
            dialog --title "GPG SIGNATURE VERIFICATION FAILED" --msgbox \
                "pkgtool was unable to very the GPG signature of the package \
$BASENAME. Aborting installation."
          fi
          break 2
        fi
      fi
    fi
    # 4) Finally install the package, if requested:
    if [ "$2" = "install" ]; then
      [ "$MODE" = "cmdline" -o \( "$MODE" = "dialog" -a "$IS_URL" = "1" \) ] \
          && echo "Installing/Upgrading the package..."
      upgradepkg --quiet --no-gpg --keep-dotnew --install-new --reinstall "$FILE"
      if [ $? != 0 ]; then
        if [ "$MODE" != "dialog" ]; then
          show_msg "Cannot install $BASENAME. (Package is corrupt?)"
          break
        fi
        if [ "$IS_URL" = "1" ]; then
          echo "Error installing the package $BASENAME."
          echo "The most probable reason is that the package is corrupt"
          echo "or we run out of disk space."
          while :; do
            echo -n "Skip or Quit? [S/q] "
            read REPLY
            case "$REPLY" in
              s|S|'') continue 2 ;;
              q|Q)  break 2 ;;
            esac
          done
        fi
      fi
    fi
    # 5) Record the successful installation/download:
    echo "$J" >> "$TMP/successful.$1"
  done
  # Installation/Downloading done. Show some statistics and remind of *.new files, if any:
  INSTALL_TIME=$(($(date +%s) - $INSTALL_TIME))
  printf "Time elapsed: %02d:%02d\n" "$(($INSTALL_TIME / 60))" "$(($INSTALL_TIME % 60))" > "$TMP/tmpargs"
  echo "Number of packages: $PKG_COUNT" >> "$TMP/tmpargs"
  dotnew_print_kernel >> "$TMP/tmpargs"
  dotnew_print_new >> "$TMP/tmpargs"
  dotnew_cleanup
  # Show the list of packages only in dialog mode. Command line users have already it on their screen.
  if [ $PKG_COUNT = 0 ]; then
    show_msg "No packages selected." "ERROR"
  elif [ "$MODE" = "dialog" ]; then
    sort "$TMP/successful.$1" "$TMP/$1.install" | uniq -u > "$TMP/failedpacks.$1"
    if [ -s "$TMP/failedpacks.$1" ]; then
      echo -e "\nList of failed packages:" >> "$TMP/tmpargs"
      sed 's,^.*/,,;s,\.[^.]*$,,' "$TMP/failedpacks.$1" >> "$TMP/tmpargs"
    fi
    if [ -s "$TMP/successful.$1" ]; then
      echo -e "\nList of successfully processed packages:" >> "$TMP/tmpargs"
      sed 's,^.*/,,;s,\.[^.]*$,,' "$TMP/successful.$1" >> "$TMP/tmpargs"
    fi
    [ "$2" = "install" ] && dialog --title "INSTALLATION COMPLETE" --exit-label OK --textbox "$TMP/tmpargs" 20 76
    [ "$2" = "download" ] && dialog --title "DOWNLOAD COMPLETE" --exit-label OK --textbox "$TMP/tmpargs" 20 76
  elif [ "$MODE" = "cmdline" ]; then
    echo
    cat "$TMP/tmpargs"
  fi
  local PKGTOOLS_UPGRADED=
  sed -n '/\(^\|\/\)pkgtools-[^-]*-[^-]*-[^-]*$/q1' "$TMP/$1.install" \
      || PKGTOOLS_UPGRADED=yes
  rm -f "$TMP/$1.install" "$TMP/successful.$1" "$TMP/failedpacks.$1"
  [ -n "$PKGTOOLS_UPGRADED" -a -z "$PKGTOOL_AS_INSTALLER" ] && dialog \
      --title "PKGTOOLS HAVE BEEN UPGRADED" \
      --msgbox "A new pkgtools package was installed. However, the old \
pkgtool is still running. It is strongly recommend to exit or restart \
the pkgtool now." 7 60
  return 0
}

repository_actions() {
# $1 = Repo nickname ; $2 = Package list filtering mode ; $3 = show_update (optional)
  REPOURI=$(cat "$REPO_DIR/$1/address")
  echo "dialog --title \"REPOSITORY ACTIONS\" --menu \"\" 11 60 5 \\" > "$TMP/tmpscript"
  echo "Install \"Install or upgrade selected packages\" \\" >> "$TMP/tmpscript"
  [ -z "$PKGTOOL_AS_INSTALLER" ] && is_url_dir "$REPOURI" && \
      echo "Download \"Download packages only; do not install\" \\" >> "$TMP/tmpscript"
  [ "$3" = "show_update" ] && echo "Update \"Reload PACKAGES.TXT\" \\" >> "$TMP/tmpscript"
  [ -f "$REPO_DIR/$1/singlelist" -a -f "$TMP/$1.singlelist.3" ] && \
      echo "SelectAll \"Mark all the packages as selected.\" \\" >> "$TMP/tmpscript"
  [ -f "$REPO_DIR/$1/ChangeLog.txt" ] && \
      echo "ChangeLog \"View ChangeLog\" \\" >> "$TMP/tmpscript"
  echo "2> \"$TMP/tmpanswer\"" >> "$TMP/tmpscript"
  . "$TMP/tmpscript"
  [ $? != 0 ] && return 1
  case "$(cat "$TMP/tmpanswer")" in
    Update)
      # We need to remove all cached menu scripts:
      rm -f "$TMP/$1."*
      repository_update "$1"
      [ -f "$REPO_DIR/$1/singlelist" ] && repository_create_updatelist "$1" "$2"
      return 1
      ;;
    Install)
      repository_actions_install "$1" install
      return 0
      ;;
    Download)
      repository_actions_install "$1" download
      return 0
      ;;
    SelectAll)
      sed -i 's,^.*$,"on",' "$TMP/$1.singlelist.3"
      return 1
      ;;
    ChangeLog)
      dialog --title "CHANGELOG VIEWER: $1" --exit-label Continue --no-shadow \
        --textbox "$REPO_DIR/$1/ChangeLog.txt" 0 0
      return 1
      ;;
  esac
  return 0
}

# repository_filter* functions take one filename as an argument. The file
# contents must be formatted like files 'shortnames': foo-bar-0.12-i486-1baz%987
repository_filter_remove_exact() {
  # Filters out package versions that are already installed.
  sort "$1" "$TMP/installedlist" | sed -n '
      /%/!{
        :loop
        N
        s/^\([^%]*\)\n\1%[0-9]*$/\1/
        t loop
        D
      }
      p'
}

repository_filter_leave_any() {
  # Filters out all packages that do not have any version installed.
  sort "$1" "$2" | sed -n '
      h
      :loop
      g
      N
      s/^\([^%]*\)%[^-%]*-[^-%]*-[^-%]*\n\(\1-[^-%]*-[^-%]*-[^-%]*%[0-9]*\)$/\2/p
      t loop
      D'
}

repository_filter_remove_blacklisted() {
  sed '/[#% ]/d;/^$/d' "$BLACKLIST_FILE" > "$TMP/blacklist_tmp"
  sort "$1" "$TMP/blacklist_tmp" | sed -n '
      /%/!{
        :loop
        N
        s/^\([^%]*\)\n\1-[^-%]*-[^-%]*-[^-%]*%[0-9]*$/\1/
        t loop
        D
      }
      p'
  rm -f "$TMP/blacklist_tmp"
}

repository_create_packagelist_script() {
# $1 = Repo name ; $2 = shortnames* file (e.g. shortnames.ap)
# $3 = Package list filtering mode ; $4 = Default item (optional)
# Function creates $TMP/tmpscript
  echo dialog --title \"BROWSE PACKAGE REPOSITORY\" --separate-output --item-help \\ > "$TMP/tmpscript"
  [ "$1" != "Custom@" ] && echo --help-button --help-label Details --help-status \\ >> "$TMP/tmpscript"
  [ "$2" = "shortnames" -o "$2" = "singlelist" ] && echo --ok-label Actions \\ >> "$TMP/tmpscript"
  [ "$4" != "" ] && echo --default-item "$4" \\ >> "$TMP/tmpscript"
  echo "--checklist \"$1 - $(cat "$REPO_DIR/$1/address")\"" 20 76 13 \\ >> "$TMP/tmpscript"
  if [ ! -f "$TMP/$1.$2.0" ]; then
    # Create list of installed packages. Package names that do not match
    # the Slackware spec are filtered out. ('sort' is just to be sure, shouldn't hurt much.):
    ls -1 "$ADM_DIR/packages" | sed -n '/^.*-[^-]*-[^-]*-[^-]*$/p' | sort > "$TMP/installedlist"
    # repository_filter_remove_exact() and repository_filter_leave_any() require different
    # sort order. This can be achieved by converting the installed packages names like this:
    #     foo-bar-0.12-i486-1baz => foo-bar%0.12-i486-1baz
    sed 's/^\(.*\)-\([^-]*-[^-]*-[^-]*\)$/\1%\2/' "$TMP/installedlist" | sort > "$TMP/installedlist%"
    # FIXME: Multiple versions of the same package installed?
    case "$3" in
      All)
        cat "$REPO_DIR/$1/$2" > "$TMP/$1.$2.unsplitted"
        ;;
      AlmostAll)
        repository_filter_remove_blacklisted "$REPO_DIR/$1/$2" \
            | repository_filter_remove_exact - \
            > "$TMP/$1.$2.unsplitted"
        ;;
      New)
        repository_filter_leave_any "$REPO_DIR/$1/$2" "$TMP/installedlist%" \
            | sort - "$REPO_DIR/$1/$2" \
            | uniq -u \
            | repository_filter_remove_blacklisted - \
            > "$TMP/$1.$2.unsplitted"
        ;;
      Updates)
        # First find packages having exactly the same version installed and
        # in the repository. Then filter out all versions of these packages.
        # E.g. if user has installed kernel-modules-2.6.x from testing/ and
        # there's no new kernel-modules available in testing/, we hide all
        # version of the kernel-modules package including kernel-modules-2.4.x
        # in slackware/a/. Finally filter out packages that have no version
        # installed and blacklisted packages. Simple, huh? ;-D
        sed 's/%[^%]*$//' "$REPO_DIR/$1/$2" \
            | sort - "$TMP/installedlist" \
            | uniq -d \
            | sed 's/-[^-]*-[^-]*-[^-]*$/%/' \
            | sort - "$TMP/installedlist" \
            | sed -n '
                /%/{
                  :loop
                  N
                  s/^\(.*\)%\n\1-[^-]*-[^-]*-[^-]*$/\1%/
                  t loop
                  D
                }
                # Convert the output to format of "installedlist%":
                s/^\(.*\)-\([^-]*-[^-]*-[^-]*\)$/\1%\2/p
            ' | repository_filter_leave_any "$REPO_DIR/$1/$2" - \
            > "$TMP/$1.$2.unsplitted.foo"
        # Remove testing packages except if there is a package only at testing.
        if [ -f "$REPO_DIR/$1/shortnames.testing" ]; then
          sort "$TMP/$1.$2.unsplitted.foo" "$REPO_DIR/$1/shortnames.testing" \
              | uniq -u \
              | sed 's/-[^-%]*-[^-%]*-[^-%]*%[^%]*$//' \
              | sort - "$REPO_DIR/$1/shortnames.testing" \
              | sed -n '
                  /%/!{
                    h
                    :loop
                    g
                    N
                    s/^\([^%]*\)\n\1-\([^-%]*-[^-%]*-[^-%]*%[0-9]*\)$/\2/
                    t loop
                    D
                  }
                  p
              ' | sort - "$TMP/$1.$2.unsplitted.foo" \
              | uniq -u \
              > "$TMP/$1.$2.unsplitted.bar"
          rm -f "$TMP/$1.$2.unsplitted.foo"
          mv "$TMP/$1.$2.unsplitted.bar" "$TMP/$1.$2.unsplitted.foo"
        fi
        repository_filter_remove_blacklisted "$TMP/$1.$2.unsplitted.foo" > "$TMP/$1.$2.unsplitted"
        ;;
      CustomName)
        grep -i -- "$CUSTOM_FILTER" "$REPO_DIR/$1/$2" > "$TMP/$1.$2.unsplitted"
        ;;
      CustomDesc)
        sed -n '
                /^PACKAGE NAME:/,/^$/{
                  /^PACKAGE NAME:/{
                    s/^.* \([^ ]*\) *$/\1/
                    h
                    D
                  }
                  /^$/{
                    g
                    s/\n/ /g
                    p
                  }
                  s/^[^: ]*: \{0,1\}//
                  T
                  H
                }
            ' "$REPO_DIR/$1/PACKAGES.TXT" | grep -i -- "$CUSTOM_FILTER" \
            | sed -n "
                s/^\([^ ]*\) .*$/\1/
                /^$ALLOWED_FILECHARS\+$/!d;s/^\(.*\)-\([^-]*-[^-]*-[^-]*\)$/\1%\2/p
            " | sort - "$REPO_DIR/$1/$2" | sed -n '
                h
                :loop
                g
                N
                s/^\([^%]*\)%[^-%]*-[^-%]*-[^-%]*\n\(\1-[^-%]*-[^-%]*-[^-%]*%[0-9]*\)$/\2/p
                t loop
                D
            ' > "$TMP/$1.$2.unsplitted"
        ;;
      CustomExactName)
        grep "^$CUSTOM_FILTER%[0-9]*$" "$REPO_DIR/$1/$2" \
            | sed 1q > "$TMP/$1.$2.unsplitted"
        if [ ! -s "$TMP/$1.$2.unsplitted" ]; then
          # Omit build and arch:
          grep "^$CUSTOM_FILTER-[^-]*-[^-]*%[0-9]*$" "$REPO_DIR/$1/$2" \
              | sed 1q > "$TMP/$1.$2.unsplitted"
          if [ ! -s "$TMP/$1.$2.unsplitted" ]; then
            # Omit build, arch and version:
            grep "^$CUSTOM_FILTER-[^-]*-[^-]*-[^-]*%[0-9]*$" "$REPO_DIR/$1/$2" \
                | sed 1q > "$TMP/$1.$2.unsplitted"
          fi
        fi
        ;;
    esac
    # Now we have the list of packages to show. Next split the list to two files:
    sed 's/^.*%//' "$TMP/$1.$2.unsplitted" >> "$TMP/$1.$2.0"      # Line numbers in 'longnames'
    sed 's/%[0-9]*$//' "$TMP/$1.$2.unsplitted" >> "$TMP/$1.$2.1"  # Package names
    rm -f "$TMP/$1.$2.unsplitted"
    # Create the list of version numbers of the installed packages into $TMP/$1.$2.2:
    sort "$TMP/installedlist%" "$TMP/$1.$2.1" | sed -n '
            /%/!{
              s/^.*$/(New)/p
              D
            }
            h
            :loop
            g
            N
            s/^\([^%]*\)%\([^-]*-[^-]*-[^-]*\)\n\1-\2$/(Installed)/p
            t loop
            s/^\([^%]*\)%\([^-]*-[^-]*-[^-]*\)\n\1-[^-%]*-[^-%]*-[^-%]*$/\2/p
            t loop
            D
        ' > "$TMP/$1.$2.2"
    rm -f "$TMP/installedlist" "$TMP/installedlist%"
    # Set checklist entries initially to not selected:
    sed 's/^.*$/"off"/' "$TMP/$1.$2.0" > "$TMP/$1.$2.3"
    # Search an itemhelp for every package to be listed. If no itemhelp line
    # is found then put empty string "". Output must have the very same number
    # of lines as every $TMP/$1.$2.? have.
    sort "$TMP/$1.$2.1" "$REPO_DIR/$1/itemhelp" | sed -n '
            /:/!{
              ${
                # End of file, print an empty line:
                g
                p
                q
              }
              N
              s/^\([^: ]*\)\n\1: \(.*\)$/\2/p
              t success
              /^[^:]*\n/{
                # No itemhelp found, print an empty line:
                x
                P
                x
              }
              :success
              D
            }
        ' | sed 's/.*/"&" \\/' > "$TMP/$1.$2.4"
  fi
  if [ ! -s "$TMP/$1.$2.0" ]; then
    case "$3" in
      Updates) show_msg "No updates available." "NO PACKAGES TO BROWSE" ;;
      CustomExactName) show_msg "Exact package name not found." ;;
      *) show_msg "No packages matching the selected filter." "NO PACKAGES TO BROWSE" ;;
    esac
    return 1
  fi
  paste -d ' ' "$TMP/$1.$2.1" "$TMP/$1.$2.2" "$TMP/$1.$2.3" "$TMP/$1.$2.4" > "$TMP/tmpargs"
  echo "--file \"$TMP/tmpargs\" \\" >> "$TMP/tmpscript"
  echo "2> \"$TMP/tmpanswer\"" >> "$TMP/tmpscript"
}

repository_browse() {
# $1 = Repo nickname ; $2 = shortnames* filename ; $3 = Package list filtering mode
  local HELPITEM
  unset HELPITEM # ash doesn't clear unset the variable with 'local'.
  # Save old item states for the case the user presses Cancel.
  [ -f "$TMP/$1.$2.3" ] && cp "$TMP/$1.$2.3" "$TMP/$1.$2.tmp"
  while : ; do
    repository_create_packagelist_script "$1" "$2" "$3" "$HELPITEM" || break
    . "$TMP/tmpscript"
    EXITSTATUS=$?
    if [ $EXITSTATUS = 2 ]; then # Show detailed package information
      HELPITEM=$(sed 's/HELP //;s/\./\\./g;q' "$TMP/tmpanswer")
      sed -n "/^PACKAGE NAME: *$HELPITEM\.t.. *$/,/^$/{
                s/^[^: ]*: \{0,1\}//
                p
              }" "$REPO_DIR/$1/PACKAGES.TXT" > "$TMP/tmphelp"
      dialog --title "PACKAGE INFORMATION" --exit-label Back --textbox "$TMP/tmphelp" 20 76
      rm -f "$TMP/tmphelp"
      # Update item states file:
      sed 1d "$TMP/tmpanswer" \
          | comm -2 "$TMP/$1.$2.1" - \
          | sed 's/^\t.*$/"on"/;s/^[^"].*$/"off"/' > "$TMP/$1.$2.3"
    elif [ $EXITSTATUS != 0 ]; then # Cancel or escape
      [ -f "$TMP/$1.$2.tmp" ] && cp "$TMP/$1.$2.tmp" "$TMP/$1.$2.3"
      break
    else # Must be OK/Action button
      # Update item states file:
      comm -2 "$TMP/$1.$2.1" "$TMP/tmpanswer" \
          | sed 's/^\t.*$/"on"/;s/^[^"].*$/"off"/' > "$TMP/$1.$2.3"
      # Unofficial repository or official repo updates: Action
      if [ "$2" = "shortnames" -o "$2" = "singlelist" ]; then
        unset HELPITEM
        # In temporary repository (e.g. 'install from current directory') we don not show 'Update':
        if [ "$1" = "Custom@" ]; then
          repository_actions "$1" "$3" || continue
        else
          repository_actions "$1" "$3" show_update || continue
        fi
      fi
      break
    fi
  done
  [ -f "$TMP/$1.$2.tmp" ] && rm -f "$TMP/$1.$2.tmp"
}

repository_create_updatelist() {
# $1 = Repo name ; $2 = Package list filtering mode
  if [ "$2" = "CustomName" -o "$2" = "CustomDesc" ]; then
    sort "$REPO_DIR/$1/shortnames"* > "$REPO_DIR/$1/singlelist"
  else
    for I in "$REPO_DIR/$1/shortnames"*; do
      [ "$I" = "$REPO_DIR/$1/shortnames.pasture" ] && continue
      cat "$I"
    done | sort > "$REPO_DIR/$1/singlelist"
  fi
}

repository_open() {
# $1 = repo nickname ; $2 = Filter name (optional) ; $3 != "" Update database automatically (optional)
  local EXITSTATUS LAST_OPENED_DISKSET
  if [ ! -f "$REPO_DIR/$1/longnames" -o ! -f "$REPO_DIR/$1/PACKAGES.TXT" -o "$3" != "" ]; then
    repository_update "$1" || return
  fi
  if [ "$2" = "" ]; then
    dialog --title "SELECT PACKAGE LIST FILTER" --ok-label 'Open' \
        --extra-button --extra-label 'Update&Open' --menu \
        "Filters 'AlmostAll', 'New' and 'Updates' hide blacklisted packages. The package \
blacklist is in the file /etc/pkgtools/blacklist which you can edit with any \
text editor. The file must have one package basename (no version or arch) \
per line. Invalid lines are ingnored." 16 76 6 \
        "All" "Show all available packages (no filtering)" \
        "AlmostAll" "Hide the exact versions installed and blacklisted packages" \
        "New" "Only packages of which there are no versions installed" \
        "Updates" "Installed packages having a different version available" \
        "CustomName" "Show package names matching a regular expression" \
        "CustomDesc" "Search package descriptions using a regular expression" \
        2> "$TMP/tmpanswer"
    EXITSTATUS=$?
    if [ $EXITSTATUS = 3 ]; then
      repository_update "$1" || return
    elif [ $EXITSTATUS != 0 ]; then
      return
    fi
    PACKAGE_FILTER=$(cat "$TMP/tmpanswer")
  else
    PACKAGE_FILTER=$2
  fi
  if [ "$PACKAGE_FILTER" = "CustomName" -o "$PACKAGE_FILTER" = "CustomDesc" ]; then
    dialog --title "CUSTOM FILTER" --inputbox \
        "Enter the search string (case insensitive):" 8 60 2> "$TMP/tmpanswer"
    [ $? != 0 ] && return
    CUSTOM_FILTER=$(cat "$TMP/tmpanswer")
  fi
  unset LAST_OPENED_DISKSET
  while : ; do
    if [ -f "$REPO_DIR/$1/shortnames" ]; then
      repository_browse "$1" "shortnames" "$PACKAGE_FILTER"
      break
    elif [ "$PACKAGE_FILTER" = "Updates" \
        -o "$PACKAGE_FILTER" = "CustomName" \
        -o "$PACKAGE_FILTER" = "CustomDesc" ]; then
      [ "$PACKAGE_FILTER" = "Updates" ] && repository_create_updatelist "$1" "$PACKAGE_FILTER"
      [ "$PACKAGE_FILTER" = "CustomName" -o "$PACKAGE_FILTER" = "CustomDesc" ] && \
          sort "$REPO_DIR/$1/shortnames"* > "$REPO_DIR/$1/singlelist"
      repository_browse "$1" "singlelist" "$PACKAGE_FILTER"
      rm -f "$REPO_DIR/$1/singlelist"
      break
    else
      rm -f "$TMP/tmpscript"
      for I in $(cd "$ADM_DIR/setup/repositories/$1" ; ls -1 shortnames.* | sed 's/shortnames\.//'); do
        diskset_description "$I" >> "$TMP/tmpscript"
      done
      sort "$TMP/tmpscript" > "$TMP/tmpargs"
      dialog --title "SELECT DISK SET TO BROWSE" --item-help --ok-label Open  \
          --extra-button --extra-label Actions --default-item "$LAST_OPENED_DISKSET" --menu \
          "$1 - $(cat "$REPO_DIR/$1/address")" 20 76 13 --file "$TMP/tmpargs" 2> "$TMP/tmpanswer"
      EXITSTATUS=$?
      if [ $EXITSTATUS = 3 ]; then # Actions
        if [ "$2" = "" ]; then # Show Update command in actions menu only if we do not have filter predefined.
          repository_actions "$1" "$PACKAGE_FILTER" show_update && break
        else
          repository_actions "$1" "$PACKAGE_FILTER" && break
        fi
      elif [ $EXITSTATUS != 0 ]; then # Cancel or escape
        break
      else # Open
        LAST_OPENED_DISKSET=$(cat "$TMP/tmpanswer")
        repository_browse "$1" "shortnames.$(tr A-Z a-z < "$TMP/tmpanswer")" "$PACKAGE_FILTER"
      fi
    fi
  done
  rm -f "$TMP/$1."*
}

repository_validate_nickname() {
# $1 = new repo nickname ; $2 = old repo nickname (optional)
  if [ "$(echo "$1" | sed -n '/^[a-zA-Z0-9_]*$/p')" = "" ]; then
    show_msg "Repository nickname can contain only characters a-z, A-Z, 0-9 and underscore." "ERROR"
    return 1
  elif [ "$1" != "$2" -a -e "$REPO_DIR/$1" ]; then
    show_msg "Repository with nickname '$1' already exists." "ERROR"
    return 1
  elif [ ${#1} -gt 16 ]; then
    show_msg "Repository name is too long. Maximum is 16 characters." "ERROR"
    return 1
  fi
  return 0
}

repository_validate_uri() {
  if ! is_url_dir "$1" && [ "$(echo "$1" | sed -n '/^\/.*/p')" = "" ]; then
    show_msg "Invalid source path or URL." "ERROR"
    return 1
  fi
  return 0
}

repository_prompt_name() {
# $1 = Old repo name (empty if creating a new repo) ; $2 Old URL
  local EXITSTATUS NAME URI SUFFIX GPG
  echo dialog --title \"ADD/EDIT REPOSITORY - NAME\" --max-input 16 \\ > "$TMP/tmpscript"
  [ "$1" ] && echo --extra-button --extra-label Delete \\ >> "$TMP/tmpscript"
  echo "--inputbox \"Please enter a nickname for the package \
repository. The name can be up to 16 characters long and may contain only \
letters, numbers and underscores.\" 10 60 \"$1\" 2> \"$TMP/tmpanswer\"" >> "$TMP/tmpscript"
  while :; do
    . "$TMP/tmpscript"
    EXITSTATUS=$?    # 0=OK ; 3=Delete ; Other=Cancel
    [ $EXITSTATUS = 3 -a -d "$REPO_DIR/$1" ] && rm -rf "$REPO_DIR/$1"
    [ $EXITSTATUS != 0 ] && return 1
    NAME=$(cat "$TMP/tmpanswer")
    repository_validate_nickname "$NAME" "$1" && break
  done
  while :; do
    # Menu to select main category or custom URL:
    cat /usr/share/pkgtools/mirrors.*.name.txt > "$TMP/tmpargs"
    dialog --title "ADD/EDIT REPOSITORY - SOURCE" --menu \
        "You can set repository source either from a mirror list \
or by typing a custom URL." 20 76 12 custom "Custom URL" \
        --file "$TMP/tmpargs" 2> "$TMP/tmpanswer"
    [ $? != 0 ] && return 1
    URI=$(cat "$TMP/tmpanswer")
    if [ "$URI" = "custom" ]; then
      dialog --title "ADD/EDIT REPOSITORY - CUSTOM URL" --inputbox \
          "Enter the absolute path or HTTP/FTP URL to the repository. \
The directory should contain PACKAGES.TXT.gz or PACKAGES.TXT which \
should be formatted according to Slackware specifications.\n\n\
To include username, password or port number within an FTP URL:\n\
ftp://username:password@my.server.tld:1234/pub/packages" \
          13 70 "$2" 2> "$TMP/tmpanswer"
      [ $? != 0 ] && continue
      URI=$(cat "$TMP/tmpanswer")
      repository_validate_uri "$URI" && break
    else
      # Select from mirror list.
      cat "/usr/share/pkgtools/mirrors.$URI.categories.txt" > "$TMP/tmpargs"
      dialog --title "ADD/EDIT REPOSITORY - SUBCATEGORY" --menu \
          "Select subcategory:" 20 76 12 \
          --file "/usr/share/pkgtools/mirrors.$URI.categories.txt" \
          2> "$TMP/tmpanswer"
      [ $? != 0 ] && continue
      SUFFIX=$(cat "$TMP/tmpanswer")
      dialog --title "ADD/EDIT REPOSITORY - MIRROR" --item-help --menu \
          "Select a mirror. It is strongly recommended to select a mirror \
that is geographically close to you, if one is available." 20 76 12 \
          --file "/usr/share/pkgtools/mirrors.$URI.addresses.txt" \
          2> "$TMP/tmpanswer"
      [ $? != 0 ] && continue
      URI=$(sed -n "
              /^$(sed 's/\./\\./g' "$TMP/tmpanswer") /{
                s/^.* \([^ ]\+\) \\\\$/\1/p
                q
              }" \
          "/usr/share/pkgtools/mirrors.$URI.addresses.txt")
      URI="$URI$SUFFIX"
      break
    fi
  done
  dialog --title "ADD/EDIT REPOSITORY - GPG" --yesno \
      "Do you want to use GPG to verify package signatures?" 6 36 \
      && GPG=1 || GPG=0
  if [ -z "$1" ]; then
    mkdir "$REPO_DIR/$NAME" # New repository
  elif [ "$1" != "$NAME" ]; then
    ( cd "$REPO_DIR" && mv "$1" "$NAME" )
  fi
  repository_set_address "$NAME" "$URI"
  if [ $GPG = 1 ]; then
    : > "$REPO_DIR/$NAME/gpg"
  else
    [ -e "$REPO_DIR/$NAME/gpg" ] && rm -f "$REPO_DIR/$NAME/gpg"
  fi
  RETURN_VALUE=$NAME
  return 0
}

repository_set_address() {
# This function checks if the address contains username and password and
# chmods the address file if needed.
# $1 = Repo name ; $2 = New URI
  if is_url_dir "$2" && [ "$(echo "$2" | sed -n '/\/\/[^/]*:[^/]*@/p')" != "" ]; then
    show_msg "URL with password detected. The address file will be chmoded to 0600." "WARNING"
    touch "$REPO_DIR/$1/address"
    chmod 0600 "$REPO_DIR/$1/address"
  fi
  echo "$2" > "$REPO_DIR/$1/address"
}

repository_list() {
# $1 = Preselected filter (optional) If filter is specified Edit and
# Add new are not shown. This is used by QuickUpdate feature.
  local OPENED_REPO=
  while : ; do
    echo dialog --title \"PACKAGE REPOSITORIES\" --ok-label Open \
        --cancel-label Back \\ > "$TMP/tmpscript"
    [ "$1" = "" ] && echo --extra-button \
        --extra-label Edit \\ >> "$TMP/tmpscript"
    [ "$OPENED_REPO" != "" ] \
        && echo --default-item $OPENED_REPO \\ >> "$TMP/tmpscript"
    echo --menu \"Select package repository to view \
        or edit:\" 20 76 13 \\ >> "$TMP/tmpscript"
    for I in $(ls -1 "$REPO_DIR"); do
      [ ! -d "$REPO_DIR/$I" ] && continue
      if [ -f "$REPO_DIR/$I/gpg" ]; then
        echo "$I \"[GPG] $(cat "$REPO_DIR/$I/address")\" \\" >> "$TMP/tmpscript"
      else
        echo "$I \"$(cat "$REPO_DIR/$I/address")\" \\" >> "$TMP/tmpscript"
      fi
    done
    if [ "$1" = "" ]; then
      echo "--- \"Add new\"" \\ >> "$TMP/tmpscript"
    elif ! ls "$REPO_DIR"/* > /dev/null 2> /dev/null; then
      show_msg "Please add at least one repository before using this feature." "ERROR"
      break
    fi
    echo "2> \"$TMP/tmpanswer\"" >> "$TMP/tmpscript"
    . "$TMP/tmpscript"
    EXITSTATUS=$?
    [ $EXITSTATUS = 1 ] && break
    OPENED_REPO=$(cat "$TMP/tmpanswer")
    if [ "$OPENED_REPO" = "---" ]; then # New is created with both "Open" and "Edit".
      repository_prompt_name "" "" || continue # sets NEWREPONAME and NEWREPOURI
      OPENED_REPO=$RETURN_VALUE
    elif [ "$EXITSTATUS" = "0" ]; then # Open
      rm -f "$REPO_DIR/$OPENED_REPO/singlelist" "$TMP/$OPENED_REPO."* # Delete repo's temp files.
      if [ "$1" = "" ]; then
        repository_open "$OPENED_REPO"
      else
        repository_open "$OPENED_REPO" "$1" with_database_update
        break
      fi
    elif [ "$EXITSTATUS" = "3" ]; then # Edit
      repository_prompt_name "$OPENED_REPO" \
          "$(cat "$REPO_DIR/$OPENED_REPO/address")" || continue
      OPENED_REPO=$RETURN_VALUE
    fi
  done
}

# End of functions.pkgtool_repository.sh

