# functions.installer.sh - setup program specific part of pkgtool
#
# See the file `COPYRIGHT' for copyright and license information.
#

diskset_recommended_choice() {
# $1 = diskset name
  grep -iq "^$1$" << EOF
A
AP
C
D
F
KDE
L
N
TCL
X
XAP
EOF
}

slackinstall_create_repository() {
  # Create repository 'InstallSource' for installation:
  rm -rf "$REPO_DIR/InstallSource"
  mkdir -m 0755 -p "$REPO_DIR/InstallSource"
  echo "$1" > "$REPO_DIR/InstallSource/address"
  [ -n "$2" ] && : > "$REPO_DIR/InstallSource/gpg"
  repository_update InstallSource || exit_pkgtool 1
  # If it is not an official like repository, quit:
  [ ! -f "$REPO_DIR/InstallSource/shortnames.a" ] && exit_pkgtool 1
  # Remove unwanted source directory information:
  rm -f "$REPO_DIR/InstallSource/shortnames.extra" \
        "$REPO_DIR/InstallSource/shortnames.testing" \
        "$REPO_DIR/InstallSource/shortnames.pasture"
  # Ask which disksets user wants to install:
  cat << EOF > "$TMP/tmpscript"
dialog --title "PACKAGE SERIES SELECTION" --separate-output --item-help --checklist \\
"Now it's time to select which general categories of software \\
to install on your system. \\
Use the spacebar to select or unselect the software you wish to install. \\
You can use the up and down arrows to see all the possible choices. \\
Recommended choices have been preselected. \\
Press the ENTER key when you are finished." \\
20 75 9 \\
EOF
  rm -f "$TMP/all_disksets"
  for J in $(ls -1 "$REPO_DIR/InstallSource/shortnames."* | sed 's,^.*/shortnames\.,,'); do
    echo "$J" >> "$TMP/all_disksets"
    if diskset_recommended_choice "$J"; then
      diskset_description "$J" | sed 's/" "/" "on" "/' >> "$TMP/tmpscript"
    else
      diskset_description "$J" | sed 's/" "/" "off" "/' >> "$TMP/tmpscript"
    fi
  done
  echo "2> \"$TMP/tmpanswer\"" >> "$TMP/tmpscript"
  . "$TMP/tmpscript"
  if [ $? != 0 ]; then
    rm -f "$TMP/all_disksets"
    exit_pkgtool 1
  fi
  # Remove shortnames.* and InstallSource.* which were not selected:
  for J in $(tr A-Z a-z < "$TMP/tmpanswer" | sort - "$TMP/all_disksets" | uniq -u ); do
    rm -f "$REPO_DIR/InstallSource/shortnames.$J" "$TMP/InstallSource.$J."*
  done
  rm -f "$TMP/all_disksets"
  # Quit if nothing was selected:
  ls "$REPO_DIR/InstallSource/shortnames."* > /dev/null 2> /dev/null || exit_pkgtool 1
  # Installation type:
  while : ; do
    TAGFILEPATH=$1/slackware
    TAGFILEEXT=""
    dialog --title "SELECT PROMPTING MODE" --menu \
      "The 'full' will install all the packages (except which are \
marked 'skip' in the tagfiles) and will take about 2-3 gigabytes \
in case you selected all the package series from the previous \
screen. The 'full' is the easiest and by far most foolproof choice, \
and therefore recommended if you have the disk space. \n\n\
If you like to select individual packages use 'novice' or 'expert' \
to get interactive menus. The 'novice' automatically selects the \
required packages and hides packages marked 'required' or 'skip' in \
the tagfiles, thus trying to prevent unusable installation." \
      20 76 4 \
      "full"   "No prompts: install required, recommended and optional packages" \
      "novice" "Menu: show only packages marked recommended or optional" \
      "expert" "Menu: show all the packages available for installation" \
      "custom" "Use custom tagfiles (experts only)" \
      2> "$TMP/tmpanswer"
    [ $? != 0 ] && exit_pkgtool 1
    REPLY=$(cat "$TMP/tmpanswer")
    [ "$REPLY" != "custom" ] && break
    dialog --title "ENTER PATH TO TAGFILES" --inputbox \
      "There must be a directory for every diskset and tagfile like in Slackware tree on \
the FTP site. Tagfiles should be named e.g. 'xap/tagfile' or 'xap/tagfile.ext' \
where 'ext' can be any filename extension you like to use. You will be prompted for tagfile \
extension in the next screen.\n\n\
Path to tagfiles?" 14 65 "$TAGFILEPATH" 2> "$TMP/tmpanswer"
    [ $? != 0 ] && continue
    TAGFILEPATH=$(cat "$TMP/tmpanswer")
    [ -z "$TAGFILEPATH" ] && continue
    dialog --title "ENTER TAGFILE EXTENSION" --inputbox \
      "You may have multiple tagfiles for different types of installation in \
the same location if you use a different filename extension for the tagfiles. \
E.g. if you have 'a/tagfile.foo', 'ap/tagfile.foo' etc. enter here 'foo' to \
use those tagfiles. Leave this empty if you don not want to use an extension \
(files are named 'a/tagfile' etc.).\n\n\
Filename extension of the tagfiles?" 15 65 2> "$TMP/tmpanswer"
    [ $? != 0 ] && continue
    TAGFILEEXT=$(cat "$TMP/tmpanswer")
    # Fix extension dot: '.foo' or 'foo' => '.foo':
    [ -n "$TAGFILEEXT" ] && TAGFILEEXT=".${TAGFILEEXT#.}"
    break
  done
  # Get the tagfiles and create package list scripts.
  show_info "Getting and processing tagfiles..." "PLEASE WAIT"
  if is_url_dir "$TAGFILEPATH"; then
    INSTALL_SOURCE_TYPE=network
  else
    INSTALL_SOURCE_TYPE=local
  fi
  for J in $(ls -1 "$REPO_DIR/InstallSource/shortnames."* | sed 's,^.*/shortnames\.,,'); do
    repository_create_packagelist_script InstallSource "shortnames.$J" All
    if [ "$INSTALL_SOURCE_TYPE" = "local" ]; then
      cat "$TAGFILEPATH/$J/tagfile$TAGFILEEXT" > "$REPO_DIR/InstallSource/tagfile.$J" 2> /dev/null
    else
      download "$TAGFILEPATH/$J/tagfile$TAGFILEEXT" "$REPO_DIR/InstallSource/tagfile.$J" > /dev/null 2> /dev/null
    fi
    if [ $? != 0 ]; then
      show_msg "Error copying tagfiles." "ERROR"
      exit_pkgtool 1
    fi
    # Add Required/Recommended/Optional/Skip to the place were normally is installed version:
    sed 's,^\(.*\)-[^-]*-[^-]*-[^-]*$,\1:,' "$TMP/InstallSource.shortnames.$J.1" > "$TMP/foo1"
    sed '/^#/d;/^ *$/d' "$REPO_DIR/InstallSource/tagfile.$J" > "$TMP/foo2"
    # FIXME: IIRC the sed script below misbehaves if tagfile has no entry for the very last package.
    sort "$TMP/foo1" "$TMP/foo2" | sed -n '
            1{
              # Put "" to the hold space, we will use it if no tag is found.
              x
              s/^.*$/""/
              x
            }
            /:$/!D
            # If we are processing the last line and it does not have
            # a corresponding tagfile entry:
            ${
              x
              p
              q
            }
            N
            s/^\(.*\):\n\1: *\([a-zA-Z]\{3\}\) *$/\2/
            t found
            # No tag for this package was found. Print "" from hold space:
            x
            p
            x
            D
            :found
            s/^[Aa][Dd][Dd]$/"* REQUIRED"/p
            s/^[Rr][Ee][Cc]$/"- Recommended"/p
            s/^[Oo][Pp][Tt]$/"  Optional"/p
            s/^[Ss][Kk][Pp]$/"  (Skip)"/p
            d
        ' > "$TMP/InstallSource.shortnames.$J.2"
    if [ "$REPLY" = "full" ]; then
      sed -n '/\(^#\|SKP\)/d;s/\([^: ]*\): *[a-zA-Z]*$/\1/p' \
          "$REPO_DIR/InstallSource/tagfile.$J" | sort -u > "$TMP/tagged"
    else
      sed -n '/\(^#\|SKP\|OPT\)/d;s/\([^: ]*\): *[a-zA-Z]*$/\1/p' \
          "$REPO_DIR/InstallSource/tagfile.$J" | sort -u > "$TMP/tagged"
    fi
    # This might bug badly if there is more than one version available for installation: :-(
    sed 's,-[^-]*-[^-]*-[^-]*$,,' "$TMP/InstallSource.shortnames.$J.1" \
        | comm -2 - "$TMP/tagged" \
        | sed 's/^\t.*$/"on"/;s/^[^"].*$/"off"/' \
        > "$TMP/InstallSource.shortnames.$J.3"
    # In novice mode we remove ADD and SKP packages from the listing:
    if [ "$REPLY" = "novice" ]; then
      paste "$TMP/InstallSource.shortnames.$J.0" "$TMP/InstallSource.shortnames.$J.2" \
          | sed -n 's/^\(.*\)\t"\(\* REQUIRED\|  (Skip)\)"$/\1/p' \
          >> "$TMP/InstallSource.shortnames.hidden@.0"
      sed 's/^.*$/"on"/' "$TMP/InstallSource.shortnames.hidden@.0" \
          > "$TMP/InstallSource.shortnames.hidden@.3"
      for K in 0 1 3 4 2; do
        paste "$TMP/InstallSource.shortnames.$J.$K" "$TMP/InstallSource.shortnames.$J.2" \
            | sed -n 's/^\(.*\)\t"\(- Recommended\|  Optional\)"$/\1/p' > "$TMP/foo1"
        mv "$TMP/foo1" "$TMP/InstallSource.shortnames.$J.$K"
      done
    fi
    # Tiny progress bar ;-)
    echo -n .
  done
  rm -f "$TMP/tagged" "$TMP/foo1" "$TMP/foo2"
}

