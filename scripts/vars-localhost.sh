#/bin/bash

# Set up vars common to all the configuration scripts

export OVERCLOUD="./novarc"

# Set network defaults, if not already set.
[[ -z "$GATEWAY" ]] && export GATEWAY="172.16.1.1"
[[ -z "$CIDR_EXT" ]] && export CIDR_EXT="172.16.1.0/24"
[[ -z "$FIP_RANGE" ]] && export FIP_RANGE="172.16.1.201:172.16.1.254"
[[ -z "$NAMESERVER" ]] && export NAMESERVER="172.16.1.1"
[[ -z "$CIDR_PRIV" ]] && export CIDR_PRIV="192.168.21.0/24"

# handy function to test if an array contains a value $1 in ${2[@]}
# returns $? as 1 if the element does exist
elementIn () {
  local e
  for e in "${@:2}"; do [[ "$e" == "$1" ]] && return 0; done
  return 1
}

