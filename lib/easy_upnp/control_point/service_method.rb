module EasyUpnp
  class ServiceMethod
    attr_reader :name, :in_args, :out_args

    def initialize(name, in_args, out_args, arg_references)
      @name = name
      @in_args = in_args
      @out_args = out_args
      @arg_references = arg_references
    end

    def call_method(client, args_hash, validator_provider)
      raise ArgumentError, 'Service args must be a hash' unless args_hash.is_a?(Hash)

      present_args = args_hash.keys.map(&:to_sym)

      if (unsupported_args = (present_args - in_args)).any?
        raise ArgumentError, "Unsupported arguments: #{unsupported_args.join(', ')}." <<
                             " Supported args: #{in_args.join(', ')}"
      end

      args_hash.each do |arg, val|
        validator = validator_provider.validator(arg_reference(arg))
        begin
          validator.validate(val)
        rescue ArgumentError => e
          raise ArgumentError, "Invalid value for argument #{arg}: #{e}"
        end
      end

      raw_response = client.call(name, args_hash)
      parse_response(raw_response)
    end

    def parse_response(response)
      # Response is usually wrapped in <#{ActionName}Response></>. For example:
      # <BrowseResponse>...</BrowseResponse>. Extract the body since consumers
      # won't care about wrapper stuff.
      if response.body.keys.count > 1
        raise RuntimeError, "Unexpected keys in response body: #{response.body.keys}"
      end

      result = response.body.first[1]
      output = {}

      # Keys returned by savon are underscore style. Convert them to camelcase.
      out_args.map do |arg|
        output[arg] = result[underscore(arg.to_s).to_sym]
      end

      output
    end

    def arg_reference(arg)
      @arg_references[arg.to_sym]
    end

    def self.from_xml(xml)
      name = xml.xpath('name').text.to_sym
      args = xml.xpath('argumentList')

      arg_references = {}

      extract_args = ->(v) do
        arg_name = v.xpath('name').text.to_sym
        ref = v.xpath('relatedStateVariable').text.to_sym

        arg_references[arg_name] = ref
        arg_name
      end

      in_args = args.xpath('argument[direction = "in"]').map(&extract_args)
      out_args = args.xpath('argument[direction = "out"]').map(&extract_args)

      ServiceMethod.new(name, in_args, out_args, arg_references)
    end

    private

    # This is included in ActiveSupport, but don't want to pull that in for just this method...
    def underscore(s)
      s.gsub(/::/, '/').
          gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
          gsub(/([a-z\d])([A-Z])/, '\1_\2').
          tr("-", "_").
          downcase
    end

  end
end