slackinstall_check_for_disk_full() {
  [ ! -d "$ROOT/bin" -a ! -d "$ROOT/etc" ] && exit_pkgtool 1 # if there no Linux here, exit
  # Test writing a 256K file and assume if it returns an error
  # that it means the drive filled up
  if ! dd if=/dev/zero of="$TMP/SeTtestfull" bs=1024 count=256 1> /dev/null 2> /dev/null; then
    dialog --title "ERROR: TARGET PARTITION FULL" --msgbox "Setup has \
detected that one or more of your target partitions has become full.  \
I'm sorry, but you will have to try installing again onto a partition \
or partitions with more free space.  You could also try selecting \
fewer packages to \
install.  Since there is no longer any space for setup to make its \
temporary files, this is an unrecoverable error.  Press control-alt-delete \
to reboot and try again.  Before doing that, you might want to switch to \
another console (Alt-F2) and use df (disk free utility) to see if you \
can get an idea of how to avoid this the next time around."  15 65
    exit_pkgtool 1
  fi
  rm -f "$TMP/SeTtestfull"
}

slackinstall_run_setup_scripts() {
# $1 = root device
  # Post installation and setup scripts added by packages.
  [ ! -d "$ROOT/proc" ] && mkdir -p "$ROOT/proc"
  mount -t proc proc "$ROOT/proc"
  if [ -d "$ROOT/var/log/setup" ]; then
    (
      cd "$ROOT"
      unset ROOT  # E.g. lilo reads ROOT environment variable.
      for INSTALL_SCRIPTS in var/log/setup/setup.* ; do
        SCRIPT=$(basename "$INSTALL_SCRIPTS")
        # install-kernel is deprecated:
        [ "$SCRIPT" = "setup.70.install-kernel" ] && continue
        # We hopefully have a bit better tools on the target partition.
        # E.g. BusyBox' grep doesn't support -w which is used by
        # some Slackware's scripts. :(
        # Here, we call each script in /var/log/setup. Two arguments are provided:
        # 1 -- the target prefix (normally /, but /mnt from the bootdisk)
        # 2 -- the name of the root device.
        chroot . /bin/sh "var/log/setup/$SCRIPT" / "$1"
        if echo "$SCRIPT" | fgrep -q onlyonce; then # only run after first install
          [ ! -d var/log/setup/install ] && mkdir var/log/setup/install
          mv -f "$INSTALL_SCRIPTS" var/log/setup/install
        fi
      done
      # Offer the user to rerun scripts e.g. if installing boot
      # loader had failed. This is now implemented in the laziest
      # way (copypasted a bit from functions.pkgtool_misc.sh).
      dialog --title 'DOES ANY SCRIPT NEED TO BE RERUN?' --yesno \
"In case something went wrong e.g. boot manager didn't install properly, \
you may want to rerun one or more of the setup scripts.\\n\\n\
Do you want to rerun any of the setup scripts?" 9 60
      if [ $? = 0 ]; then
        echo 'dialog --title "SELECT SYSTEM SETUP SCRIPTS" --separate-output --item-help --checklist \
"Please use the spacebar to select the setup scripts to run.  Hit enter when you \
are done with selecting the scripts." 20 76 12 \' > "$TMP/setupscr"
        for INSTALL_SCRIPTS in var/log/setup/setup.* ; do
          SCRIPT=$(echo "$INSTALL_SCRIPTS" | sed 's|^.*/setup\.||')
          [ "$SCRIPT" = "70.install-kernel" ] && continue
          BLURB=`grep '#BLURB' "$INSTALL_SCRIPTS" | cut -b8-`
          if [ "$BLURB" = "" ]; then
            BLURB="\"\""
          fi
          echo " \"`echo "$SCRIPT" | cut -f2- -d .`\" $BLURB \"no\" $BLURB \\" >> "var/log/setup/tmp/setupscr"
        done
        echo "2> \"var/log/setup/tmp/return\"" >> "var/log/setup/tmp/setupscr"
        . "var/log/setup/tmp/setupscr"
        if [ -s "var/log/setup/tmp/return" ]; then
          # Run each script:
          for SCRIPT in $(cat "var/log/setup/tmp/return") ; do
            chroot . /bin/sh "var/log/setup/setup.$SCRIPT" / "$1"
          done
        fi
      fi
      rm -f "var/log/setup/tmp/return" "var/log/setup/tmp/setupscr"
    )
  fi
  umount "$ROOT/proc"
}

