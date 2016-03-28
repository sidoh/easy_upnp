module EasyUpnp
  module Log
    class <<self
      attr_accessor :enabled, :level
    end

    def self.enabled?
      @enabled.nil? ? @enabled = true : @enabled
    end

    def self.level
      @level ||= :info
    end
  end
end
