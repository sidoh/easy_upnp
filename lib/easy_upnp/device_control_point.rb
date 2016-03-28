require 'nokogiri'
require 'open-uri'
require 'nori'

require_relative 'logger'

module EasyUpnp
  class DeviceControlPoint
    attr_reader :service_methods, :service_endpoint

    def initialize(urn, service_endpoint, definition, options)
      @urn = urn
      @service_endpoint = service_endpoint
      @options = options
      @definition = definition

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
      definition_xml.xpath('//actionList/action').map do |action|
        service_methods.push define_action(action)
      end

      @service_methods = service_methods
    end

    def to_params
      {
        urn: @urn,
        service_endpoint: @service_endpoint,
        definition: @definition,
        options: @options
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

    def self.from_service_definition(definition, options = {})
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
            options
        )
      end
    end

    private

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

        attrs = {
            soap_action: "#{@urn}##{action_name}",
            attributes: {
                :'xmlns:u' => @urn
            },
        }.merge(@options)

        response = @client.call action['name'], attrs do
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