slackinstall_copy_keyboard_config() {
  if [ -x /etc/rc.d/rc.keymap ]; then
    cp /etc/rc.d/rc.keymap "$ROOT/etc/rc.d/rc.keymap"
    chmod 0755 "$ROOT/etc/rc.d/rc.keymap"
  fi
}

slackinstall_create_cdrom_symlinks() {
  # Figure out how to set the /dev/cdrom and/or /dev/dvd symlinks.  Everything seems to
  # report itself as a DVD-ROM, so don't blame me.  Without asking what's what, all we can
  # do here is guess.  It's a better guess than before, though, as now it takes ide-scsi
  # into account.
  if dmesg | grep "ATAPI CD" 1> /dev/null 2> /dev/null ; then
    dmesg | grep "ATAPI CD" | while read device ; do
      shortdev=$(echo $device | cut -f 1 -d :)
      if grep -w "$shortdev=ide-scsi" "$ROOT/etc/lilo.conf" 1> /dev/null 2> /dev/null ; then
        shortdev=sr0
      fi
      ( cd "$ROOT/dev"
        rm -f cdrom dvd
        ln -sf "/dev/$shortdev" cdrom
        ln -sf "/dev/$shortdev" dvd
      )
      # Rather than keep overwriting the devices, quit keeping only links to the first
      # device found.  "Real" users will use the actual devices instead of silly links
      # anyway.  ;-)
      break
    done
  fi
}

