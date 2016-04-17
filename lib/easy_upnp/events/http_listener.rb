require 'webrick'

require_relative '../options_base'

module EasyUpnp
  class HttpListener
    class Options < EasyUpnp::OptionsBase
      DEFAULTS = {
        # Port to listen on. Default value "0" will cause OS to choose a random
        # ephemeral port
        listen_port: 0,

        # By default, event callback just prints the request body
        callback: ->(request) { puts request.body }
      }

      def initialize(options)
        super(options, DEFAULTS)
      end
    end

    def initialize(o = {}, &block)
      @options = Options.new(o, &block)

      @server = WEBrick::HTTPServer.new(
        Port: @options.listen_port,
        AccessLog: []
      )
      @server.mount('/', NotifyServlet, @options.callback)
    end

    def listen
      @listen_thread ||= Thread.new do
        @server.start
      end
      true
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
    end

    def do_NOTIFY(request, response)
      @callback.call(request)
    end
  end
end
