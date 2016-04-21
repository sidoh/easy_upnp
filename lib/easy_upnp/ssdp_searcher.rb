require 'socket'
require 'ipaddr'
require 'timeout'

require 'easy_upnp/upnp_device'

module EasyUpnp
  class SsdpSearcher
    # These are dictated by the SSDP protocol and cannot be changed
    MULTICAST_ADDR = '239.255.255.250'
    MULTICAST_PORT = 1900

    DEFAULT_OPTIONS = {
        # Number of seconds to wait for responses
        :timeout => 2,

        # Part of the SSDP protocol. Servers should delay a random amount of time between 0 and N
        # seconds before sending the response.
        :mx => 1,

        # Sometimes recommended to send repeat M-SEARCH queries. Control that here.
        :repeat_queries => 1
    }

    def initialize(options = {})
      unsupported_args = options.keys.reject { |x| DEFAULT_OPTIONS[x] }
      raise RuntimeError.new "Unsupported arguments: #{unsupported_args}" if unsupported_args.any?

      @options = DEFAULT_OPTIONS.merge options
    end

    def option(key)
      @options[key]
    end

    def search(urn = 'ssdp:all')
      socket = build_socket
      packet = construct_msearch_packet(urn)

      # Send M-SEARCH packet over UDP socket
      option(:repeat_queries).times do
        socket.send packet, 0, MULTICAST_ADDR, MULTICAST_PORT
      end

      raw_messages = []

      # Wait for responses. Timeout after a specified number of seconds
      begin
        Timeout::timeout(option :timeout) do
          loop do
            raw_messages.push(socket.recv(4196))
          end
        end
      rescue Timeout::Error
        # This is expected
      ensure
        socket.close
      end

      # Parse messages (extract HTTP headers)
      parsed_messages = raw_messages.map { |x| parse_message x }

      # Group messages by device they come from (identified by a UUID in the 'USN' header),
      # and create UpnpDevices for them. This wrap the services advertized by the SSDP
      # results.
      parsed_messages.reject { |x| !x[:usn] }.group_by { |x| x[:usn].split('::').first }.map do |k, v|
        UpnpDevice.from_ssdp_messages(k, v)
      end
    end

    def construct_msearch_packet(urn)
      <<-MSEARCH
M-SEARCH * HTTP/1.1\r
HOST: #{MULTICAST_ADDR}:#{MULTICAST_PORT}\r
MAN: "ssdp:discover"\r
MX: #{option :mx}\r
ST: #{urn}\r
\r
      MSEARCH
    end

    def parse_message(message)
      lines = message.split "\r\n"
      headers = lines.map do |line|
        if !(match = line.match(/([^:]+):\s?(.*)/i)).nil?
          header, value = match.captures
          key = header.
              downcase.
              gsub('-', '_').
              to_sym

          [key, value]
        end
      end

      Hash[headers.reject(&:nil?)]
    end

    private

    def build_socket
      socket = UDPSocket.open
      socket.do_not_reverse_lookup = true

      socket.setsockopt(:IPPROTO_IP, :IP_MULTICAST_TTL, true)
      socket.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)

      socket
    end
  end
end
