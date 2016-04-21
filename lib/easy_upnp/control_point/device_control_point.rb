require 'nokogiri'
require 'open-uri'
require 'nori'

require 'easy_upnp/control_point/validator_provider'
require 'easy_upnp/control_point/client_wrapper'
require 'easy_upnp/control_point/service_method'

require 'easy_upnp/events/event_client'
require 'easy_upnp/events/http_listener'
require 'easy_upnp/events/subscription_manager'

module EasyUpnp
  class DeviceControlPoint
    attr_reader :event_vars, :service_endpoint, :events_endpoint

    class Options < EasyUpnp::OptionsBase
      DEFAULTS = {
        advanced_typecasting: true,
        validate_arguments: false,
        log_enabled: true,
        log_level: :error,
        call_options: {}
      }

      def initialize(o = {}, &block)
        super(o, DEFAULTS, &block)
      end
    end

    class EventConfigOptions < EasyUpnp::OptionsBase
      DEFAULTS = {
        configure_http_listener: ->(c) { },
        configure_subscription_manager: ->(c) { }
      }

      def initialize(&block)
        super({}, DEFAULTS, &block)
      end
    end

    def initialize(urn, service_endpoint, events_endpoint, definition, options, &block)
      @urn = urn
      @service_endpoint = service_endpoint
      @definition = definition
      @options = Options.new(options, &block)

      @events_endpoint = events_endpoint
      @events_client = EasyUpnp::EventClient.new(events_endpoint)

      @client = ClientWrapper.new(
        service_endpoint,
        urn,
        @options.call_options,
        @options.advanced_typecasting,
        @options.log_enabled,
        @options.log_level
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

      @event_vars = definition_xml.
        xpath('//serviceStateTable/stateVariable[@sendEvents = "yes"]/name').
        map(&:text).
        map(&:to_sym)
    end

    def to_params
      {
        urn: @urn,
        service_endpoint: @service_endpoint,
        events_endpoint: @events_endpoint,
        definition: @definition,
        options: @options.options
      }
    end

    def self.from_params(params)
      DeviceControlPoint.new(
          params[:urn],
          params[:service_endpoint],
          params[:events_endpoint],
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

        endpoint_url = ->(xpath) do
          URI.join(root_uri, service.xpath(xpath).text).to_s
        end

        DeviceControlPoint.new(
            urn,
            endpoint_url.call('service/controlURL'),
            endpoint_url.call('service/eventSubURL'),
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

    def add_event_callback(url, &block)
      manager = EasyUpnp::SubscriptionManager.new(@events_client, url, &block)
      manager.subscribe
      manager
    end

    def on_event(callback, &block)
      raise ArgumentError, 'Must provide block' if callback.nil?

      options = EventConfigOptions.new(&block)

      listener = EasyUpnp::HttpListener.new do |c|
        options.configure_http_listener.call(c)

        # It'd be kinda weird if a user set this (since a callback is taken as
        # an argument to the `on_event` method), but it'd be even weirder if
        # we ignored it.
        user_callback = c.callback
        c.callback do |r|
          user_callback.call(r) if user_callback
          callback.call(r)
        end
      end

      # exposing the URL as a lambda allows the subscription manager to get a
      # new URL should the server stop and start again on a different port.
      url = ->() { listener.listen }

      manager = EasyUpnp::SubscriptionManager.new(@events_client, url) do |c|
        options.configure_subscription_manager.call(c)

        user_shutdown = c.on_shutdown
        c.on_shutdown = ->() do
          user_shutdown.call if user_shutdown
          listener.shutdown
        end
      end

      manager.subscribe
      manager
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
