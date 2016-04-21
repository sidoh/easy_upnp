require 'easy_upnp/control_point/argument_validator'

module EasyUpnp
  module ValidatorProvider
    def self.no_op_provider
      NoOpValidatorProvider.new
    end

    def self.from_xml(xml)
      validators = {}

      xml.xpath('//serviceStateTable/stateVariable').each do |var|
        name = var.xpath('name').text.to_sym
        validators[name] = EasyUpnp::ArgumentValidator.from_xml(var)
      end

      DefaultValidatorProvider.new(validators)
    end

    private
      class DefaultValidatorProvider
        def initialize(validators)
          @validators = validators
        end

        def validator(arg_ref)
          validator = @validators[arg_ref.to_sym]
          raise ArgumentError, "Unknown argument reference: #{arg_ref}" if arg_ref.nil?
          validator
        end
      end

      class NoOpValidatorProvider
        def validator(arg_ref)
          ArgumentValidator.no_op
        end
      end
  end
end
