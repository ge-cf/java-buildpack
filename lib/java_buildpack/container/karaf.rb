# Cloud Foundry Java Buildpack
# Copyright (c) 2013 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'java_buildpack/container'
require 'java_buildpack/util/application_cache'
require 'java_buildpack/util/format_duration'
require 'yaml'

module JavaBuildpack::Container

  # Encapsulates the detect, compile, and release functionality for Karaf OSGi bundles.
  class Karaf

    # Creates an instance, passing in an arbitrary collection of options.
    #
    # @param [Hash] context the context that is provided to the instance
    # @option context [String] :app_dir the directory that the application exists in
    # @option context [String] :java_home the directory that acts as +JAVA_HOME+
    # @option context [Array<String>] :java_opts an array that Java options can be added to
    # @option context [Hash] :configuration the properties provided by the user
    def initialize(context)
      @app_dir = context[:app_dir]
      @java_home = context[:java_home]
      @java_opts = context[:java_opts]
      @configuration = context[:configuration]
      @version = VERSION
      @uri = DOWNLOAD_URI
    end

    # Detects whether this application is an OSGi bundle for the Karaf container.
    #
    # @return [String] returns +karaf-<version>+ if and only if a +META-INF/MANIFEST.MF+ file exists and has
    #                  +Export-Package+ and +Import-Package+ attributes
    def detect
      File.exists?(File.join(@app_dir, CONFIG_FILE)) ? CONTAINER_NAME : nil
    end

    # Downloads and unpacks a Karaf container
    #
    # @return [void]
    def compile
      download_start_time = Time.now
      print "-----> Downloading Karaf #{@version} from #{@uri} "

      JavaBuildpack::Util::ApplicationCache.new.get(@uri) do |file|  # TODO Use global cache #50175265
        puts "(#{(Time.now - download_start_time).duration})"
        expand file
      end

      configure
      deploy_bundles
    end

    # Creates the command to run the Karaf application.
    #
    # @return [String] the command to run the application.
    def release
      @java_opts << "-D#{KEY_HTTP_PORT}=$PORT"

      "JAVA_HOME=/app/#{@java_home} JAVA_OPTS=\"#{java_opts}\" KARAF_BASE=/app/#{KARAF_HOME} KARAF_DATA=/app/#{KARAF_HOME}/data #{KARAF_HOME}/bin/karaf server"
    end

    private

    KEY_HTTP_PORT = 'http.port'.freeze

    VERSION = '2.3.1'.freeze

    DOWNLOAD_URI = "http://apache.claz.org/karaf/#{VERSION}/apache-karaf-#{VERSION}.tar.gz".freeze

    KARAF_HOME = '.karaf'.freeze

    CONTAINER_NAME = "karaf-#{VERSION}".freeze

    CONFIG_FILE = "karaf.yml".freeze

    def expand(file)
      expand_start_time = Time.now
      print "-----> Expanding Karaf to #{KARAF_HOME} "

      system "rm -rf #{karaf_home}"
      system "mkdir -p #{karaf_home}"
      system "mkdir -p #{karaf_home}/data/log"
      system "tar xzf #{file.path} -C #{karaf_home} --strip 1 --exclude demos --exclude karaf-manual-* 2>&1"

      puts "(#{(Time.now - expand_start_time).duration})"
    end

    def configure
      set_property_in_file "#{karaf_home}/etc/org.ops4j.pax.web.cfg", 'org.osgi.service.http.port' do ||
        '${http.port}'
      end

      config = YAML.load(File.open(File.join(@app_dir, CONFIG_FILE)))
      features = config["features"]

      if features
        puts "-----> Adding boot features #{features}"
        set_property_in_file "#{karaf_home}/etc/org.apache.karaf.features.cfg", 'featuresBoot' do |value|
          value + ',' + features
        end
      end
    end

    def deploy_bundles
      Dir.glob(File.join(@app_dir, "**", "*.jar")).each do |path|
        puts "-----> Deploying jar file #{File.basename(path)} "
        system "mv #{path} #{karaf_home}/deploy"
      end
    end

    def java_opts
      @java_opts.compact.sort.join(' ')
    end

    def karaf_home
      File.join @app_dir, KARAF_HOME
    end

    def manifest
      manifest_file = File.join(@app_dir, 'META-INF', 'MANIFEST.MF')
      manifest_file = File.exists?(manifest_file) ? manifest_file : nil
      JavaBuildpack::Util::Properties.new(manifest_file)
    end

    def set_property_in_file(filename, key)
      property_set = false

      if File.exists? filename
        backup_filename = "#{filename}.bak"
        File.rename(filename, backup_filename)

        File.open(filename, 'w') do |file|
          File.open(backup_filename, 'r').each do |line|
            property = line.split('=', 2)
            if property.length == 2 && property[0] == key
              value = yield(property[1].strip)
              file.puts "#{property[0]}=#{value}"
              property_set = true
            else
              file.puts line
            end
          end
        end
      end

      if !property_set
        File.open(filename, 'a') do |file|
          value = yield("")
          file.puts "#{key}=#{value}"
        end
      end

    end
  end

end
