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
Challenge 3
Write a script that accepts a directory as an argument as well as a
container name. The script should upload the contents of the specified
directory to the container (or create it if it doesn't exist). The
script should handle errors appropriately. (Check for invalid paths,
etc.)
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
options.srcdir = nil
options.dc = :dfw
options.container = nil
options.create = true

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: challenge3.rb [options] srcdir container"
  opts.on('--nocreate', 'Do not create desination container if it does not exist') {options.create = false}
  opts.on('--datacenter DC', [:dfw, :ord], 'Create server in datacenter (dfw, ord)') {|dc| options.dc = dc}
  opts.on('-h','--help','Show help') {puts opts; exit}
end
optparse.parse!

# must specify a name for the cloned server
if ARGV.length != 2
  p optparse
  exit
end

options.srcdir = ARGV.shift
options.container = ARGV.shift

if not File.directory?(options.srcdir)
  puts "Source directory must exist"
  exit
end

# create Cloud Files storage service
service = Fog::Storage.new({
  :provider             => 'rackspace',
  :rackspace_username   => rackspace_username,
  :rackspace_api_key    => rackspace_api_key,
  :rackspace_region => options.dc #Use specified region
})

container = service.directories.get(options.container)
if (container == nil) && (not options.create)
  puts "Container #{options.container} does not exist and nocreate is set"
  exit
end

container = service.directories.create(:key => options.container) if container == nil

puts "Uploading all files from directory #{options.srcdir} to container #{options.container}"
Dir.foreach(options.srcdir) do |file|
  next if file == '.' or file == '..' or File.directory?(file)
  puts "Uploading #{file}"
  container.files.create(:key => file, :body => File.open(file))
end
