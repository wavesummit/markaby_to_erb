require 'parser/current'
require 'logger'

require_relative 'extractors/extractors'
require_relative 'processors/processors'
require_relative 'helpers/helpers'

module MarkabyToErb
  class Converter

    include MarkabyToErb::Extractors
    include MarkabyToErb::Processors
    include MarkabyToErb::Helpers

    def initialize(markaby_code, options = {})
      @markaby_code = markaby_code.encode('UTF-8')
      @buffer = []
      @indent_level = 0
      @line_numbers = {} # Track line numbers for error reporting
      @current_line = 1
      @validate_output = options.fetch(:validate_output, true)
      @verbose = options.fetch(:verbose, false)
      @logger = options.fetch(:logger, nil)
      @logger ||= Logger.new($stdout) if @verbose
    end

    def convert
      begin
        parser = Parser::CurrentRuby.parse(@markaby_code)
      rescue Parser::SyntaxError => e
        raise ParseError.new('Failed to parse the Markaby code. Please check the syntax.', 
                            markaby_code: @markaby_code, 
                            parser_error: e)
      end

      pp parser if test?
      
      # Handle empty files or files with only comments
      if parser.nil?
        log_info("File appears to be empty or contains only comments (#{@markaby_code.lines.count} lines)")
        
        # Check if file is completely empty
        if @markaby_code.strip.empty?
          return ""
        end
        
        # File contains only comments - preserve them as ERB comments
        comment_lines = @markaby_code.lines.map do |line|
          stripped = line.strip
          if stripped.empty?
            ""
          elsif stripped.start_with?('#')
            # Convert Ruby comment to ERB comment
            "<%# #{stripped[1..-1].strip} %>"
          else
            # Preserve whitespace-only lines
            line.chomp
          end
        end
        
        erb_code = comment_lines.join("\n").encode('UTF-8')
        log_info("Conversion complete. Generated #{erb_code.lines.count} lines of ERB (comments only)")
        return erb_code
      end

      begin
        log_info("Starting conversion of Markaby code (#{@markaby_code.lines.count} lines)")
        process_node(parser)
        erb_code = @buffer.join("\n").encode('UTF-8')
        log_info("Conversion complete. Generated #{erb_code.lines.count} lines of ERB")
        
        # Validate output if enabled
        if @validate_output
          validate_output(erb_code)
        end
        
        erb_code
      rescue ConversionError => e
        # Add line number if available
        if e.line_number.nil? && @current_line > 1
          e = ConversionError.new(e.message, 
                                  node_type: e.node_type,
                                  node_location: e.node_location,
                                  context: e.context,
                                  line_number: @current_line)
        end
        raise e
      rescue => e
        # Wrap unexpected errors in ConversionError
        raise ConversionError.new("Unexpected error during conversion: #{e.message}", 
                                 context: e.class.name,
                                 line_number: @current_line)
      end
    end

    private

    INDENT = '  '.freeze

    def append_classes(attributes, classes)
      return attributes if classes.empty?

      if attributes.include?('class="')
        attributes.sub('class="', "class=\"#{classes.join(' ')} ")
      else
        "#{attributes} class=\"#{classes.join(' ')}\""
      end
    end

    def append_ids(attributes, ids)
      return attributes if ids.empty?

      if attributes.include?('id="')
        attributes.sub('id="', "id=\"#{ids.join(' ')} ")
      else
        "#{attributes} id=\"#{ids.join(' ')}\""
      end
    end


    def add_line(line, from_method)
      output_line = (INDENT * @indent_level) + line
      @buffer << output_line
      @line_numbers[@buffer.length] = @current_line
      log_debug("Line #{@buffer.length}: #{output_line} (from #{from_method})")
      puts "Adding line: #{line} from #{from_method}" if test?
    end

    def test?
      ENV['DEBUG'].to_i == 1
    end

    def indent
      @indent_level += 1
      yield
      @indent_level -= 1
    end

    def verbose?
      @verbose
    end

    def log_info(message)
      @logger&.info(message)
    end

    def log_debug(message)
      @logger&.debug(message)
    end

    def log_warn(message)
      @logger&.warn(message)
    end

    def log_error(message)
      @logger&.error(message)
    end

    # Validate that the generated ERB contains valid Ruby syntax
    def validate_output(erb_code)
      log_info("Validating generated ERB output...")
      
      # Validate each ERB tag's Ruby code separately
      erb_code.lines.each_with_index do |line, line_num|
        # Find all ERB tags, but skip those inside HTML attribute strings
        # We'll extract ERB tags that are not inside quotes
        erb_pattern = /<%(=)?\s*((?:[^%"]|%[^>])*?)\s*%>/
        
        # First, identify ERB tags that are inside HTML attribute strings
        # by looking for patterns like: attr="<%= ... %>"
        in_attribute = false
        line_chars = line.chars
        i = 0
        erb_positions = []
        
        while i < line_chars.length
          if line_chars[i..i+1] == ['<', '%']
            # Found start of ERB tag
            start_pos = i
            # Check if we're inside an attribute string
            # Look backwards for ="
            j = start_pos - 1
            while j >= 0 && line_chars[j] =~ /\s/
              j -= 1
            end
            if j >= 0 && line_chars[j] == '"' && j > 0 && line_chars[j-1] == '='
              # This ERB tag is inside an attribute, skip it
              # Find the end of this ERB tag
              i += 2
              while i < line_chars.length && !(line_chars[i-1] == '%' && line_chars[i] == '>')
                i += 1
              end
              i += 1
              next
            end
            
            # Not in attribute, find the end
            i += 2
            while i < line_chars.length && !(line_chars[i-1] == '%' && line_chars[i] == '>')
              i += 1
            end
            end_pos = i + 1
            erb_positions << [start_pos, end_pos]
          else
            i += 1
          end
        end
        
        # Now validate ERB tags that are not in attributes
        line.scan(erb_pattern) do |output_tag, code|
          next if code.strip.empty?
          
          # Check if this ERB tag is inside an attribute by checking the match position
          match_start = $~.begin(0)
          # Simple heuristic: if the ERB tag is after a =", it's in an attribute
          before_match = line[0...match_start]
          if before_match =~ /="[^"]*$/
            # Likely inside an attribute string, skip
            next
          end
          
          begin
            # Try to parse each ERB tag's Ruby code
            test_code = code.strip
            
            # Skip validation for incomplete control flow statements and end statements
            # These are valid in ERB context but not as standalone Ruby
            if test_code == 'end' || 
               test_code == 'else' || 
               test_code == 'elsif' || 
               test_code == 'when' || 
               test_code == 'rescue' || 
               test_code == 'ensure' ||
               test_code.start_with?('end,') ||
               test_code.start_with?('end ')
              # These are part of multi-line control structures, skip validation
              next
            end
            
            # Skip validation for incomplete block statements (e.g., "v.each_pair do |setting,value|" or "link_to capture do")
            if test_code =~ /\sdo\s*(\|.*\|)?\s*$/
              # This is an incomplete block, skip validation
              next
            end
            
            if test_code =~ /^(if|unless|while|until|for|begin|case|class|module|def|elsif|else|when|rescue|ensure)\s/ && 
               !test_code.end_with?('end') && 
               !test_code.include?('then') &&
               !test_code.include?('do')
              # This is likely an incomplete control flow statement, skip validation
              next
            end
            
            # Try parsing as a statement first
            begin
              Parser::CurrentRuby.parse(test_code)
            rescue Parser::SyntaxError => stmt_error
              # If that fails, check if it's an incomplete control flow statement
              if stmt_error.message.include?('$end') && 
                 test_code =~ /^(if|unless|while|until|for|begin|case|class|module|def)\s/
                # This is an incomplete control flow statement, skip validation
                next
              end
              
              # If that fails, try as an expression (but skip for control flow)
              unless test_code =~ /^(if|unless|while|until|for|begin|case|class|module|def)\s/
                begin
                  Parser::CurrentRuby.parse("_ = #{test_code}")
                rescue Parser::SyntaxError => expr_error
                  # If expression parsing also fails, it might be incomplete
                  # Only raise if it's clearly invalid syntax
                  if expr_error.message =~ /unexpected token|syntax error/i && 
                     !expr_error.message.include?('$end')
                    log_error("Output validation failed at line #{line_num + 1}: #{expr_error.message}")
                    log_error("Code: #{code}")
                    raise ValidationError.new('Generated ERB contains invalid Ruby syntax.',
                                             erb_code: erb_code,
                                             validation_error: expr_error,
                                             line_number: line_num + 1)
                  end
                end
              end
            end
          rescue ValidationError
            raise
          rescue Parser::SyntaxError => e
            # Only raise for clearly invalid syntax (not incomplete statements)
            if e.message =~ /unexpected token|syntax error/i && 
               !e.message.include?('$end') &&
               !code.strip.match(/^(if|unless|while|until|for|begin|case|class|module|def|elsif|else|when|rescue|ensure)\s/)
              log_error("Output validation failed at line #{line_num + 1}: #{e.message}")
              log_error("Code: #{code}")
              raise ValidationError.new('Generated ERB contains invalid Ruby syntax.',
                                       erb_code: erb_code,
                                       validation_error: e,
                                       line_number: line_num + 1)
            end
          end
        end
      end
      
      log_info("Output validation passed")
    end

    # Try to find the approximate line number in ERB where the error occurred
    def find_error_line_in_erb(erb_code, parser_error)
      # Parser errors sometimes include line information
      if parser_error.respond_to?(:diagnostic) && parser_error.diagnostic
        location = parser_error.diagnostic.location
        if location.respond_to?(:line)
          return location.line
        end
      end
      
      # Fallback: try to match error message for line numbers
      if parser_error.message =~ /line (\d+)/
        return $1.to_i
      end
      
      nil
    end
  end
end
