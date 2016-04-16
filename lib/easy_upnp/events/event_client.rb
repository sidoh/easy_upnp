require 'net/http'

require_relative '../options_base'

module EasyUpnp
  class EventClient
    class Options < EasyUpnp::OptionsBase
      DEFAULTS = {
        timeout: 300
      }

      def initialize(options, &block)
        super(options, DEFAULTS, &block)
      end
    end

    def initialize(events_endpoint, callback_url, options = {}, &block)
      @options = Options.new(options, &block)
      @events_endpoint = URI(events_endpoint)
      @callback_url = callback_url
    end

    def subscribe
      req = SubscribeRequest.new(
        @events_endpoint,
        @callback_url,
        @options.timeout
      )
      do_request(req)['sid']
    end

    def unsubscribe(sid)
      req = UnsubscribeRequest.new(
        @events_endpoint,
        sid
      )
      do_request(req)
    end

    def resubscribe
    end

    private

    def do_request(req)
      uri = URI(@events_endpoint)
      Net::HTTP.start(uri.host, uri.port) do |http|
        puts req.inspect
        puts req.to_hash
        return http.request(req)
      end
    end

    class EventRequest < Net::HTTPRequest

      def timeout=(v)
        self['TIMEOUT'] = "Second-#{v}"
      end

      def callback=(v)
        self['CALLBACK'] = "<#{v}>"
        self['NT'] = 'upnp:event'
      end

      def sid=(v)
        self['SID'] = v
      end
    end

    class ResubscribeRequest < EventRequest
      METHOD = 'SUBSCRIBE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = false

      def initialize(event_url, sid, timeout)
        super(URI(event_url))
        self.timeout = timeout
        self.sid = sid
      end
    end

    class SubscribeRequest < EventRequest
      METHOD = 'SUBSCRIBE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = false

      def initialize(event_url, callback_url, timeout)
        super(URI(event_url))
        self.timeout = timeout
        self.callback = callback_url
      end
    end

    class UnsubscribeRequest < EventRequest
      METHOD = 'UNSUBSCRIBE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = false

      def initialize(event_url, sid)
        super(URI(event_url))
        self.sid = sid
      end
    end
  end
end
