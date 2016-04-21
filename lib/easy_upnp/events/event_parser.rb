require 'nokogiri'

module EasyUpnp
  class EventParser
    def parse(event_xml)
      x = Nokogiri::XML(event_xml)
      prop_changes = x.xpath('//e:propertyset/e:property/*', e: 'urn:schemas-upnp-org:event-1-0').map do |n|
        [n.name.to_sym, n.text]
      end

      Hash[prop_changes]
    end
  end
end
