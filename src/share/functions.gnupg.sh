# functions.gnupg.sh
#
# See the file `COPYRIGHT' for copyright and license information.
#
# gnupg_verify_signature <path/to/package.ext> [quiet]
#

gnupg_verify_signature() {
  if [ ! -f "$1" -o ! -f "$1.asc" ]; then
    echo "BUG: gnupg_verify_signature called for non-existing file."
    return 97 # It is much safer to return than "exit".
  fi
  if ! type gpgv > /dev/null 2> /dev/null; then
    echo "ERROR: GnuPG is not installed. Unable to verify GPG signature."
    return 5
  fi
  [ -z "$QUIET$2" ] && echo -n "Verifying the GPG signature..."
  gpgv --keyring "${GNUPGHOME:-/root/.gnupg}/pubring.gpg" \
      "$1.asc" > /dev/null 2> /dev/null
  case $? in
    0)  # Good signature.
      [ -z "$QUIET$2" ] && echo " OK"
      return 0
      ;;
    1)  # Invalid signature. Package should not be installed.
      [ -z "$QUIET$2" ] && echo " INVALID"
      return 1
      ;;
    2)  # Other error. Usually in this case there is no matching key in pubring.gpg.
      if [ -z "$QUIET$2" ]; then
        echo " Error"
        echo "Unable to verify the GPG signature of $(basename "$1")."
        echo "It is probably signed with key that is not in the local keyring file."
      fi
      return 2
      ;;
  esac
}

# End of functions.gnupg.sh

