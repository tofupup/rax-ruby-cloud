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

# Challenge 5
# Write a script that creates a Cloud Database instance. This
# instance should contain at least one database, and the database
# should have at least one user that can connect to it.
# Worth 1 Point


import pyrax
import os
from sys import exit
from time import sleep
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter

parser = ArgumentParser(formatter_class=ArgumentDefaultsHelpFormatter)
parser.add_argument("-f", dest="flavor", default=1, type=int,
                    help="build database of flavor FLAVOR", metavar="FLAVOR")
parser.add_argument("-s", dest="size", default=1, type=int,
                    help="create database of SIZE in GB", metavar="SIZE")
parser.add_argument("-i", dest="instname",
                    default="testinst",
                    help="name cloud database instance INSTNAME",
                    metavar="INSTNAME")
parser.add_argument("-n", dest="dbname", default="testdb",
                    help="name database DBNAME", metavar="DBNAME")
parser.add_argument("-u", dest="dbuser", default="testuser",
                    help="name user DBUSER",
                    metavar="DBUSER")
parser.add_argument("-p", dest="dbpass", default="testpass",
                    help="set user password to DBPASS", metavar="DBPASS")
parser.add_argument("-t", dest="interval", type=int, default=5,
                    help="wait INTERVAL seconds between status checks",
                    metavar="INTERVAL")
parser.add_argument("-d", dest="dc", default="DFW",
                    help="use data center DC", metavar="DC")

args = parser.parse_args()

pyrax.set_credential_file(os.path.expanduser("~/.rackspace_cloud_credentials"))

cs = pyrax.connect_to_cloud_databases(region=args.dc)

flavors = cs.list_flavors()
flavor = None
for f in flavors:
    if f.id == args.flavor:
        flavor = f
if flavor is None:
    print "Flavor %s not found.  Please specify an existing flavor ID:" % (args.flavor)
    for f in flavors:
        print "ID: %s  Name: %s" % (f.id, f.name)
    exit(1)

print "Creating instance %s" % (args.instname)
inst = cs.create(args.instname, flavor=flavor, volume=args.size)
while inst.status != "ACTIVE":
    print "Instance %s still building..." % (inst.name)
    inst.get()
    sleep(args.interval)

print "Creating database %s" % (args.dbname)
db = inst.create_database(args.dbname)

print "Creating user %s/%s" % (args.dbuser, args.dbpass)
user = inst.create_user(name=args.dbuser, password=args.dbpass,
                        database_names=[args.dbname])

print "Hostname: %s  DB: %s    Username/password: %s/%s" \
    % (inst.hostname, db.name, user.name, args.dbpass)