slackinstall_set_root_password() {
  while [ "$(fgrep 'root:' "$ROOT/etc/shadow" | cut -f 2 -d :)" = "" ]; do
    # There is no root password
    dialog --title "WARNING: NO ROOT PASSWORD DETECTED" --yesno "There is \
currently no password set on the system administrator account (root).  \
It is recommended that you set one now so that it is active the first \
time the machine is rebooted.  This is especially important if you're \
using a network enabled kernel and the machine is on an Internet \
connected LAN.  Would you like to set a root password?" 10 68
    if [ $? = 0 ] ; then
      echo
      echo
      echo
      chroot "$ROOT" /usr/bin/passwd root
      echo
      echo -n "Press [enter] to continue:"
      read REPLY
      echo
      # Here we drop through, and if there's still no password the menu
      # runs again.
    else
      # Don't set a password:
      break
    fi
  done
}

slackinstall_create_fstab() {
# $1 = root device
  local REPLACE_FSTAB
  REPLACE_FSTAB=Y
  if [ -r "$ROOT/etc/fstab" ]; then
    dialog --title "REPLACE /etc/fstab?" --yesno "You already have an \
/etc/fstab on your install partition.  If you were just adding software, \
you should probably keep your old /etc/fstab.  If you've changed your \
partitioning scheme, you should use the new /etc/fstab.  Do you want \
to replace your old /etc/fstab with the new one?" 10 58
    [ $? != 0 ] && REPLACE_FSTAB=N
  fi
  if [ "$REPLACE_FSTAB" = "Y" ]; then
    if [ -r "$TMP/SeTfstab" ]; then
      cat "$TMP/SeTfstab" > "$ROOT/etc/fstab"
    else
      # No partition info available, guess something and warn user:
      printf "%-11s %-11s %-11s %-27s %-2s %s\n" "$1" "/" "reiserfs" "noauto,owner,ro" "1" "1" > "$ROOT/etc/fstab"
      dialog --title "WARNING" --msgbox "The file /etc/fstab will be \
created but very probably needs manual tweaking. Edit fstab before trying \
to boot your new installation! " 7 60
    fi
    cat << "EOF" >> "$ROOT/etc/fstab"
/dev/cdrom  /mnt/cdrom  iso9660     noauto,owner,ro             0  0
/dev/fd0    /mnt/floppy auto        noauto,owner                0  0
devpts      /dev/pts    devpts      gid=5,mode=620              0  0
proc        /proc       proc        defaults                    0  0
#shm         /dev/shm    tmpfs       defaults                    0  0
EOF
  fi
}

