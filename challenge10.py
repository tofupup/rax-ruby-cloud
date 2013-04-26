#!/usr/bin/env python

   # Copyright 2013 John Schutz

   # Licensed under the Apache License, Version 2.0 (the "License");
   # you may not use this file except in compliance with the License.
   # You may obtain a copy of the License at

   #     http://www.apache.org/licenses/LICENSE-2.0

   # Unless required by applicable law or agreed to in writing, software
   # distributed under the License is distributed on an "AS IS" BASIS,
   # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   # See the License for the specific language governing permissions and
   # limitations under the License.

# Challenge 10
# Write an application that will:
# - Create 2 servers, supplying a ssh key to be installed at
#   /root/.ssh/authorized_keys.
# - Create a load balancer
# - Add the 2 new servers to the LB
# - Set up LB monitor and custom error page.
# - Create a DNS record based on a FQDN for the LB VIP.
# - Write the error page html to a file in cloud files for backup.
# ***Worth 8 points!***

import pyrax
import os
from sys import exit
from time import sleep
from re import match
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter

parser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)
parser.add_argument("-k", dest="sshkeyfile", default="~/.ssh/id_rsa.pub",
                    help="SSH public key in FILE", metavar="FILE")
parser.add_argument("errorfile", metavar="ERRORFILE",
                    help="Use HTML error page from ERRORFILE")
parser.add_argument("fqdn", metavar="FQDN",
                    help="Create hostname FQDN for load balancer VIP")
parser.add_argument("-l", dest="lbname", default="testlb",
                    help="name the load balancer LBNAME", metavar="LBNAME")
parser.add_argument("-v", dest="port", type=int, default=80,
                    help="VIP port VIPPORT", metavar="VIPPORT")
parser.add_argument("-p", dest="srvport", type=int, default=80,
                    help="load balancer connects to TCP SRVPORT on nodes",
                    metavar="SRVPORT")
parser.add_argument("-i", dest="image",
                    default="e4dbdba7-b2a4-4ee5-8e8f-4595b6d694ce",
                    help="use cloud image id IMAGE", metavar="IMAGE")
parser.add_argument("-s", dest="flavor", default="2",
                    help="use cloud flavor id FLAVOR", metavar="FLAVOR")
parser.add_argument("-n", dest="name", default="web",
                    help="use base server name NAME followed by instance\
                    number (ie. web1, web2, etc)", metavar="NAME")
parser.add_argument("-c", dest="count", type=int, default=2,
                    help="create COUNT cloud servers", metavar="COUNT")
parser.add_argument("-t", dest="interval", type=int, default=5,
                    help="wait INTERVAL seconds between status checks",
                    metavar="INTERVAL")
parser.add_argument("-w", dest="private", default=False, action="store_true",
                    help="create private VIP on servicenet")
parser.add_argument("-d", dest="dc", default="DFW",
                    help="use data center DC (DFW or ORD)", metavar="DC")
parser.add_argument("-a", dest="container", default="errorcontainer",
                    help="Store error page in CONTAINER", metavar="CONTAINER")
args = parser.parse_args()

pyrax.set_credential_file(os.path.expanduser("~/.rackspace_cloud_credentials"))

# make sure ssh key file exists
try:
    sshfile = open(os.path.expanduser(args.sshkeyfile))
    sshkey = sshfile.read()
except IOError:
    print "Could not load SSH key file %s.  Exiting" % (args.sshkeyfile)
    exit(1)

# make sure HTML error file exists
try:
    errorfile = open(os.path.expanduser(args.errorfile))
    errorpage = errorfile.read()
except IOError:
    print "Could not open HTML error page %s.  Exiting" % (args.errorfile)
    exit(1)

# make sure FQDN provided is a good hostname
hostwords = args.fqdn.split('.')
if len(hostwords) < 3:
    print "%s is not a valid hostname.  Exiting" % (args.fqdn)
    exit(1)
domain = ".".join(hostwords[-2:])

cs = pyrax.connect_to_cloudservers(region=args.dc)
clb = pyrax.connect_to_cloud_loadbalancers(region=args.dc)
cf = pyrax.connect_to_cloudfiles(region=args.dc)
cdns = pyrax.connect_to_cloud_dns(region=args.dc)

# check if container name exists
containers = cf.get_all_containers()
container = None
for c in containers:
    if c.name == args.container:
        container = c
if container is not None:
    print "Container %s already exists.  Please specify non-existent container" \
        % (args.container)
    exit(1)
