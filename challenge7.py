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

# Challenge 7
# Write a script that will create 2 Cloud Servers and add them as
# nodes to a new Cloud Load Balancer.
# Worth 3 Points

import pyrax
import os
from sys import exit
from time import sleep
from re import match
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter

parser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)
parser.add_argument("-l", dest="lbname", default="testlb",
                    help="name the load balancer LBNAME", metavar="LBNAME")
parser.add_argument("-v", dest="port", type=int, default=80,
                    help="VIP port VIPPORT", metavar="VIPPORT")
parser.add_argument("-p", dest="srvport", type=int, default=80,
                    help="load balancer connects to TCP SRVPORT on nodes",
                    metavar="SRVPORT")
parser.add_argument("-o", dest="protocol", default="HTTP",
                    help="load balance protocol PROTOCOL", metavar="PROTOCOL")
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

args = parser.parse_args()

pyrax.set_credential_file(os.path.expanduser("~/.rackspace_cloud_credentials"))

cs = pyrax.connect_to_cloudservers(region=args.dc)
clb = pyrax.connect_to_cloud_loadbalancers(region=args.dc)

images = cs.images.list()
image = None
for i in images:
    if i.id == args.image:
        image = i
if image is None:
    print "Image %s not found.  Please specify an existing image ID:" % (args.image)
    for i in images:
        print "ID: %s  Name: %s" % (i.id, i.name)
    exit()

flavors = cs.flavors.list()
flavor = None
for f in flavors:
    if f.id == args.flavor:
        flavor = f
if flavor is None:
    print "Flavor %s not found.  Please specify an existing flavor ID:" % (args.flavor)
    for f in flavors:
        print "ID: %s  Name: %s" % (f.id, f.name)
    exit()

print "Creating %d servers" % (args.count)
print "Image: %s" % (cs.images.get(args.image).name)
print "Flavor: %s" % (cs.flavors.get(args.flavor).name)
print "Name base: %s" % (args.name)

servers = []

for i in xrange(0, args.count):
    name = '%s%d' % (args.name, i+1)
    print "Creating server %s..." % (name)
    servers.append(cs.servers.create(name, args.image, args.flavor))

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
for server in completed:
    ipv4 = 0
    ipv6 = 1
    if match('\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', server.networks['public'][1]):
        ipv4 = 1
        ipv6 = 0
    print "Server  : %s\nIP      : %s\nIPv6    : %s\nUsername: %s\nPassword: %s\n" \
        % (server.name, server.networks['public'][ipv4],
           server.networks['public'][ipv6], "root", server.adminPass)

print
print "Building load balancer %s" % (args.lbname)
nodes = []
for i in completed:
    i.get()
    nodes.append(clb.Node(address=i.networks["private"][0], port=args.srvport,
                          condition="ENABLED"))

if not args.private:
    vip = clb.VirtualIP(type="PUBLIC")
else:
    vip = clb.VirtualIP(type="SERVICENET")

lb = clb.create(args.lbname, port=args.port, protocol=args.protocol, nodes=nodes,
                virtual_ips=[vip])

while lb.status != "ACTIVE":
    sleep(args.interval)
    print "Checking status"
    lb.get()

print "Load balancer created.  Name: %s  Virtual IP: %s" % (lb.name, lb.virtual_ips[0].address)
