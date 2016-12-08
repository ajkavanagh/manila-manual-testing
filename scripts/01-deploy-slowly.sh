#/bin/bash

# deploy the openstack bundle using Juju 2.0 slowly.
# First deploy with no units, then add a unit every 2 minutes.

# This assumes that you have bootstrapped and (for Juju 2.0) switched to the
# model.
set -e

declare -a UNITS=(
    'mysql'
    'rabbitmq-server'
    'keystone'
    'ceph'
    'ceph-radosgw'
    'cinder'
    'glance'
    'neutron-gateway'
    'neutron-api'
    'nova-cloud-controller'
    'nova-compute'
    'manila')

for UNIT in ${UNITS[@]}; do
    current=`juju show-status --format=oneline $UNIT | tr -d '\n'`
    echo -n "Checking $UNIT: "
    if [[ -z $current ]]; then
        echo -n "waiting for idle: "
        while [ 1 ]; do
            idle=`juju show-status --format=oneline | grep -E "executing|allocating" | tr -d '\n'`
            echo -n .
            if [[ -z $idle ]]; then break; fi
            sleep 10
        done
        echo " -- add unit for $UNIT"
        juju add-unit $UNIT
    else
        echo "deployed already."
    fi
done

# finally wait for it to go idle
echo ""
echo -n "Waiting for idle on deployment: "
while [ 1 ]; do
    idle=`juju show-status --format=oneline | grep -E "executing|allocating" | tr -d '\n'`
    if [[ -z $idle ]]; then break; fi
    echo -n .
    sleep 10
done
echo "\n"
echo "All done. Now make sure you 'juju add-unit ceph -n 2' for the cluster"


