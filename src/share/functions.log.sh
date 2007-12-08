# functions.log.sh
#
# See the file `COPYRIGHT' for copyright and license information.
#

log_line() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$ADM_DIR/pkgtools"
}

log_pipe() {
  sed "s#^#$(date '+%Y-%m-%d %H:%M:%S') " >> "$ADM_DIR/pkgtools"
}

# Eof of functions.log.sh

