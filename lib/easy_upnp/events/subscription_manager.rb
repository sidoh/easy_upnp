require_relative '../options_base'

module EasyUpnp
  class Options < EasyUpnp::OptionsBase
    DEFAULTS = {
      # Number of seconds to request our event subscription be active for. The
      # server can set it to whatever it wants.
      requested_timeout: 300,

      # Number of seconds before a subscription expires before we request that
      # it be refreshed.
      resubscription_interval_buffer: 10,

      logger: Logger.new($stdout),
      log_level: Logger::WARN
    }

    def initialize(o, &block)
      super(o, DEFAULTS, &block)
    end
  end

  class SubscriptionManager
    def initialize(event_client, callback_url, options = {}, &block)
      @options = Options.new(options, &block)
      @event_client = event_client
      @callback_url = callback_url

      logger.level = @options.log_level
    end

    def start_subscription
      @subscription_thread ||= Thread.new do
        logger.info "Starting subscription thread..."

        begin
          response = @event_client.subscribe(
            @callback_url,
            timeout: @options.requested_timeout
          )
        rescue Exception => e
          logger.error "Error subscribing to event: #{e}"
          raise e
        end

        resubscribe_time = calculate_refresh_time(response)
        @sid = response.sid

        logger.info "Got subscription response: #{response}"

        while true
          if Time.now >= resubscribe_time
            logger.info "Refreshing subscription for: #{sid}"
            response = @event_client.resubscribe(
              @sid,
              timeout: @options.requested_timeout
            )
            logger.info "Got resubscribe response: #{response}"
            resubscribe_time = calculate_refresh_time(response)
          else
            sleep 1
          end
        end

        logger.info "Ending subscription"
      end
      
      true
    end

    def end_subscription
      if @subscription_thread.nil?
        raise RuntimeError, "Illegal state: no active subscription"
      end
      @subscription_thread.kill
      @subscription_thread = nil

      begin
        if @sid
          @event_client.unsubscribe(@sid)
          @sid = nil
        end
      rescue Exception => e
        logger.error "Error unsubscribing with SID #{@sid}: #{e}"
      end
    end

    def calculate_refresh_time(response)
      timeout = response.timeout
      Time.now + timeout - @options.resubscription_interval_buffer
    end

    private

    def logger
      @options.logger
    end
  end
end
