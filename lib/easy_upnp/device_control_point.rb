require 'nokogiri'
require 'open-uri'
require 'nori'

require_relative 'logger'
require_relative 'argument_validator'

module EasyUpnp
  class DeviceControlPoint
    attr_reader :service_methods, :service_endpoint

    class Options
      DEFAULTS = {
        advanced_typecasting: true,
        validate_arguments: false
      }

      attr_reader :options

      def initialize(o = {}, &block)
        @options = o.merge(DEFAULTS)

        @options.map do |k, v|
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

    def initialize(urn, service_endpoint, definition, call_options, &block)
      @urn = urn
      @service_endpoint = service_endpoint
      @call_options = call_options
      @definition = definition
      @options = Options.new(&block)

      @client = Savon.client(log: EasyUpnp::Log.enabled?, log_level: EasyUpnp::Log.level) do |c|
        c.endpoint service_endpoint
        c.namespace urn

        # I found this was necessary on some of my UPnP devices (namely, a Sony TV).
        c.namespaces({:'s:encodingStyle' => "http://schemas.xmlsoap.org/soap/encoding/"})

        # This makes XML tags be like <ObjectID> instead of <objectID>.
        c.convert_request_keys_to :camelcase

        c.namespace_identifier :u
        c.env_namespace :s
      end

      definition_xml = Nokogiri::XML(definition)
      definition_xml.remove_namespaces!

      service_methods = []
      service_methods_args = {}
      definition_xml.xpath('//actionList/action').map do |action|
        service_methods.push(define_action(action))

        name = action.xpath('name').text
        args = {}
        action.xpath('argumentList/argument').map do |arg|
          arg_name = arg.xpath('name').text
          arg_ref = arg.xpath('relatedStateVariable').text
          args[arg_name.to_sym] = arg_ref.to_sym
        end
        service_methods_args[name.to_sym] = args
      end

      arg_validators = {}
      definition_xml.xpath('//serviceStateTable/stateVariable').map do |var|
        name = var.xpath('name').text
        arg_validators[name.to_sym] = extract_validators(var)
      end

      @service_methods = service_methods
      @service_methods_args = service_methods_args
      @arg_validators = arg_validators
    end

    def to_params
      {
        urn: @urn,
        service_endpoint: @service_endpoint,
        definition: @definition,
        call_options: @call_options,
        options: @options.options
      }
    end

    def self.from_params(params)
      DeviceControlPoint.new(
          params[:urn],
          params[:service_endpoint],
          params[:definition],
          params[:call_options]
      ) { |c|
        params[:options].map { |k, v| c.options[k] = v }
      }
    end

    def self.from_service_definition(definition, call_options = {}, &block)
      urn = definition[:st]
      root_uri = definition[:location]

      xml = Nokogiri::XML(open(root_uri))
      xml.remove_namespaces!

      service = xml.xpath("//device/serviceList/service[serviceType=\"#{urn}\"]").first

      if service.nil?
        raise RuntimeError.new "Couldn't find service with urn: #{urn}"
      else
        service = Nokogiri::XML(service.to_xml)
        service_definition_uri = URI.join(root_uri, service.xpath('service/SCPDURL').text).to_s
        service_definition = open(service_definition_uri) { |f| f.read }

        DeviceControlPoint.new(
            urn,
            URI.join(root_uri, service.xpath('service/controlURL').text).to_s,
            service_definition,
            call_options,
            &block
        )
      end
    end

    def arg_validator(method, arg)
      method_args = @service_methods_args[method.to_sym]
      raise ArgumentError, "Unknown method: #{method}" if method_args.nil?

      arg_ref = method_args[arg.to_sym]
      raise ArgumentValidator, "Unknown argument: #{arg}" if arg_ref.nil?

      @arg_validators[arg_ref]
    end

    private

    def extract_validators(var)
      ArgumentValidator.build do |v|
        v.type(var.xpath('dataType').text)

        if (range = var.xpath('allowedValueRange')).any?
          min = range.xpath('minimum').text
          max = range.xpath('maximum').text
          step = range.xpath('step')
          step = step.any? ? step.text : 1

          v.in_range(min.to_i, max.to_i, step.to_i)
        end

        if (list = var.xpath('allowedValueList')).any?
          allowed_values = list.xpath('allowedValue').map { |x| x.text }
          v.allowed_values(*allowed_values)
        end
      end
    end

    def define_action(action)
      action = Nori.new.parse(action.to_xml)['action']
      action_name = action['name']
      args = action['argumentList']['argument']
      args = [args] unless args.is_a? Array

      input_args = args.
          reject { |x| x['direction'] != 'in' }.
          map { |x| x['name'].to_sym }
      output_args = args.
          reject { |x| x['direction'] != 'out' }.
          map { |x| x['name'].to_sym }

      define_singleton_method(action['name']) do |args_hash = {}|
        if !args_hash.is_a? Hash
          raise RuntimeError.new "Input arg must be a hash"
        end

        args_hash = args_hash.inject({}) { |m,(k,v)| m[k.to_sym] = v; m }

        if (args_hash.keys - input_args).any?
          raise RuntimeError.new "Unsupported arguments: #{(args_hash.keys - input_args)}." <<
                                     " Supported args: #{input_args}"
        end

        if @options.validate_arguments
          args_hash.each { |k,v|
            begin
              arg_validator(action['name'], k).validate(v)
            rescue ArgumentError => e
              raise ArgumentError, "Invalid value for argument #{k}: #{e}"
            end
          }
        end

        attrs = {
            soap_action: "#{@urn}##{action_name}",
            attributes: {
                :'xmlns:u' => @urn
            },
        }.merge(@call_options)

        options = @options
        response = @client.call action['name'], attrs do
          advanced_typecasting options.advanced_typecasting
          message(args_hash)
        end

        # Response is usually wrapped in <#{ActionName}Response></>. For example:
        # <BrowseResponse>...</BrowseResponse>. Extract the body since consumers
        # won't care about wrapper stuff.
        if response.body.keys.count > 1
          raise RuntimeError.new "Unexpected keys in response body: #{response.body.keys}"
        end
        result = response.body.first[1]
        output = {}

        # Keys returned by savon are underscore style. Convert them to camelcase.
        output_args.map do |arg|
          output[arg] = result[underscore(arg.to_s).to_sym]
        end

        output
      end

      action['name']
    end

    # This is included in ActiveSupport, but don't want to pull that in for just this method...
    def underscore s
      s.gsub(/::/, '/').
          gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
          gsub(/([a-z\d])([A-Z])/, '\1_\2').
          tr("-", "_").
          downcase
    end
  end
end
