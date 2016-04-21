require 'webrick'
require 'thread'

require 'easy_upnp/events/event_parser'

module EasyUpnp
  class HttpListener
    class Options < EasyUpnp::OptionsBase
      DEFAULTS = {
        # Port to listen on. Default value "0" will cause OS to choose a random
        # ephemeral port
        listen_port: 0,

        # Address to bind listener on. Default value binds to all IPv4
        # interfaces.
        bind_address: '0.0.0.0',

        # By default, event callback just prints the changed state vars
        callback: ->(state_vars) {
          puts state_vars.inspect
        }
      }

      def initialize(options)
        super(options, DEFAULTS)
      end
    end

    def initialize(o = {}, &block)
      @options = Options.new(o, &block)
    end

    def listen
      if !@listen_thread
        @server = WEBrick::HTTPServer.new(
          Port: @options.listen_port,
          AccessLog: [],
          BindAddress: @options.bind_address
        )
        @server.mount('/', NotifyServlet, @options.callback)
      end

      @listen_thread ||= Thread.new do
        @server.start
      end

      url
    end

    def url
      if !@listen_thread or !@server
        raise RuntimeError, 'Server not started'
      end

      addr = Socket.ip_address_list.detect{|intf| intf.ipv4_private?}
      port = @server.config[:Port]

      "http://#{addr.ip_address}:#{port}"
    end

    def shutdown
      raise RuntimeError, "Illegal state: server is not started" if @listen_thread.nil?

      @listen_thread.kill
      @listen_thread = nil
    end
  end

  class NotifyServlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(_server, block)
      @callback = block
      @parser = EasyUpnp::EventParser.new
    end

    def do_NOTIFY(request, response)
      @callback.call(@parser.parse(request.body))
    end
  end
end
