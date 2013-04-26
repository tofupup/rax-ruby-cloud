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
Challenge 1
Write a script that builds three 512 MB Cloud Servers that follow a
similar naming convention. (ie., web1, web2, web3) and returns the IP
and login credentials for each server. Use any image you want.
Worth 1 point
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
options.namebase = "web"
options.numservers = 3
options.interval = 5
options.dc = :dfw

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge1.rb [options] destname"
  opts.on('-n', '--name NAME', "Base name of servers, ie. web for web1, web2, etc.") { |n| options.namebase = n }
  opts.on('-f', '--flavor FLAVOR', 'Flavor ID for servers') {|f| options.flavor = f}
  opts.on('-i', '--image ID', 'ID of image to use for servers') { |i| options.image = i }
  opts.on('-t', '--interval INTERVAL', OptionParser::DecimalInteger, 'Sleep INTERVAL seconds between status checks') do |i|
    options.interval = i
  end
  opts.on('-c', '--count COUNT', OptionParser::DecimalInteger, 'Create COUNT new servers') do |n|
    options.numservers = n
  end
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

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

# create the servers
servers = []
puts "Creating #{options.numservers} servers"
options.numservers.times do |x|
  servers[x] = service.servers.create({:name => options.namebase + (x+1).to_s,
                                       :flavor_id => flavor.id,
                                       :image_id => image.id})
end

# watch for server builds to complete.  check every 5 seconds, and move
# server to complete array once done to prevent repeated API calls
print "Monitoring for server creation completion"
complete = []
while complete.length < options.numservers
  sleep(5)
  print "."
  servers.each {|x| x.reload}
  servers.delete_if do |server|
    if server.ready?
      print "#{server.name} complete"
      complete << server
      true
    end
  end
  STDOUT.flush
end
puts

# print server information
complete.each do |server|
  # sometimes if printing immediately, the network addresses are not properly populated
  while server.ipv4_address == ""
    sleep 5
    server.reload
  end
  puts "#{server.name}: IPv4: #{server.ipv4_address} IPv6: #{server.ipv6_address} username: #{server.username} password: #{server.password}"
end
