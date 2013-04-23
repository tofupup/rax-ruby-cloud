#!/usr/bin/env ruby
=begin
   Copyright 2013 John Schutz

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
=end

=begin
Challenge 4
Write a script that uses Cloud DNS to create a new A record when
passed a FQDN and IP address as arguments.
Worth 1 Point
=end

require 'fog'
require 'optparse'
require 'ipaddr'

# Used to get Rackspace cloud credentials if not provided in Fog config
def get_user_input(prompt)
  print "#{prompt}: "
  gets.chomp
end

# Use username defined in ~/.fog file, if absent prompt for username.
# For more details on ~/.fog refer to http://fog.io/about/getting_started.html
def rackspace_username
  Fog.credentials[:rackspace_username] || get_user_input("Enter Rackspace Username")
end

# Use api key defined in ~/.fog file, if absent prompt for api key
# For more details on ~/.fog refer to http://fog.io/about/getting_started.html
def rackspace_api_key
  Fog.credentials[:rackspace_api_key] || get_user_input("Enter Rackspace API key")
end

# parse command line options
options = OpenStruct.new
options.fqdn = ""
options.ip = ""
options.dc = :dfw
options.create = false
options.adminemail = nil

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge2.rb [options] fqdn ipaddress"
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('--create EMAIL', 'Create domain if it doesn\'t exist with admin email EMAIL') {|e| options.create = true; options.adminemail = e}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

if ARGV.length != 2
  p optparse
  exit
end

options.fqdn = ARGV.shift
options.ip = ARGV.shift

begin
  addr = IPAddr.new(options.ip)
rescue ArgumentError
  puts "#{options.ip} is not a valid IP address"
  exit
end

fqdnsplit = options.fqdn.split('.')
if fqdnsplit.length < 3
  puts "#{options.fqdn} is not a valid fully qualified domain name"
  exit
end
domain = fqdnsplit.last(2).join('.')

# create Cloud DNS service
service = Fog::DNS.new({
  :provider             => 'rackspace',
  :rackspace_username   => rackspace_username,
  :rackspace_api_key    => rackspace_api_key,
})

zone = service.zones.find {|z| z.domain == domain}
if zone == nil and not options.create
  puts "Zone #{domain} does not exist.  Specify --create to create"
  exit
end

if zone == nil
  puts "Zone #{domain} does not exist.  Creating"
  zone = service.zones.create(
    :domain => domain, :email => options.adminemail)
end
begin
  record = zone.records.create(
    :value => addr.to_s,  # in case there were spaces or something in IP
    :name => options.fqdn,
    :type => 'A')
  puts "Address record for #{record.name} with address #{record.value} created"
rescue Fog::DNS::Rackspace::CallbackError
  puts "Address record for #{options.fqdn} already exists"
end