container = cf.create_container(args.container)

# make sure zone for DNS exists
zones = cdns.list()
zone = None
for z in zones:
    if z.name == domain:
        zone = z
if zone is None:
    print "Zone %s not found.  Please insure the FQDN is an existing domain" \
        % (domain)
    for z in zones:
        print "%s" % (z.name)
    exit(1)

# insure image is valid
images = cs.images.list()
image = None
for i in images:
    if i.id == args.image:
        image = i
if image is None:
    print "Image %s not found.  Please specify an existing image ID:" \
        % (args.image)
    for i in images:
        print "ID: %s  Name: %s" % (i.id, i.name)
    exit(1)

# make sure flavor is valid
flavors = cs.flavors.list()
flavor = None
for f in flavors:
    if f.id == args.flavor:
        flavor = f
if flavor is None:
    print "Flavor %s not found.  Please specify an existing flavor ID:" \
        % (args.flavor)
    for f in flavors:
        print "ID: %s  Name: %s" % (f.id, f.name)
    exit()

print "Creating %d servers" % (args.count)
print "Image: %s" % (cs.images.get(args.image).name)
print "Flavor: %s" % (cs.flavors.get(args.flavor).name)
print "Name base: %s" % (args.name)

# create servers
servers = []
for i in xrange(0, args.count):
    name = '%s%d' % (args.name, i+1)
    print "Creating server %s..." % (name)
    servers.append(
        cs.servers.create(name, args.image, args.flavor,
                          files={"/root/.ssh/authorized_keys": sshkey}))

# monitor for server build completion
completed = []
while len(completed) < args.count:
    sleep(args.interval)
    print "\nChecking status"
    for server in servers:
        if server not in completed:
            server.get()
            if server.status == "BUILD":
                print "%s is still building" % (server.name)
            elif server.status == "ACTIVE":
                print "%s is finished building" % (server.name)
                completed.append(server)
            else:
                sname = server.name
                print "UNKNOWN SERVER STATUS FOR %s: %s...exiting..." \
                    % (sname, server.status)
                exit()

print

# add servers to load balancer
print "Building load balancer %s" % (args.lbname)
nodes = []
for i in completed:
    i.get()
    nodes.append(clb.Node(address=i.networks["private"][0], port=args.srvport,
                          condition="ENABLED"))

# set what type of VIP address we want
if not args.private:
    vip = clb.VirtualIP(type="PUBLIC")
else:
    vip = clb.VirtualIP(type="SERVICENET")

# create load balancer
lb = clb.create(args.lbname, port=args.port, protocol="HTTP",
                nodes=nodes, virtual_ips=[vip])

# monitor for load balancer build completion
while lb.status != "ACTIVE":
    sleep(args.interval)
    print "Checking status"
    lb.get()
print "Load balancer created.  Name: %s  Virtual IP: %s" \
    % (lb.name, lb.virtual_ips[0].address)

# create health monitor
print "Adding HTTP health monitor"
lb.add_health_monitor(type="HTTP", delay=10, timeout=10,
                      attemptsBeforeDeactivation=3, path="/",
                      statusRegex="^[234][0-9][0-9]$",
                      bodyRegex=".* testing .*")

# monitor for LB update to complete
lb.get()
while lb.status != "ACTIVE":
    sleep(args.interval)
    print "Checking status"
    lb.get()

# add custom error page to LB
print "Setting error page from file %s" % (args.errorfile)
lb.set_error_page(errorpage)

# monitor for LB update to complete
lb.get()
while lb.status != "ACTIVE":
    sleep(args.interval)
    print "Checking status"
    lb.get()

# Add A record for VIP
print "Creating A record for VIP with hostname %s" % (args.fqdn)
zone.add_records({"type": "A", "name": args.fqdn,
                  "data": lb.virtual_ips[0].address,
                  "ttl": 300})

# backup error page to cloud files
basefile = os.path.basename(args.errorfile)
print "Uploading error file %s to cloud files container %s" \
    % (basefile, args.container)
cloudfile = container.store_object(basefile, errorpage)

# print server information
print "Server information:"
for server in completed:
    ipv4 = 0
    ipv6 = 1
    if match('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}',
             server.networks['public'][1]):
        ipv4 = 1
        ipv6 = 0
    print "Server  : %s\nIP      : %s\nIPv6    : %s\nUsername: %s\nPassword: %s\n" \
        % (server.name, server.networks['public'][ipv4],
           server.networks['public'][ipv6], "root", server.adminPass)
