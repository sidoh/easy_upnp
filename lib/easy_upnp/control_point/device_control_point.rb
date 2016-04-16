require 'nokogiri'
require 'open-uri'
require 'nori'

require_relative 'validator_provider'
require_relative 'client_wrapper'
require_relative 'service_method'

module EasyUpnp
  class DeviceControlPoint
    attr_reader :service_endpoint

    class Options
      DEFAULTS = {
        advanced_typecasting: true,
        validate_arguments: false,
        log_enabled: true,
        log_level: :error,
        call_options: {}
      }

      attr_reader :options

      def initialize(o = {}, &block)
        @options = o.merge(DEFAULTS)

        DEFAULTS.map do |k, v|
          define_singleton_method(k) do
            @options[k]
          end

          define_singleton_method("#{k}=") do |v|
            @options[k] = v
          end
        end

        block.call(self) unless block.nil?
      end
    end

    def initialize(urn, service_endpoint, definition, options, &block)
      @urn = urn
      @service_endpoint = service_endpoint
      @definition = definition
      @options = Options.new(options, &block)

      @client = ClientWrapper.new(
        service_endpoint,
        urn,
        call_options: @options.call_options,
        advanced_typecasting: @options.advanced_typecasting,
        log_enabled: @options.log_enabled,
        log_level: @options.log_level
      )

      definition_xml = Nokogiri::XML(definition)
      definition_xml.remove_namespaces!

      @validator_provider = EasyUpnp::ValidatorProvider.from_xml(definition_xml)

      @service_methods = {}
      definition_xml.xpath('//actionList/action').map do |action|
        method = EasyUpnp::ServiceMethod.from_xml(action)
        @service_methods[method.name] = method

        # Adds a method to the class
        define_service_method(method, @client, @validator_provider, @options)
      end
    end

    def to_params
      {
        urn: @urn,
        service_endpoint: @service_endpoint,
        definition: @definition,
        options: @options.options
      }
    end

    def self.from_params(params)
      DeviceControlPoint.new(
          params[:urn],
          params[:service_endpoint],
          params[:definition],
          params[:options]
      )
    end

    def self.from_service_definition(definition, options, &block)
      urn = definition[:st]
      root_uri = definition[:location]

      xml = Nokogiri::XML(open(root_uri))
      xml.remove_namespaces!

      service = xml.xpath("//device/serviceList/service[serviceType=\"#{urn}\"]").first

      if service.nil?
        raise RuntimeError, "Couldn't find service with urn: #{urn}"
      else
        service = Nokogiri::XML(service.to_xml)
        service_definition_uri = URI.join(root_uri, service.xpath('service/SCPDURL').text).to_s
        service_definition = open(service_definition_uri) { |f| f.read }

        DeviceControlPoint.new(
            urn,
            URI.join(root_uri, service.xpath('service/controlURL').text).to_s,
            service_definition,
            options,
            &block
        )
      end
    end

    def arg_validator(method_ref, arg_name)
      arg_ref = service_method(method_ref).arg_reference(arg_name)
      raise ArgumentError, "Unknown argument: #{arg_name}" if arg_ref.nil?

      @validator_provider.validator(arg_ref)
    end

    def method_args(method_ref)
      service_method(method_ref).in_args
    end

    def service_method(method_ref)
      method = @service_methods[method_ref]
      raise ArgumentError, "Unknown method: #{method_ref}" if method.nil?

      method
    end

    def service_methods
      @service_methods.keys
    end

    private

    def define_service_method(method, client, validator_provider, options)
      if !options.validate_arguments
        validator_provider = EasyUpnp::ValidatorProvider.no_op_provider
      end

      define_singleton_method(method.name) do |args_hash = {}|
        method.call_method(client, args_hash, validator_provider)
      end
    end
  end
end
