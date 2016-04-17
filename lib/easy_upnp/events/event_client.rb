require 'net/http'

require_relative '../options_base'

module EasyUpnp
  class EventClient
    def initialize(events_endpoint, callback_url)
      @events_endpoint = URI(events_endpoint)
      @callback_url = callback_url
    end

    def subscribe(timeout: 300)
      req = SubscribeRequest.new(
        @events_endpoint,
        @callback_url,
        timeout
      )

      response = do_request(req)

      if !response['SID']
        raise RuntimeError, "SID header not present in response: #{response.to_hash}"
      end

      response['SID']
    end

    def unsubscribe(sid)
      req = UnsubscribeRequest.new(
        @events_endpoint,
        sid
      )
      do_request(req)
      true
    end

    def resubscribe(sid, timeout: 300)
      req = ResubscribeRequest.new(
        @events_endpoint,
        sid,
        timeout
      )
      do_request(req)
      true
    end

    private

    def do_request(req)
      uri = URI(@events_endpoint)
      Net::HTTP.start(uri.host, uri.port) do |http|
        response = http.request(req)

        if response.code.to_i != 200
          raise RuntimeError, "Unexpected response type (#{response.code}): #{response.body}"
        end

        return response
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
      RESPONSE_HAS_BODY = true

      def initialize(event_url, sid, timeout)
        super(URI(event_url))
        self.timeout = timeout
        self.sid = sid
      end
    end

    class SubscribeRequest < EventRequest
      METHOD = 'SUBSCRIBE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = true

      def initialize(event_url, callback_url, timeout)
        super(URI(event_url))
        self.timeout = timeout
        self.callback = callback_url
      end
    end

    class UnsubscribeRequest < EventRequest
      METHOD = 'UNSUBSCRIBE'
      REQUEST_HAS_BODY = false
      RESPONSE_HAS_BODY = true

      def initialize(event_url, sid)
        super(URI(event_url))
        self.sid = sid
      end
    end
  end
end
