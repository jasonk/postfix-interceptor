#!/bin/bash
# 1997 Jason Kohles <email@jasonkohles.com> http://www.jasonkohles.com/

#### CONFIGURATION ####
# WORK_DIR is a temporary directory where this script can save the
# message while it is operating on it.
if [ -z "$WORK_DIR" ]; then
  WORK_DIR='/var/spool/interceptor'
fi
# INTERCEPTORS is a directory that will be searched for executable
# filters based on the sender address.
if [ -z "$INTERCEPTORS" ]; then
  INTERCEPTORS='/etc/postfix/interceptors'
fi
if [ -z "$SENDMAIL" ]; then
  SENDMAIL='/usr/sbin/sendmail'
fi

# If this script exits with EX_TEMPFAIL then that means that something
# went wrong that prevented the filtering from happening.  In this
# case postfix will put the incoming message into the deferred mail
# queue and try running the filter again later.
EX_TEMPFAIL=75

MY_DIR="$WORK_DIR/interceptor-$$"
# Clean up when done or when aborting.
if [ -z "$SKIP_CLEANUP" ]; then trap 'rm -rf $MY_DIR' 0 1 2 3 15; fi

function fail() { echo "$@"; exit $EX_TEMPFAIL; }

# Start processing.
mkdir -p "$MY_DIR" || fail "Cannot create $MY_DIR"
cd "$MY_DIR" || fail "'$MY_DIR' does not exist"

sender="$1" ; shift 1

cat > "message.txt" || fail "Cannot save mail"
echo "$sender" > "sender.txt" || fail "Cannot save sender"
echo "$@" | xargs -n1 > "recipients.txt" || fail "Cannot save recipients"

formail -fX '' < message.txt > headers.txt
formail -fI '' < message.txt > content.txt
formail -fczx subject < message.txt > subject.txt || true
md5sum *.txt > checksums.txt

name="$(echo "$sender" | tr -cs '[:alnum:]' '-')"
name="${name%%-}"
name="${name##-}"

function unmodified() {
  grep -w "$1.txt" "checksums.txt" | md5sum --check --status
}
function modified() {
  ! unmodified "$1"
}

echo "$INTERCEPTORS/$name"
if [ -x "$INTERCEPTORS/$name" ]; then
  interceptor="$INTERCEPTORS/$name"
elif [ -x "$INTERCEPTORS/default" ]; then
  interceptor="$INTERCEPTORS/default"
else
  interceptor=""
fi

if [ -n "$interceptor" ]; then
  "$interceptor" || fail "Filter $interceptor failed"
fi

# If any of the sender, recipients, or message files have been removed
# or emptied then we discard the message
if [ ! -s sender.txt ]; then exit 0; fi
if [ ! -s recipients.txt ]; then exit 0; fi
if [ ! -s message.txt ]; then exit 0; fi

if modified headers || modified content; then
  {
    cat headers.txt
    echo ''
    cat content.txt
  } > message.txt
fi

if modified subject; then
  cp message.txt temp.txt
  formail -fi "Subject: $(head -1 subject.txt)" < temp.txt > message.txt
fi

if modified sender; then
  sender="$(head -1 sender.txt)"
  if [ -z "$sender" ]; then exit; fi
fi

# NEVER include `-t` in the sendmail args!
SENDMAIL_ARGS=( -i -G -f "$sender" )

SENDMAIL_ARGS+=( -- )
if modified recipients; then
  FOUND_RECIPIENTS=0
  while IFS= read -r EMAIL; do
    let FOUND_RECIPIENTS++
    SENDMAIL_ARGS+=( "$EMAIL" )
  done < recipients.txt
  # If no recipients were found then discard the message
  if [ $FOUND_RECIPIENTS -eq 0 ]; then exit; fi
else
  SENDMAIL_ARGS+=( "$@" )
fi

exec "$SENDMAIL" "${SENDMAIL_ARGS[@]}" < message.txt
