#!/bin/bash
#
# Alex Wicks, 2021
# github.com/jesusdf
#

printf "\e[32m
    ___      ___      ___       __      ___      ___       __       __      ___      ___    __  ___ 
  //   ) ) //   ) ) //___) ) //   ) ) //   ) ) //   ) ) //   ) ) //   ) ) //___) ) //   ) )  / /    
 //   / / //___/ / //       //   / / //       //   / / //   / / //   / / //       //        / /     
((___/ / //       ((____   //   / / ((____   ((___/ / //   / / //   / / ((____   ((____    / /      
\e[0m\n"

# Test for presence of required vars
if [ -z "${TUN_DEVICE}" ]
then
  printf "\e[31m\$WARNING: TUN_DEVICE is not set, using tun127 by default.\e[0m\n"
  TUN_DEVICE=tun127
fi
printf "\e[33mTun device name:\e[0m %s\n" "${TUN_DEVICE}"

if [ -z "${URL}" ]
then
  printf "\e[31m\$URL is not set\n\e[0m" 
  exit 1
fi
printf "\e[33mURL:\e[0m %s \n" "${URL}"

if [ -z "${USER}" ]
then
  printf "\e[31m\$USER is not set\e[0m\n"
  exit 2
fi
printf "\e[33mUsername:\e[0m %s\n" "${USER}"

if [ -z "${PASS}" ]
then
  printf "\e[31m\$PASS is not set\e[0m\n"
  exit 3
fi
printf "\e[33mPassword:\e[0m [REDACTED]\n\n"

if [ -z "${SPLICE_ARGS}" ]
then
  printf "\e[31m\$SPLICE_ARGS is not set\e[0m\n"
  exit 2
fi
printf "\e[33mSplice parameters:\e[0m %s\n" "${SPLICE_ARGS}"

if [ -z "${MIN_SESSION_TIME}" ]
then
  MIN_SESSION_TIME=600
fi

if [ -z "${RECONNECT_DELAY}" ]
then
  RECONNECT_DELAY=600
fi

# --- Server certificate pin helpers (used when SERVERCERT=auto) ---

# Plan A: ask openconnect itself for the pin, without authenticating.
# With no credentials and --non-inter, openconnect performs just the TLS
# handshake, stops at certificate verification, prints the pin it would
# trust ("--servercert pin-sha256:...") and aborts before any auth prompt,
# so no OTP/password is consumed.
discover_pin_openconnect() {
  local grp=""
  [ -n "${AUTH_GROUP}" ] && grp="--authgroup=${AUTH_GROUP}"
  # EXTRA_ARGS is passed through so protocol-selecting flags (e.g.
  # --protocol=fortinet) are honored during the handshake probe.
  # shellcheck disable=SC2086
  openconnect --non-inter ${grp} ${EXTRA_ARGS} "${URL}" </dev/null 2>&1 \
    | grep -oE 'pin-sha256:[A-Za-z0-9+/=]+' | head -n1
}

# Plan B: compute the SPKI pin directly with openssl. Produces the exact same
# "pin-sha256:..." value as plan A, used as a fallback if the scrape comes back
# empty (e.g. an openconnect build that phrases the message differently).
discover_pin_openssl() {
  command -v openssl >/dev/null 2>&1 || return 1
  # Extract host[:port] from URL (strip scheme and path); default to port 443.
  local u="${URL#*://}"; u="${u%%/*}"
  local host="${u%%:*}" port="${u##*:}"
  [ "${port}" = "${host}" ] && port=443
  local b64
  b64=$(echo | openssl s_client -connect "${host}:${port}" -servername "${host}" 2>/dev/null \
    | openssl x509 -noout -pubkey 2>/dev/null \
    | openssl pkey -pubin -outform der 2>/dev/null \
    | openssl dgst -sha256 -binary 2>/dev/null \
    | openssl base64 2>/dev/null)
  [ -n "${b64}" ] && printf 'pin-sha256:%s' "${b64}"
}

# Discover the server's certificate pin (plan A, falling back to plan B).
discover_pin() {
  local pin
  pin=$(discover_pin_openconnect)
  [ -z "${pin}" ] && pin=$(discover_pin_openssl)
  printf '%s' "${pin}"
}

# (Re)build the full openconnect command. URL must stay last, and
# --servercert must come before it, so we assemble it here on demand.
build_cmd() {
  OPENCONNECT_CMD="openconnect --script='vpn-slice ${SPLICE_ARGS}' ${OPENCONNECT_ARGS} ${SERVERCERT_OPT} ${URL}"
}

# Run openconnect, streaming output to the console while also capturing it
# to ${LOGFILE} so we can detect a certificate rejection afterwards.
do_connect() {
  local ret
  : > "${LOGFILE}"
  if [ -n "${OTP}" ]; then
    # shellcheck disable=SC2086
    echo -e "${PASS}\n${OTP}\n" | eval ${OPENCONNECT_CMD} 2>&1 | tee "${LOGFILE}"
    ret=${PIPESTATUS[1]}
  else
    # shellcheck disable=SC2086
    echo -e "${PASS}\n" | eval ${OPENCONNECT_CMD} 2>&1 | tee "${LOGFILE}"
    ret=${PIPESTATUS[1]}
  fi
  return "${ret}"
}

printf "\e[32mSetting mandatory arguments...\e[0m\n"
# Set user
# Drop --non-inter parameter
OPENCONNECT_ARGS="--user=${USER} -i ${TUN_DEVICE} --passwd-on-stdin"

# Test for auth group
printf "\e[32mChecking for authentication group parameter...\e[0m\n"
if [ -n "${AUTH_GROUP}" ]
then
  OPENCONNECT_ARGS="${OPENCONNECT_ARGS} --authgroup=${AUTH_GROUP}"
fi

# Add any additional arguments
printf "\e[32mChecking for additional arguments...\e[0m\n"
if [ -n "${EXTRA_ARGS}" ]
then
  OPENCONNECT_ARGS="${OPENCONNECT_ARGS} ${EXTRA_ARGS}"
fi

# Resolve the server certificate pin.
#   SERVERCERT unset            -> nothing added (rely on EXTRA_ARGS / system trust)
#   SERVERCERT=auto             -> trust-on-first-use: discover, cache and reuse the
#                                  pin; auto-refresh if it stops matching (key rotated)
#   SERVERCERT=pin-sha256:...   -> use the given pin verbatim
# The cache lives inside the container filesystem, so it survives restarts but is
# re-discovered whenever the container is recreated.
printf "\e[32mResolving server certificate pin...\e[0m\n"
SERVERCERT_OPT=""
SERVERCERT_PIN=""
PIN_FILE="/vpn/servercert.pin"

if [ "${SERVERCERT}" = "auto" ]; then
  if [ -s "${PIN_FILE}" ]; then
    SERVERCERT_PIN=$(cat "${PIN_FILE}")
    printf "\e[33mUsing cached server certificate pin:\e[0m %s\n" "${SERVERCERT_PIN}"
  else
    printf "\e[33mNo cached pin, discovering server certificate (trust-on-first-use)...\e[0m\n"
    SERVERCERT_PIN=$(discover_pin)
    if [ -n "${SERVERCERT_PIN}" ]; then
      printf '%s\n' "${SERVERCERT_PIN}" > "${PIN_FILE}"
      printf "\e[33mPinned and cached:\e[0m %s\n" "${SERVERCERT_PIN}"
    else
      printf "\e[31mCould not auto-discover a pin; the certificate may already be trusted by the system store. Continuing without an explicit pin.\e[0m\n"
    fi
  fi
elif [ -n "${SERVERCERT}" ]; then
  SERVERCERT_PIN="${SERVERCERT}"
  printf "\e[33mUsing provided server certificate pin:\e[0m %s\n" "${SERVERCERT_PIN}"
fi

if [ -n "${SERVERCERT_PIN}" ]; then
  SERVERCERT_OPT="--servercert=${SERVERCERT_PIN}"
fi

# Set the local time
# shellcheck disable=SC2086
cp /usr/share/zoneinfo/${TZ} /etc/localtime
# shellcheck disable=SC2086
echo "${TZ}" >  /etc/timezone

printf "\e[32mStarting OpenConnect VPN...\e[0m\n"
LOGFILE=$(mktemp)
build_cmd
printf "\e[33mArguments:\e[0m %s\n\n" "${OPENCONNECT_CMD}"

START_DATE=$(date +%s)
do_connect
RESULT=$?

# Auto-refresh: if a cached pin no longer matches (server key rotated),
# openconnect prints a fresh "pin-sha256:" suggestion. Re-discover it,
# update the cache and retry once with the new pin.
if [ "${SERVERCERT}" = "auto" ] && [ "${RESULT}" -ne 0 ] && grep -q 'pin-sha256:' "${LOGFILE}"; then
  printf "\e[31mThe pinned server certificate no longer matches (server key rotated?).\e[0m\n"
  NEW_PIN=$(discover_pin)
  if [ -n "${NEW_PIN}" ] && [ "${NEW_PIN}" != "${SERVERCERT_PIN}" ]; then
    printf "\e[33mAuto-accepting and caching new server certificate pin:\e[0m %s\n" "${NEW_PIN}"
    SERVERCERT_PIN="${NEW_PIN}"
    SERVERCERT_OPT="--servercert=${SERVERCERT_PIN}"
    printf '%s\n' "${SERVERCERT_PIN}" > "${PIN_FILE}"
    build_cmd
    START_DATE=$(date +%s)
    do_connect
    RESULT=$?
  else
    printf "\e[31mCould not obtain a different pin automatically; leaving the cache untouched.\e[0m\n"
  fi
fi

rm -f "${LOGFILE}"

END_DATE=$(date +%s)
DURATION=$((END_DATE - START_DATE))

# shellcheck disable=SC2004
if (( $DURATION < $MIN_SESSION_TIME )); then
    echo "Premature failure, delaying retry by $RECONNECT_DELAY seconds."
    # shellcheck disable=SC2086
    sleep $RECONNECT_DELAY
fi

exit $RESULT