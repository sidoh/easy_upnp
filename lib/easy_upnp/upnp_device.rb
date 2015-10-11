require 'uri'
require 'nokogiri'
require 'open-uri'
require 'savon'

require_relative 'device_control_point'

module EasyUpnp
  class UpnpDevice
    attr_reader :uuid, :name, :host

    def initialize uuid, messages
      @uuid = uuid
      @service_definitions = messages.
          # Filter out messages that aren't service definitions. These include
          # the root device and the root UUID
          reject { |message| not message[:st].include? ':service:' }.
          # Distinct by ST header -- might have repeats if we sent multiple
          # M-SEARCH packets
          group_by { |message| message[:st] }.
          map { |_, matching_messages| matching_messages.first }.
          map do |message|
            {
                :location => message[:location],
                :st => message[:st]
            }
          end

      # Download one of the definitions to get the name of this device
      if @service_definitions.any?
        service_location = @service_definitions.first[:location]

        xml = Nokogiri::XML(open(service_location))
        xml.remove_namespaces!
        @name = xml.xpath('//device/friendlyName').text
        @host = URI.parse(service_location).host
      else
        @name = 'UNKNOWN'
        @host = 'UNKNOWN'
      end
    end

    def all_services
      @service_definitions.map { |x| x[:st] }
    end

    def has_service?(urn)
      !service_definition(urn).nil?
    end

    def service(urn, options = {})
      definition = service_definition(urn)

      if !definition.nil?
        root_uri = definition[:location]
        xml = Nokogiri::XML(open(root_uri))
        xml.remove_namespaces!

        service = xml.xpath("//device/serviceList/service[serviceType=\"#{urn}\"]").first

        if service.nil?
          raise RuntimeError.new "Couldn't find service with urn: #{urn}"
        else
          service = Nokogiri::XML(service.to_xml)
          wsdl = URI.join(root_uri, service.xpath('service/SCPDURL').text).to_s

          client = Savon.client do |c|
            c.endpoint URI.join(root_uri, service.xpath('service/controlURL').text).to_s

            c.namespace urn

            # I found this was necessary on some of my UPnP devices (namely, a Sony TV).
            c.namespaces({:'s:encodingStyle' => "http://schemas.xmlsoap.org/soap/encoding/"})

            # This makes XML tags be like <ObjectID> instead of <objectID>.
            c.convert_request_keys_to :camelcase

            c.namespace_identifier :u
            c.env_namespace :s
          end

          DeviceControlPoint.new client, urn, wsdl, options
        end
      end
    end

    def service_definition(urn)
      @service_definitions.
          reject { |s| s[:st] != urn }.
          first
    end
  end
end