slackinstall_select_kernel24() {
  # Here's the default kernel install location:
  VMLINUZ="$ROOT/boot/vmlinuz"
  # Detect if we have 2.4 kernel i.e. we are installing Slackware:
  grep -q 'slackware/a/kernel-ide-2.4' "$REPO_DIR/InstallSource/longnames" || return 0
  # Check for newer kernel in patches:
  BZIMAGE_DIRECTORY="$1/kernels"
  grep -q 'slackware/a/../../patches/packages/kernel-ide-2.4' \
      "$REPO_DIR/InstallSource/longnames" && BZIMAGE_DIRECTORY="$1/patches/kernels"
  # Ask for the kernel image and try to download/copy it:
  while : ; do
    dialog --title "SELECT THE KERNEL IMAGE" --cancel-label Skip --menu \
"All IDE (*.i) kernels support IDE hard drives and CD-ROM drives, plus \
additional support listed below. All SCSI (*.s) kernels feature full \
IDE hard drive and CD-ROM drive support, plus additional SCSI drivers. \
See /bootdisks/README.TXT on you Slackware FTP mirror for more complete \
list which devices are supported by these kernels.\n\n\
To use whatever kernel that is already installed (such as a generic \
kernel from the A series) press <Skip>." 20 76 6 \
bare.i     "Most IDE based PCs (this is usually the right choice)" \
bareacpi.i "bare.i but instead of APM contains support for ACPI" \
ataraid.i  "IDE RAID: 3ware, Promise Fasttrak(tm), Highpoint 370" \
old_cd.i   "Support for old non-IDE and non-SCSI CD-ROM drives" \
pportide.i "Support for parallel-port IDE devices" \
sata.i     "Promise, Silicon Image, SiS, ServerWorks, VIA, Vitesse" \
adaptec.s  "Most Adaptec SCSI controllers including RAID" \
ibmmca.s   "IBM MCA (MicroChannel Architechture) support" \
jfs.s      "bare.i + IBM's Journaled Filesystem + AIC7xxx SCSI" \
raid.s     "Older AMI Megaraid, Compaq Smart Array, IBM, LSI, Mylex" \
scsi.s     "AM53,BusLogic,DPT&EATA/DMA,Initio,SYM53C8XX,QlogicISP/QLA" \
scsi2.s    "AdvanSys, ACARD, AMI, Compaq, Domex, DTC, Future, NCR53*" \
scsi3.s    "WD,Always,Intel/ICP,PCI2xx0i,PSI240i,Qlogic FAS&ISP2100" \
speakup.s  "bare.i + Speakup + Adaptec AIC7xxx SCSI" \
xfs.s      "bare.i + SGI's XFS + Adaptec AIC7xxx SCSI" \
zipslack.s "Kernel used on ZipSlack" \
    2> "$TMP/tmpanswer"
    [ $? != 0 ] && return 0
    if [ "$(echo "$BZIMAGE_DIRECTORY" | sed -n 's/^\(http\|ftp\):\/\/.*$/\1/p')" = "" ]; then
      cp -v "$BZIMAGE_DIRECTORY/$(cat "$TMP/tmpanswer")/bzImage" "$VMLINUZ.incoming"
    else
      download "$BZIMAGE_DIRECTORY/$(cat "$TMP/tmpanswer")/bzImage" "$VMLINUZ.incoming"
    fi
    if [ $? != 0 ]; then
      echo
      echo "An error occurred while copying the bzImage."
      echo "Press [enter] to return to the menu."
      read REPLY
    else
      rm -f "$VMLINUZ"
      mv "$VMLINUZ.incoming" "$VMLINUZ"
      break
    fi
  done
}

