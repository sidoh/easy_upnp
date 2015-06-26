require 'socket'
require 'ipaddr'
require 'timeout'
require_relative 'upnp_device'

module EasyUpnp
  class SsdpSearcher
    # These are dictated by the SSDP protocol and cannot be changed
    MULTICAST_ADDR = '239.255.255.250'
    MULTICAST_PORT = 1900

    DEFAULT_OPTIONS = {
        :bind_addr => '0.0.0.0',

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

    def option key
      @options[key]
    end

    def search urn
      listen_socket = build_listen_socket
      send_socket = build_send_socket
      packet = construct_msearch_packet(urn)

      # Send M-SEARCH packet over UDP socket
      option(:repeat_queries).times do
        send_socket.send packet, 0, MULTICAST_ADDR, MULTICAST_PORT
      end

      raw_messages = []

      # Wait for responses. Timeout after a specified number of seconds
      begin
        Timeout::timeout(option :timeout) do
          loop do
            raw_messages.push send_socket.recv(4196)
          end
        end
      rescue Timeout::Error
        # This is expected
      ensure
        send_socket.close
        listen_socket.close
      end

      # Parse messages (extract HTTP headers)
      parsed_messages = raw_messages.map { |x| parse_message x }

      # Group messages by device they come from (identified by a UUID in the 'USN' header),
      # and create UpnpDevices for them. This wrap the services advertized by the SSDP
      # results.
      parsed_messages.reject { |x| !x[:usn] }.group_by { |x| x[:usn].split('::').first }.map do |k, v|
        UpnpDevice.new k, v
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

    def parse_message message
      lines = message.split "\r\n"
      headers = lines[1...-1].map do |line|
        header, value = line.match(/([^:]+):\s?(.*)/i).captures

        key = header.
            downcase.
            gsub('-', '_').
            to_sym

        [key, value]
      end
      Hash[headers]
    end

    private

    def build_listen_socket
      socket = UDPSocket.new
      socket.do_not_reverse_lookup = true

      membership = IPAddr.new(MULTICAST_ADDR).hton + IPAddr.new(option :bind_addr).hton

      socket.setsockopt(:IPPROTO_IP, :IP_ADD_MEMBERSHIP, membership)
      socket.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)
      socket.setsockopt(:IPPROTO_IP, :IP_TTL, 1)

      socket.bind(option(:bind_addr), MULTICAST_PORT)

      socket
    end

    def build_send_socket
      socket = UDPSocket.open
      socket.do_not_reverse_lookup = true

      socket.setsockopt(:IPPROTO_IP, :IP_MULTICAST_TTL, true)
      socket.setsockopt(:SOL_SOCKET, :SO_REUSEADDR, true)

      socket
    end
  end
  end
