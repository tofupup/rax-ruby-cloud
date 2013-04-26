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
Challenge 8
Write a script that will create a static webpage served out of Cloud
Files. The script must create a new container, cdn enable it, enable
it to serve an index file, create an index file object, upload the
object to the container, and create a CNAME record pointing to the
CDN URL of the container.
Worth 3 Points
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
options.name = "index.html"
options.dc = :dfw
options.container = nil
options.fqdn = nil

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge8.rb [options] container fqdn"
  opts.on('-i', '--index NAME', 'Use NAME for index file') {|n| options.name = n}
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

# must specify a container and fqdn
if ARGV.length != 2
  p optparse
  exit
end

options.container = ARGV.shift
options.fqdn = ARGV.shift

# insure fqdn is proper length
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

# check if domain exists
zone = dnsservice.zones.find {|z| z.domain == domain}
if zone == nil
  puts "Zone #{domain} does not exist.  Exiting..."
  exit
end

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

# create container with pointer to index file
container = service.directories.create(
  :key => options.container,
  :public => true,
  :metadata => {"Web-Index" => options.name})

# create an index file
file = container.files.create(:key => options.name, :body => "<html><h1>Howdy Rackers!</h1></html>")

puts "Public container #{options.container} created.  URL #{container.public_url}"

# create a CNAME pointing to the URL of the container
begin
  record = zone.records.create(
    :value => container.public_url,
    :name => options.fqdn,
    :type => 'CNAME')
  puts "CNAME created.  New URL http://#{record.name}/"
rescue Fog::DNS::Rackspace::CallbackError # cname already exists
  puts "CNAME record for #{options.fqdn} already exist.  Please specify new CNAME"
  exit
end
