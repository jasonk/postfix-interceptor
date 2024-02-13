#!/bin/bash
cd "$(dirname "$0")"

export WORK_DIR="$(pwd)/temp-work-data"
export SKIP_CLEANUP=true
export HOME="$(pwd)"
export SENDMAIL="$HOME/test-sendmail"
export INTERCEPTORS="$HOME/test-interceptors"

mkdir -p "$WORK_DIR"
rm -rf "$WORK_DIR"/*

./interceptor-filter.sh \
  dev-test-thing@mindwell.com jason@mindwell.com jason-bcc@mindwell.com \
  < test-mail.txt

cd "$WORK_DIR"/* || exit 1

function check() {
  if $@; then
    echo "OK: $@"
  else
    echo "FAIL: $@"
  fi
}
function sum_is() {
  grep -w "$1.txt" checksums.txt | egrep -q "^$2 "
}
function unmodified() {
  grep -w "$1.txt" "checksums.txt" | md5sum --check --status
}
function modified() {
  ! unmodified "$@"
}
function contains() {
  grep -q "$1" ./test-sendmail.txt
}
function lines() {
  [ "$(wc -l "$1.txt" | awk '{print $1}')" -eq "$2" ]
}

if [ ! -f test-sendmail.txt ]; then
  echo "#### MESSAGE DISCARDED ####"
  exit 1
fi

check sum_is content 'f8028289a611adfe44fd972aeac045d3'
check sum_is headers 'a56438d4a43d5abcf7a775b7c4ae8a4d'
check sum_is message 'f0b88d5354d4bf6d97c9a496b292ec93'
check sum_is recipients '6a985a29ac5360dc2b242da0d4c03243'
check sum_is sender 'ca500003c6958e966769a0b128e0449d'
check sum_is subject '92c510833234505a0b7708a23e97a1f1'

check modified content
check modified headers
check modified recipients
check modified subject

check lines recipients 1
check lines subject 1
check contains content 'support@mindwell.com'
check contains headers 'X-Dev-Env:'

echo "#### RESULTS ####"
cat test-sendmail.txt
