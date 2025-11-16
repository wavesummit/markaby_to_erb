module MarkabyToErb
  # Base exception class for all MarkabyToErb errors
  class Error < StandardError
  end

  # Raised when Markaby code cannot be parsed
  class ParseError < Error
    attr_reader :markaby_code, :parser_error

    def initialize(message = 'Failed to parse the Markaby code. Please check the syntax.', markaby_code: nil, parser_error: nil)
      super(message)
      @markaby_code = markaby_code
      @parser_error = parser_error
    end

    def to_s
      msg = super
      if @parser_error
        msg += "\nParser error: #{@parser_error.message}"
      end
      if @markaby_code && @markaby_code.length < 200
        msg += "\nMarkaby code:\n#{@markaby_code}"
      end
      msg
    end
  end

  # Raised when conversion encounters an unsupported or invalid construct
  class ConversionError < Error
    attr_reader :node_type, :node_location, :context, :line_number

    def initialize(message = nil, node_type: nil, node_location: nil, context: nil, line_number: nil)
      msg = message || "Unhandled node type: #{node_type}"
      super(msg)
      @node_type = node_type
      @node_location = node_location
      @context = context
      @line_number = line_number
    end

    def to_s
      msg = super
      if @node_type
        msg += " (node type: #{node_type})"
      end
      if @line_number
        msg += " at line #{@line_number}"
      elsif @node_location
        msg += " at #{@node_location}"
      end
      if @context
        msg += "\nContext: #{@context}"
      end
      msg
    end
  end

  # Raised when generated ERB output is invalid Ruby syntax
  class ValidationError < Error
    attr_reader :erb_code, :validation_error, :line_number

    def initialize(message = 'Generated ERB contains invalid Ruby syntax.', erb_code: nil, validation_error: nil, line_number: nil)
      super(message)
      @erb_code = erb_code
      @validation_error = validation_error
      @line_number = line_number
    end

    def to_s
      msg = super
      if @validation_error
        msg += "\nValidation error: #{@validation_error.message}"
      end
      if @line_number
        msg += "\nAt line: #{@line_number}"
      end
      if @erb_code && @erb_code.length < 500
        msg += "\nERB code:\n#{@erb_code}"
      end
      msg
    end
  end
end
