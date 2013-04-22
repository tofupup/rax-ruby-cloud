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
Challenge 2
Write a script that clones a server (takes an image and deploys the
image as a new server).
Worth 2 Points
=end

require 'optparse'
require 'fog'

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
options.srcname = nil
options.id = nil
options.interval = 5
options.dc = :dfw
options.delete = false

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge2.rb [options] destname"
  opts.on('-n', '--name NAME', 'Name of server to clone') { |n| options.srcname = n }
  opts.on('-i', '--id ID', 'ID of server to clone') { |i| options.id = i }
  opts.on('-t', '--interval INTERVAL', OptionParser::DecimalInteger, 'Sleep INTERVAL seconds between status checks') do |i|
    options.interval = i
  end
  opts.on('--delete', 'Delete image after clone is built') {options.delete = true}
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

# we can only accept either a source server name, or a source server id, but not both
if ((options.srcname == nil) and (options.id == nil)) || ((options.srcname) && (options.id))
  puts "You must specify either a source server name or ID, but not both.  Source server name and ID are mutually exclusive."
  p optparse
  exit
end

# must specify a name for the cloned server
if ARGV.length != 1
  puts "Destination server name is required"
  p optparse
  exit
end
options.destname = ARGV.shift

# create Next Generation Cloud Server service
service = Fog::Compute.new({
  :provider             => 'rackspace',
  :rackspace_username   => rackspace_username,
  :rackspace_api_key    => rackspace_api_key,
  :version => :v2,  # Use Next Gen Cloud Servers
  :rackspace_region => options.dc #Use specified region
})

# find the source server from either name or id provided on command line
# if this fails, we can't proceed
if (options.srcname)
  toclone = service.servers.find {|s| s.name == options.srcname }
  if not toclone
    puts "Could not locate server named #{options.srcname}"
    exit
  end
else
  toclone = service.servers.find {|s| s.id == options.id }
  if not toclone
    puts "Could not locate server with ID #{options.id}"
    exit
  end
end

# generate a name for the image with a randomized postfix.  insure it's
# unique just to prevent confusion
dupe = true
while dupe
  imagename = toclone.name + "." + rand(36**8).to_s(36)
  dupe = service.images.find {|i| i.name == imagename}
end

# create an image of source server
print "Building image of #{toclone.name}"
image = toclone.create_image(imagename)
image.wait_for(3600, options.interval) { print ".";  STDOUT.flush; ready?}
puts "complete"

# create server from built image, with same flavor as source server
print "Building clone #{options.destname} from image of #{toclone.name}"
server = service.servers.create(:name => options.destname,
                                :flavor_id => toclone.flavor.id,
                                :image_id => image.id)
server.wait_for(600, options.interval) { print "."; STDOUT.flush; ready?}
puts "complete"

# since sometimes the addresses aren't immediately populated when the
# server reaches ready status, wait a few seconds to get that data
while server.ipv4_address == ""
  sleep 1
  server.reload
end

# output clone server information
puts "#{server.name}: IPv4: #{server.ipv4_address} IPv6: #{server.ipv6_address} username: #{server.username} password: #{server.password}"

# remove image if delete flag specified
if options.delete
  puts "Deleting image #{image.name}"
  image.destroy
end
