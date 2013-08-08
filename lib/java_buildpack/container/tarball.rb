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
require 'java_buildpack/util/properties'
require "yaml"

module JavaBuildpack::Container

  class Tarball

    # Creates an instance, passing in an arbitrary collection of options.
    #
    # @param [Hash] context the context that is provided to the instance
    # @option context [String] :app_dir the directory that the application exists in
    # @option context [String] :java_home the directory that acts as +JAVA_HOME+
    # @option context [Array<String>] :java_opts an array that Java options can be added to
    # @option context [Hash] :configuration the properties provided by the user
    def initialize(context = {})
      @app_dir = context[:app_dir]
      @java_home = context[:java_home]
      @java_opts = context[:java_opts]
      @configuration = context[:configuration]
    end

    # Detects whether this application is Java +main()+ application.
    #
    # @return [String] returns +java-main+ if:
    #                  * a +java.main.class+ system property is set by the user
    #                  * a +META-INF/MANIFEST.MF+ file exists and has a +Main-Class+ attribute
    def detect
      File.exists?(File.join(@app_dir, "myapp.tar.gz")) ? CONTAINER_NAME : nil
    end

    # Does nothing as no transformations are required when running Java +main()+ applications.
    #
    # @return [void]
    def compile
      expand
    end

    # Creates the command to run the Java +main()+ application.
    #
    # @return [String] the command to run the application.
    def release
      sed_port = %Q(sed -i "s/dsp\.admin\.webservice\.http\.port=.*/dsp\.admin\.webservice\.http\.port=$PORT/g" #{DSP_HOME}/dsp/config/dsp.core.conf)

      "#{sed_port} && JAVA_HOME=/app/#{@java_home} #{DSP_HOME}/bin/start"
    end

    private

    CONTAINER_NAME = 'tarball'.freeze

    DSP_HOME = '/app/dsp-k-1.2.0'.freeze

    def expand
      system("cd '#{@app_dir}' && tar xzvf #{File.join(@app_dir, "myapp.tar.gz")}")
    end

    def java_opts
      @java_opts.compact.sort.join(' ')
    end

  end

end
