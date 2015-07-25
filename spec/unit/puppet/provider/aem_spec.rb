#!/usr/bin/env ruby

require 'spec_helper'
require 'puppet/type/aem'
require 'puppet/provider/aem'

describe Puppet::Provider::AEM do

  let(:source) { '/opt/aem/cq-author-4502.jar' }

  let(:resource) {
    allow(File).to receive(:file?).with(any_args).at_least(1).and_call_original
    expect(File).to receive(:file?).with(source).and_return(true)
    allow(File).to receive(:directory?).with(any_args).at_least(1).and_call_original
    expect(File).to receive(:directory?).with('/opt/aem').and_return(true)
    Puppet::Type.type(:aem).new({
      :name     => 'foo',
      :ensure   => :present,
      :source   => source,
      :version  => '6.1',
      :home     => '/opt/aem',
      :provider => :simple,
    })
  }

  let(:defaults) {
    {
      :port               => 4502,
      :type               => :author,
      :runmodes           => '',
      :jvm_mem_opts       => '-Xmx1024m -XX:MaxPermSize=256M',
      :sample_content     => :true
    }
  }

  before do
    @provider_class = Puppet::Type.type(:aem).provide(:simple, :parent => :linux)
    @provider_class.stubs(:suitable?).returns true
    Puppet::Type.type(:aem).stubs(:defaultprovider).returns @provider_class

  end

  before :each do
    described_class.stubs(:which).with('find').returns('/bin/find')
    described_class.stubs(:which).with('java').returns('/usr/bin/java')
  end

  let(:mock_file) { double('File') }

  describe 'self.prefetch' do
    it 'should respond' do
      expect(described_class).to respond_to(:prefetch)
    end
  end

  describe 'exists?' do

    shared_examples 'exists_check' do |opts|
      it {
        provider = @provider_class.new( { :ensure => opts[:ensure] })
        expect( provider.exists? ).to eq(opts[:present])
      }
    end

    describe 'ensure is absent' do
      it_should_behave_like 'exists_check', :ensure => :absent, :present => false
    end

    describe 'ensure is present' do
      it_should_behave_like 'exists_check', :ensure => :present, :present => true
    end

  end

  describe 'destroy' do
    it 'should remove quickstart folder' do
      expect(File).to receive(:join).with('/opt/aem', 'crx-quickstart').and_call_original
      expect(FileUtils).to receive(:remove_entry_secure)
      provider = @provider_class.new
      provider.resource = resource
      provider.destroy
    end

  end

  describe 'start-env' do
    it 'should have default values' do

      expect(Puppet::Parser::Files).to receive(:find_template).and_return('templates/start-env.erb')
      envfile = File.join(resource[:home], 'crx-quickstart', 'bin', 'start-env')
      expect(File).to receive(:new).with(envfile, any_args).and_return(mock_file)
      expect(mock_file).to receive(:write) do |contents|

        match = /PORT=(#{defaults[:port]})/.match(contents).captures
        expect(match).to_not be(nil)

        match = /TYPE=(#{defaults[:type]})/.match(contents).captures
        expect(match).to_not be(nil)

        match = /RUNMODES='(.*?)'/.match(contents).captures
        expect(match[0]).to eq("")

        match = /SAMPLE_CONTENT='(.*?)'\n/.match(contents).captures
        expect(match[0]).to eq("")

        match = /DEBUG_PORT=(\d*)\n/.match(contents).captures
        expect(match[0]).to eq("")

        match = /CONTEXT_ROOT/.match(contents)
        expect(match).to be(nil)

        match = /JVM_MEM_OPTS='(#{defaults[:jvm_mem_opts]})'/.match(contents).captures
        expect(match).to_not be(nil)

        match = /\sJVM_OPTS='(.*?)'\s/.match(contents).captures
        expect(match[0]).to eq("")

      end.and_return(0)

      expect(mock_file).to receive(:close)
      expect(File).to receive(:chmod).with(0750, any_args).and_return(0)
      expect(File).to receive(:chown).with(any_args)

      provider = @provider_class.new
      provider.resource = resource
      provider.flush

    end
  end

  describe 'property updates' do
    shared_examples 'update_env' do |opts|
      it {

        # Updates the env file
        expect(Puppet::Parser::Files).to receive(:find_template).and_return('templates/start-env.erb')
        envfile = File.join(resource[:home], 'crx-quickstart', 'bin', 'start-env')
        expect(File).to receive(:new).with(envfile, any_args).and_return(mock_file)
        expect(mock_file).to receive(:write) do |contents|

          if value = opts[:port]
            match = /PORT=(#{value})/.match(contents).captures
            expect(match).to_not be(nil)
          end

          if value = opts[:runmodes]
            value = value.is_a?(Array) ? value.join(',') : value
            match = /RUNMODES='(#{value})'/.match(contents).captures
            expect(match).to_not be(nil)
          end

          if opts[:sample_content] == :false
            match = /SAMPLE_CONTENT='(#{Puppet::Provider::AEM::NO_SAMPLE_CONTENT})'/.match(contents).captures
            expect(match).to_not be(nil)
          end

          if value = opts[:debug_port]
            match = /DEBUG_PORT=(#{value})\n/.match(contents).captures
            expect(match[0]).to_not be(nil)
          end

          if value = opts[:context_root]
            match = /CONTEXT_ROOT='(#{value})'/.match(contents).captures
            expect(match).to_not be(nil)
          else
            match = /CONTEXT_ROOT/.match(contents)
            expect(match).to be(nil)
          end

          if value = opts[:jvm_mem_opts]
            match = /JVM_MEM_OPTS='(#{value})'/.match(contents).captures
            expect(match).to_not be(nil)
          end

          if value = opts[:jvm_opts]
            match = /\sJVM_OPTS='(#{value})'\s/.match(contents).captures
            expect(match[0]).to eq(value)
          end

        end.and_return(0)

        expect(mock_file).to receive(:close)
        expect(File).to receive(:chmod).with(0750, any_args).and_return(0)
        expect(File).to receive(:chown).with(any_args)

        provider = @provider_class.new
        provider.resource = resource

        opts.each do |k, v|
          resource[k] = v
        end

        provider.flush
        expect(provider.properties).to eq(resource.to_hash)

        opts.each do |k, v|
          expect(provider.properties[k]).to eq(v)
        end
      }
    end

    describe 'update port' do
      it_should_behave_like 'update_env', :port => 8080
    end

    describe 'update runmode' do
      it_should_behave_like 'update_env', :runmodes => ['production']
    end

    describe 'update runmodes' do
      it_should_behave_like 'update_env', :runmodes => ['dev', 'stage', 'client', 'vml']
    end

    describe 'update sample content' do
      it_should_behave_like 'update_env', :sample_content => :false
    end

    describe 'update debug port' do
      it_should_behave_like 'update_env', :debug_port => 12345
    end

    describe 'update context root' do
      it_should_behave_like 'update_env', :context_root => 'contextroot'
    end

    describe 'update jvm memory' do
      it_should_behave_like 'update_env', :jvm_mem_opts => '-Xmx2048m -XX:MaxPermSize=512m'
    end

    describe 'update jvm opts' do
      it_should_behave_like 'update_env', :jvm_opts => '-Dsome.jvm.option=somevalue'
    end
  end

end