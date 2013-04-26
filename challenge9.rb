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
Challenge 9
Write an application that when passed the arguments FQDN, image, and
flavor it creates a server of the specified image and flavor with the
same name as the fqdn, and creates a DNS entry for the fqdn pointing
to the server's public IP.
Worth 2 Points
=end

require 'fog'
require 'optparse'

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
options.flavor = "2"
options.image = "5cebb13a-f783-4f8c-8058-c4182c724ccd"
options.fqdn = nil
options.interval = 5
options.timeout = 1200
options.dc = :dfw

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge9.rb [options] fqdn"
  opts.on('-f', '--flavor FLAVOR', 'Flavor ID for servers') {|f| options.flavor = f}
  opts.on('-i', '--image ID', 'ID of image to use for servers') { |i| options.image = i }
  opts.on('-t', '--interval INTERVAL', OptionParser::DecimalInteger, 'Sleep INTERVAL seconds between status checks') do |i|
    options.interval = i
  end
  opts.on('--timeout TIMEOUT', OptionParser::DecimalInteger, 'Wait maximum of TIMEOUT seconds for build to complete') do |t|
    options.timeout = t
  end
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

# insure a fqdn has been specified
if ARGV.length != 1
  p optparse
  exit
end
options.fqdn = ARGV.shift

# make sure fqdn is at least host.domain
fqdnsplit = options.fqdn.split('.')
if fqdnsplit.length < 3
  puts "#{options.fqdn} is not a valid fully qualified domain name"
  exit
end
domain = fqdnsplit.last(2).join('.')

dnsservice = Fog::DNS.new({
  :provider             => 'rackspace',
  :rackspace_username   => rackspace_username,
  :rackspace_api_key    => rackspace_api_key,
})

# make sure zone exists
zone = dnsservice.zones.find {|z| z.domain == domain}
if zone == nil
  puts "Zone #{domain} does not exist.  Exiting..."
  exit
end

# create Next Generation Cloud Server service
service = Fog::Compute.new({
  :provider             => 'rackspace',
  :rackspace_username   => rackspace_username,
  :rackspace_api_key    => rackspace_api_key,
  :version => :v2,  # Use Next Gen Cloud Servers
  :rackspace_region => options.dc #Use Chicago Region
})

# map flavor and image IDs to object
flavor = service.flavors.get(options.flavor)
if flavor == nil
  puts "Could not load flavor ID #{options.flavor}"
  exit
end
image = service.images.get(options.image)
if image == nil
  puts "Could not load image ID #{options.image}"
  exit
end

# create the server
puts "Creating server"
server = service.servers.create({:name => options.fqdn,
                                 :flavor_id => flavor.id,
                                 :image_id => image.id})


# watch for server builds to complete.  check every 5 seconds, and move
# server to complete array once done to prevent repeated API calls
print "Monitoring for server creation completion.  Maximum timeout #{options.timeout}"
server.wait_for(options.timeout, options.interval) {print "."; STDOUT.flush; ready?}

# sometimes if printing immediately, the network addresses are not properly populated
while server.ipv4_address == ""
  sleep 5
  server.reload
end
puts
puts "#{server.name}: IPv4: #{server.ipv4_address} IPv6: #{server.ipv6_address} username: #{server.username} password: #{server.password}"

# add A record for host
begin
  record = zone.records.create(
    :value => server.ipv4_address,
    :name => options.fqdn,
    :type => 'A')
  puts "A record created for #{options.fqdn} for #{server.ipv4_address}"
rescue Fog::DNS::Rackspace::CallbackError # cname already exists
  puts "Address record for #{options.fqdn} already exists."
  exit
end