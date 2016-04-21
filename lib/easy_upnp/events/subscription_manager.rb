module EasyUpnp
  class Options < EasyUpnp::OptionsBase
    DEFAULTS = {
      ##
      # Number of seconds to request our event subscription be active for. The
      # server can set it to whatever it wants.
      requested_timeout: 300,

      ##
      # Number of seconds before a subscription expires before we request that
      # it be refreshed.
      resubscription_interval_buffer: 10,

      ##
      # Specifies an existing subscription ID. If non-nil, will attempt to
      # maintain the existing subscription, creating a new one if there's an
      # error. If nil, will always create a new subscription.
      existing_sid: nil,

      logger: Logger.new($stdout),
      log_level: Logger::WARN,

      on_shutdown: -> { }
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
      @sid = @options.existing_sid

      logger.level = @options.log_level
    end

    def subscription_id
      @sid
    end

    def callback_url
      if @callback_url.is_a? Proc
        @callback_url.call
      else
        @callback_url
      end
    end

    def subscribe
      @subscription_thread ||= Thread.new do
        logger.info "Starting subscription thread..."

        resubscribe_time = start_or_renew_subscription

        begin
          while true
            if Time.now >= resubscribe_time
              resubscribe_time = renew_subscription
            else
              sleep 1
            end
          end
        rescue Exception => e
          logger.error "Caught error: #{e}"
          raise e
        end

        logger.info "Ending subscription"
      end

      true
    end

    def unsubscribe
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

      @options.on_shutdown.call
    end

    private

    def start_or_renew_subscription
      if !@sid
        start_subscription
      else
        renew_subscription
      end
    end

    def renew_subscription
      begin
        logger.info "Refreshing subscription for: #{@sid}"
        response = @event_client.resubscribe(
          @sid,
          timeout: @options.requested_timeout
        )
        logger.info "Got resubscribe response: #{response.inspect}"
        @resubscribe_time = calculate_refresh_time(response)
      rescue EasyUpnp::EventClient::SubscriptionError => e
        logger.error "Error renewing subscription; trying to start a new one"
        start_subscription
      rescue Exception => e
        logger.error "Unrecoverable exception renewing subscription: #{e}"
        raise e
      end
    end

    def start_subscription
      begin
        response = @event_client.subscribe(
          callback_url,
          timeout: @options.requested_timeout
        )

        logger.info "Got subscription response: #{response.inspect}"

        @sid = response.sid
        @resubscribe_time = calculate_refresh_time(response)
      rescue Exception => e
        logger.error "Error subscribing to event: #{e}"
        raise e
      end
    end

    def calculate_refresh_time(response)
      timeout = response.timeout
      Time.now + timeout - @options.resubscription_interval_buffer
    end

    def logger
      @options.logger
    end
  end
end
