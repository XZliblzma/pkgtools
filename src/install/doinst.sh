config_new() {
	# If there's no config file by that name, mv it over:
	if [ ! -e "$1" ]; then
		mv -f "$1.new" "$1"
	# Using 'md5sum' instead of 'cmp' to compare files, because it
	# is possible that the diffutils package is not installed:
	elif [ "$(md5sum < "$1")" = "$(md5sum < "$1.new")" ]; then
		# Remove the redundant copy:
		rm -f "$1.new"
	fi
	# Otherwise, we leave the .new copy for the admin to consider...
}

config_new etc/pkgtools/blacklist
config_new etc/pkgtools/config

# Create a symlink tar-1.13-pkgtools->tar-1.13 if and only if tar-1.13
# does not exist. We don't want to overwrite the original tar-1.13 if it
# exist but it also has to exist to keep upgrades/downgrades working
# perfectly between pkgtools versions (including Tukaani<->Slackware).
if [ ! -e bin/tar-1.13 ]; then
( cd bin ; rm -rf tar-1.13 )
( cd bin ; ln -sf tar-1.13-pkgtools tar-1.13 )
fi

# Use framebuffer by default if no XF86Config is found:
if [ ! -r etc/X11/XF86Config -a -r etc/X11/XF86Config-vesa ]; then
  cp -a etc/X11/XF86Config-vesa etc/X11/XF86Config
fi
# Use framebuffer by default if no xorg.conf is found:
if [ ! -r etc/X11/xorg.conf -a -r etc/X11/xorg.conf-vesa ]; then
  cp -a etc/X11/xorg.conf-vesa etc/X11/xorg.conf
fi

# Links for backwards compatibility:
( cd sbin ; rm -rf explodepkg )
( cd sbin ; ln -sf ../usr/bin/explodepkg explodepkg )
( cd sbin ; rm -rf upgradepkg )
( cd sbin ; ln -sf ../usr/sbin/upgradepkg upgradepkg )
( cd sbin ; rm -rf removepkg )
( cd sbin ; ln -sf ../usr/sbin/removepkg removepkg )
( cd sbin ; rm -rf installpkg )
( cd sbin ; ln -sf ../usr/sbin/installpkg installpkg )
( cd sbin ; rm -rf makepkg )
( cd sbin ; ln -sf ../usr/bin/makepkg makepkg )
( cd sbin ; rm -rf pkgtool )
( cd sbin ; ln -sf ../usr/sbin/pkgtool pkgtool )
( cd usr/bin ; rm -rf xwmconfig )
( cd usr/bin ; ln -sf config-xwm xwmconfig )
( cd usr/man/man1 ; rm -rf xwmconfig.1.gz )
( cd usr/man/man1 ; ln -sf config-xwm.1.gz xwmconfig.1.gz )