slackinstall_main() {
# $1 = Source path/URL ; $2 = root device (e.g. /dev/hda1) ; $3 = use GPG if non-empty
  MODE=dialog
  DIALOGOPTS="--backtitle \"Tukaani Installer\""
  export DIALOGOPTS
  if [ "$ROOT" = "" ]; then
    show_msg "You must explicitly use \$ROOT or --root." "ERROR"
    exit_pkgtool 1
  fi
  repository_validate_uri "$1" || exit_pkgtool 1
  if [ ! -b "$2" ]; then
    show_msg "Root device node does not exists or is not a valid block device." "ERROR"
    exit_pkgtool 1
  fi
  slackinstall_create_repository "$1" "$3"
  if [ "$REPLY" = "full" ]; then
    # If full installation is selected, no more menus are shown:
    repository_actions_install "InstallSource" install
  else
    # Novice/Expert/Tagfiles show the packages in menus before installing:
    repository_open "InstallSource" All
  fi
  slackinstall_check_for_disk_full
  # Run ldconfig:
  if [ -x "$ROOT/sbin/ldconfig" ]; then
    show_info "Running /sbin/ldconfig..." "PLEASE WAIT"
    chroot "$ROOT" /sbin/ldconfig > /dev/null 2> /dev/null
  fi
  # Only ask if we want to skip configuring if we suspect the user should
  # skip the step:
  if [ -r "$ROOT/etc/fstab" ]; then
    dialog --title "CONFIGURE THE SYSTEM" --yesno "Now we can configure your \
Linux system.  If this is a new installation, you MUST configure it now or it \
will not boot correctly.  However, if you are just adding software to an \
existing system, you can back out to the main menu and skip this step.  \
However (important exception) if you've installed a new kernel image, it's \
important to reconfigure your system so that you can install LILO (the Linux \
loader) or create a bootdisk using the new kernel.  You want to CONFIGURE \
your system, right?" 0 0
    [ $? != 0 ] && exit_pkgtool 0
  fi
  slackinstall_select_kernel24 "$1"
  slackinstall_run_setup_scripts "$2"
  slackinstall_copy_keyboard_config
  slackinstall_create_cdrom_symlinks
  slackinstall_set_root_password
  slackinstall_create_fstab "$2"
  exit_pkgtool 0
}
