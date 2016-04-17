module EasyUpnp
  class OptionsBase
    class Builder
      attr_reader :options

      def initialize(supported_options)
        @options = {}

        supported_options.each do |k|
          define_singleton_method("#{k}=") { |v| @options[k] = v }
          define_singleton_method("#{k}") do |&block|
            @options[k] = block if block
            @options[k]
          end
        end
      end
    end

    attr_reader :options

    def initialize(options, defaults, &block)
      @options = defaults.merge(options)

      if block
        block_builder = Builder.new(defaults.keys)
        block.call(block_builder)
        @options = @options.merge(block_builder.options)
      end

      defaults.map do |k, v|
        define_singleton_method(k) do
          @options[k]
        end
      end
    end
  end
end
