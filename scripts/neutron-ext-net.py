#!/usr/bin/python

# from charm-openstack-testing!

from neutronclient.v2_0 import client

from keystoneclient.v2_0 import client as ks_client
from keystoneclient.auth import identity
from keystoneclient import session
import optparse
import os
import sys
import logging


usage = """Usage: %prog [options] ext_net_name

For example:

  %prog -g 192.168.21.1 -c 192.168.21.0/25 \\
      -f 192.168.21.100:192.168.21.200 ext_net
"""

if __name__ == '__main__':
    parser = optparse.OptionParser(usage)
    parser.add_option('-t', '--tenant',
                      help='Tenant name to create network for',
                      dest='tenant', action='store',
                      default=None)
    parser.add_option("-d", "--debug",
                      help="Enable debug logging",
                      dest="debug", action="store_true", default=False)
    parser.add_option("-g", "--gateway",
                      help="Default gateway to use.",
                      dest="default_gateway", action="store", default=None)
    parser.add_option("-c", "--cidr",
                      help="CIDR of external network.",
                      dest="cidr", action="store", default=None)
    parser.add_option("-f", "--floating-range",
                      help="Range of floating IP's to use (separated by :).",
                      dest="floating_range", action="store", default=None)
    parser.add_option("--network-type",
                      help="Network type.",
                      dest="network_type", action="store", default='gre')
    (opts, args) = parser.parse_args()

    if len(args) != 1:
        parser.print_help()
        sys.exit(1)

    if opts.debug:
        logging.basicConfig(level=logging.DEBUG)
    else:
        logging.basicConfig(level=logging.INFO)

    net_name = args[0]
    subnet_name = '{}_subnet'.format(net_name)

    if (opts.floating_range):
        (start_floating_ip, end_floating_ip) = opts.floating_range.split(':')
    else:
        start_floating_ip = None
        end_floating_ip = None

    # use session based authentication
    ep = os.environ['OS_AUTH_URL']
    if not ep.endswith('v2.0'):
        ep = "{}/v2.0".format(ep)
    auth = identity.v2.Password(username=os.environ['OS_USERNAME'],
                                password=os.environ['OS_PASSWORD'],
                                tenant_name=os.environ['OS_TENANT_NAME'],
                                auth_url=ep)
    sess = session.Session(auth=auth)
    keystone = ks_client.Client(session=sess)
    keystone.auth_ref = auth.get_access(sess)
    neutron_ep = keystone.service_catalog.url_for(
            service_type='network', endpoint_type='publicURL')
    neutron = client.Client(session=sess)

    # Resolve tenant id
    tenant_id = None
    for tenant in [t._info for t in keystone.tenants.list()]:
        if (tenant['name'] == (opts.tenant or os.environ['OS_TENANT_NAME'])):
            tenant_id = tenant['id']
            break  # Tenant ID found - stop looking
    if not tenant_id:
        logging.error("Unable to locate tenant id for %s.", opts.tenant)
        sys.exit(1)

    networks = neutron.list_networks(name=net_name)
    if len(networks['networks']) == 0:
        logging.info("Configuring external network '%s'", net_name)
        network_msg = {
            'network': {
                'name': net_name,
                'router:external': True,
                'tenant_id': tenant_id,
                'provider:network_type': opts.network_type,
            }
        }

        if opts.network_type == 'vxlan':
            network_msg['network']['provider:segmentation_id'] = 1234
        elif opts.network_type == 'vlan':
            network_msg['network']['provider:segmentation_id'] = 2
            network_msg['network']['provider:physical_network'] = 'physnet1'
        elif opts.network_type == 'flat':
            network_msg['network']['provider:physical_network'] = 'physnet1'
        else:
            network_msg['network']['provider:segmentation_id'] = 2

        logging.info('Creating new external network definition: %s', net_name)
        network = neutron.create_network(network_msg)['network']
        logging.info('New external network created: %s', network['id'])
    else:
        logging.warning('Network %s already exists.', net_name)
        network = networks['networks'][0]

    subnets = neutron.list_subnets(name=subnet_name)
    if len(subnets['subnets']) == 0:
        subnet_msg = {
            'name': subnet_name,
            'network_id': network['id'],
            'enable_dhcp': False,
            'ip_version': 4,
            'tenant_id': tenant_id
        }

        if opts.default_gateway:
            subnet_msg['gateway_ip'] = opts.default_gateway
        if opts.cidr:
            subnet_msg['cidr'] = opts.cidr
        if (start_floating_ip and end_floating_ip):
            subnet_msg['allocation_pools'] = [{
                'start': start_floating_ip,
                'end': end_floating_ip
            }]

        logging.info('Creating new subnet for %s', net_name)
        subnet = neutron.create_subnet({'subnet': subnet_msg})['subnet']
        logging.info('New subnet created: %s', subnet['id'])
    else:
        logging.warning('Subnet %s already exists.', subnet_name)
        subnet = subnets['subnets'][0]

    routers = neutron.list_routers(name='provider-router')
    if len(routers['routers']) == 0:
        logging.info('Creating provider router for external network access')
        router = neutron.create_router(
            {'router': {'name': 'provider-router', 'tenant_id': tenant_id}}
        )['router']
        logging.info('New router created: %s', (router['id']))
    else:
        logging.warning('Router provider-router already exists.')
        router = routers['routers'][0]

    ports = neutron.list_ports(device_owner='network:router_gateway',
                               network_id=network['id'])
    if len(ports['ports']) == 0:
        logging.info('Plugging router into ext_net')
        router = (
            neutron.add_gateway_router(
                            router=router['id'],
                            body={'network_id': network['id']}))
        logging.info('Router connected to %s', net_name)
    else:
        logging.warning('Router already connect to %s', net_name)
