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

# URL needs to be the last argument
printf "\e[32mSetting URL...\e[0m\n"
OPENCONNECT_ARGS="${OPENCONNECT_ARGS} ${URL}"

# Set the local time
# shellcheck disable=SC2086
cp /usr/share/zoneinfo/${TZ} /etc/localtime
# shellcheck disable=SC2086
echo "${TZ}" >  /etc/timezone

printf "\e[32mStarting OpenConnect VPN...\e[0m\n"
OPENCONNECT_CMD="openconnect --script='vpn-slice ${SPLICE_ARGS}' ${OPENCONNECT_ARGS}"
printf "\e[33mArguments:\e[0m %s\n\n" "${OPENCONNECT_CMD}"

# shellcheck disable=SC2086
if [ -n "${OTP}" ]; then
  # shellcheck disable=SC2086
  echo -e "${PASS}\n${OTP}\n" | eval ${OPENCONNECT_CMD}
else
  # shellcheck disable=SC2086
  echo -e "${PASS}\n" | eval ${OPENCONNECT_CMD}
fi
