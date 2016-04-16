module EasyUpnp
  module Log
    class <<self
      attr_accessor :enabled, :level
    end

    def self.enabled?
      @enabled = true if @enabled.nil?
    end

    def self.level
      @level ||= :info
    end
  end
end
