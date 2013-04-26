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
Challenge 6
Write a script that creates a CDN-enabled container in Cloud Files.
Worth 1 Point
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
options.dc = :dfw
options.container = nil

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge6.rb [options] container"
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

# must specify a name for the cloned server
if ARGV.length != 1
  p optparse
  exit
end

options.container = ARGV.shift

# create Cloud Files storage service
service = Fog::Storage.new({
  :provider             => 'rackspace',
  :rackspace_username   => rackspace_username,
  :rackspace_api_key    => rackspace_api_key,
  :rackspace_region => options.dc #Use specified region
})

# check if container exists
container = service.directories.get(options.container)
if container
  puts "Container #{options.container} already exists.  Exiting..."
  exit
end

# create public container
container = service.directories.create(
  :key => options.container,
  :public => true)

puts "Public container #{options.container} created"