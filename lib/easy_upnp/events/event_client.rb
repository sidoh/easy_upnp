require 'net/http'

require_relative '../options_base'

module EasyUpnp
  class EventClient
    def initialize(events_endpoint)
      @events_endpoint = URI(events_endpoint)
    end

    def subscribe(callback, timeout: 300)
      req = SubscribeRequest.new(
        @events_endpoint,
        callback,
        timeout
      )

      response = do_request(req)

      if !response['SID']
        raise RuntimeError, "SID header not present in response: #{response.to_hash}"
      end

      SubscribeResponse.new(response)
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

      response = do_request(req)

      SubscribeResponse.new(response)
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

    class SubscribeResponse
      TIMEOUT_HEADER_REGEX = /Second-(\d+)/i

      attr_reader :sid, :timeout

      def initialize(request)
        @sid = request['SID']
        @timeout = TIMEOUT_HEADER_REGEX.match(request['TIMEOUT'])[1].to_i
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
