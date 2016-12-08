#/bin/bash

# stolen/heavily influenced from openstack-charm-testing

# Set up the network, projects and users after we've deployed the charms
# assumes that overcloud is in ./novarc and undercloud (serverstack) is in
# ~/novarc

# In a CirrOS image, the login account is cirros. The password is "cubswin:)"

set -ex

# load the common vars
source ./vars.sh

## now everything is with the OVERCLOUD
source $OVERCLOUD

# we need cirros and manila-service-image -- if not, we'll have to add them.
glance_image_list=($(openstack image list -c Name -f value))

IMAGES=../images
mkdir -p "$IMAGES"

# fetch xenial if it doesn't exist!
if ! elementIn "xenial" ${glance_image_list[@]};
then
  [ -f $IMAGES/xenial-server-cloudimg-amd64-disk1.img ] || {
    wget -O $IMAGES/xenial-server-cloudimg-amd64-disk1.img \
      http://cloud-images.ubuntu.com/xenial/current/xenial-server-cloudimg-amd64-disk1.img
  }
  glance --os-image-api-version 1 image-create --name="xenial" \
    --is-public=true --progress --container-format=bare \
    --disk-format=qcow2 < $IMAGES/xenial-server-cloudimg-amd64-disk1.img
fi

# fetch the manila-service-image if it doesn't exist (this is big)
if ! elementIn "manila-service-image" ${glance_image_list[@]};
then
  [ -f $IMAGES/manila-service-image-master.qcow2 ] || {
    wget -O $IMAGES/manila-service-image-master.qcow2 \
      http://tarballs.openstack.org/manila-image-elements/images/manila-service-image-master.qcow2
  }
  glance --os-image-api-version 1 image-create --name="manila-service-image" \
    --is-public=true --progress --container-format=bare \
    --disk-format=qcow2 < $IMAGES/manila-service-image-master.qcow2
fi

## Set up the flavors for the cirros image and the manila-service-image
flavors=($(openstack flavor list -c Name -f value))
if ! elementIn "manila-service-flavor" ${flavors[@]}; then
  openstack flavor create manila-service-flavor --id 100 --ram 256 --disk 0 --vcpus 1
fi
if ! elementIn "m1.xenial" ${flavors[@]}; then
  openstack flavor create m1.xenial --id 7 --ram 2048 --disk 5 --vcpus 1
fi


# Create demo/testing users, tenants and flavor
openstack project create --or-show demo
openstack user create --or-show --project demo --password pass --email demo@dev.null demo
openstack role create --or-show Member
roles=($(openstack role list --user demo --project demo -c Name -f value))
if ! elementIn "Member" ${roles[@]}; then
  openstack role add --user demo --project demo Member
fi

# ensure that a keypair is setup for the user
keypairs=($(openstack keypair list -c Name -f value))
if ! elementIn "demo-user" ${keypairs[@]}; then
  [ -f ./demo-user-rsa ] && rm -f ./demo-user-rsa
  openstack keypair create demo-user > ./demo-user-rsa
  chmod 600 ./demo-user-rsa
fi

## need the network id for 'internal' network to put into these images if they
# don't exist.
net_id=$( openstack network list -c ID -c Name -f value | grep internal | awk '{print $1}' | tr -d '\n')
# get list of running servers
server_list=($(openstack server list -c Name -f value))
if ! elementIn "xenial-test1" ${server_list[@]}; then
  # and create two test vms for share testing
  # see if the two servers exist -- if either exists, tear it down.
  openstack server create --flavor m1.xenial --image xenial --key-name demo-user \
    --security-group default --nic net-id=$net_id xenial-test1
fi
if ! elementIn "xenial-test2" ${server_list[@]}; then
  # and create two test vms for share testing
  # see if the two servers exist -- if either exists, tear it down.
  openstack server create --flavor m1.xenial --image cirros \
    --security-group default --nic net-id=$net_id xenial-test2
fi

floating_ips=($(openstack ip floating list -c "Floating IP Address" -f value))
server_networks=$(openstack server list -c Name -c Networks -f value)
_ifs=IFS
IFS='
'
for server_network in ${server_networks}; do
  IFS=' '
  echo Doing $server_network
  server=$(echo $server_network | cut -f1 -d " ")
  found=0
  for ip in ${floating_ips[@]}; do
    rry=($(echo $server_network))
    if elementIn "$ip" ${rry[@]}; then
      found=1
    fi
  done
  if [ $found -eq 0 ]; then
    # need to add an IP address
    # see if there is a one not assigned.
    not_used_ips=($(openstack ip floating list -c "Floating IP Address" -c "Fixed IP Address" -f value))
    found=
    for not_used_ip in ${not_used_ips[@]}; do
      rry=($(echo $server_network))
      if elementIn None ${rry[@]}; then
        found=$(echo $not_used_ip | cut -f1 -d" ")
        break
      fi
    done
    if [ "xxx" == "xxx$found" ]; then
      # create and IP address and then assign it.
      found=$(openstack ip floating create ext_net | grep "^| ip" | awk '{print $4}')
    fi
    # now assign the ip address
    openstack ip floating add $found $server
  fi
done
IFS=_ifs

#vim: set ts=2 et:
