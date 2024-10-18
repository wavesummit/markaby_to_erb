require 'ripper'

module MarkabyToErb
  class Converter
    def initialize(markaby_code)
      @markaby_code = markaby_code.encode('UTF-8')
      @buffer = []
      @indent_level = 0
    end

    def convert
      sexp = Ripper.sexp(@markaby_code)
      if sexp.nil?
        puts "Failed to parse the Markaby code. Please check the syntax."
        exit
      end

      #pp sexp
      process_sexp(sexp)
      @buffer.join("\n").encode('UTF-8')
    end

    private

    INDENT = '  '

    def process_sexp(sexp)

      return if sexp.nil? || (sexp.is_a?(Array) && sexp.empty?)

      type = sexp[0]

      #puts type
      case type
      when :program
        sexp[1].each { |sub_sexp| process_sexp(sub_sexp) }
      when :assign
        process_assign(sexp)
      when :method_add_block
        process_method_add_block(sexp)
      when :method_add_arg
        process_method_add_arg(sexp)
      when :command
        process_command(sexp)
      when :fcall
        process_fcall(sexp)
      when :vcall
        process_vcall(sexp)
      when :string_literal
        process_string_literal(sexp)
      when :do_block
        process_do_block(sexp)
      when :bodystmt
        process_bodystmt(sexp)
      when :args_add_block
        process_args_add_block(sexp)
      when :@tstring_content
        add_content(sexp)
      when :@ident
        add_line("<%= #{sexp[1]} %>",:process_sexp)
      else
        puts "Unhandled S-expression type: #{type}"
        puts "Full S-expression: #{sexp.inspect}"
      end
    end

    def process_assign(sexp)
      # [:assign, [:var_field, [:@ident, "greeting", [1, 0]]], [:string_literal, [:string_content, [:@tstring_content, "Welcome to the Site!", [1, 12]]]]]
      variable_name = extract_variable_name(sexp[1])
      value = extract_content(sexp[2])
      value = "\"#{value}\"" if sexp[2][0] == :string_literal || sexp[2][0] == :@tstring_content
      # Adding assignment to ERB
      erb_assignment = "<% #{variable_name} = #{value} %>"
      add_line(erb_assignment, :process_assign)
    end

    def extract_variable_name(var_sexp)
      # Extract the variable name from `:var_field`
      if var_sexp && var_sexp[0] == :var_field && var_sexp[1][0] == :@ident
        var_sexp[1][1]
      else
        "unknown_variable"
      end
    end

    def process_method_add_block(sexp)
      method_call = sexp[1] # Represents the method call part (e.g., `[:method_add_arg, ...]`)
      block = sexp[2]       # Represents the block part (e.g., `[:do_block, ...]`)

      # Extract the method name (e.g., "h4")
      # method_call[1] is important without the method name was nil
      method_name = extract_method_name(method_call[1])
      method_name = extract_method_name(method_call) if method_name.nil?

      if html_tag?(method_name)
        # Step 1: Add the opening tag
        attributes = extract_attributes(method_call[2])

        # Step 2: Process the block content
        if block && block[0] == :do_block
          add_line("<#{method_name}#{attributes}>",:process_method_add_block)

          indent do
            process_bodystmt(block[2]) # Extract and process the block body (`:bodystmt`)
          end

          # Step 3: Add the closing tag after processing the block content
          add_line("</#{method_name}>",:process_method_add_block)

        else
          # If there is no block, make it a self-closing tag
          add_line("<#{method_name}#{attributes} />")
        end

        # Step 3: Add the closing tag after processing the block content

      else
        # Handle other method calls with blocks that aren't HTML tags
        process_sexp(method_call)
        process_sexp(block) if block
      end
    end

    def process_method_add_arg(sexp)
      method_call = sexp[1]
      args = sexp[2]

      method_name = extract_method_name(method_call)
      if html_tag?(method_name)

        if args.nil? || args.empty?
          add_line("<#{method_name}#{attributes} />",:process_method_add_arg)
        else
          # Start the tag
          add_line("<#{method_name}#{attributes}>",:process_method_add_arg)

          # Add content for the arguments
          indent do
            process_sexp(args)
          end

          # End the tag
          add_line("</#{method_name}>",:process_method_add_arg)
        end
      else
        process_sexp(method_call)
        process_sexp(args) if args
      end
    end

    def process_command(sexp)
      method_name = sexp[1][1] # Extract method name (e.g., "li", "text", or "h2")
      args = sexp[2]           # Extract arguments (e.g., [:args_add_block, ...])

      if method_name == 'text'
        # Handle `text` method specifically
        content = extract_content(args)
        add_line(content, :process_command)

      elsif helper_method?(method_name)
        erb_code = "<%= #{method_name}"
        if args && args[1]
          arguments = extract_arguments(args)
          erb_code += " #{arguments}"
        end
        erb_code += " %>"
        add_line(erb_code, :process_command)

      elsif html_tag?(method_name)
        # Extract attributes if present
        attributes = extract_attributes(args)

        # Determine if the argument is a variable or string
        if args && args[1].is_a?(Array)
          first_arg = args[1][0]

          # Check if it's a variable (e.g., @ident)
          if first_arg.is_a?(Array) && first_arg[1].is_a?(Array) && first_arg[1][0] == :@ident
            variable_name = first_arg[1][1]
            erb_content = "<%= #{variable_name} %>"
            add_line("<#{method_name}#{attributes}>#{erb_content}</#{method_name}>", :process_command)

          # If it's a string literal, extract and add content
          elsif first_arg.is_a?(Array) && first_arg[0] == :string_literal
            content = extract_content(args)
            add_line("<#{method_name}#{attributes}>#{content}</#{method_name}>", :process_command)

          else
            # If there's no content or unknown format, create a self-closing tag
            add_line("<#{method_name}#{attributes} />", :process_command)
          end
        else
          # If there's no argument (args is nil or empty), create a self-closing tag
          add_line("<#{method_name}#{attributes} />", :process_command)
        end

      else
        # Handle other commands or helper methods
        process_helper_method(method_name, args)
      end
    end

    def process_vcall(sexp)

      method_name = sexp[1][1] # Extract method name from `vcall`

      if helper_method?(method_name)
        # Handle it as a Rails helper method, e.g., <%= label %>
        add_line("<%= #{method_name} %>", :process_vcall)
      elsif html_tag?(method_name)
        # If it's an HTML tag, generate an empty tag
        add_line("<#{method_name}></#{method_name}>", :process_vcall)
      else
        # If it's just a plain method call, treat it as a variable or an unknown method
        add_line("<%= #{method_name} %>", :process_vcall)
      end
    end

    def process_string_literal(sexp)
      content = sexp[1][1][1] rescue ''
      add_content(content, :process_string_literal)
    end

    def process_do_block(sexp)
      body = sexp[2]
      process_sexp(body) if body
    end

    def process_bodystmt(sexp)
      body = sexp[1] # `sexp[1]` contains the statements inside the block
      body.each { |sub_sexp| process_sexp(sub_sexp) } if body
    end

    def process_args_add_block(sexp)
      args = sexp[1]
      args.each { |arg| process_sexp(arg) }
    end

    def extract_method_name(sexp)
      case sexp[0]
      when :call
        sexp[2][1]
      when :vcall
        sexp[1][1]
      when :command
        sexp[1][1]
      when :fcall
        sexp[1][1]
      else
        nil
      end
    end

    def extract_string(args_sexp)
      return '' unless args_sexp && args_sexp[1]

      first_arg = args_sexp[1][0]
      if first_arg.is_a?(Array)
        case first_arg[0]
        when :string_literal
          first_arg[1][1][1]
        when :@tstring_content
          first_arg[1]
        else
          ''
        end
      else
        ''
      end
    end

    def helper_method?(method_name)
      %w[link_to link_to_remote image_tag form_for form_with label].include?(method_name)
    end

    def html_tag?(method_name)
      %w[html head title body h1 h2 h3 h4 h5 h6 p div span a ul ol li table tr td th form input
  button select option textarea img link script meta style header footer section article nav
  aside main figure figcaption video audio canvas iframe br hr b i u strong em small sub sup
  code pre blockquote q cite dl dt dd abbr address
  ].include?(method_name)
    end

    def add_line(line, parent)
      @buffer << (INDENT * @indent_level) + line
      #puts "Adding line: #{line} from #{parent}" # For debugging purposes
    end

    def add_content(content, parent)
      @buffer << (INDENT * (@indent_level)) + content
      #puts "Adding content: #{content} from #{parent}" # For debugging purposes
    end

    def indent
      @indent_level += 1
      yield
      @indent_level -= 1
    end

    def process_helper_method(method_name, args)
      puts "Processing helper method: #{method_name}"
      process_sexp(args) if args
    end

    def extract_attributes(args)
      return '' unless args && args[1]

      # Check if the arguments contain a `:bare_assoc_hash`
      bare_assoc_hash = args[1].find { |arg| arg[0] == :bare_assoc_hash }
      return '' unless bare_assoc_hash

      # Extract key-value pairs from the `:bare_assoc_hash`
      attribute_pairs = bare_assoc_hash[1]
      attributes = attribute_pairs.map do |pair|
        key = pair[1][1].to_s.chomp(':') # Extract key name (remove the colon)
        value = unparse_sexp(pair[2])     # Extract value using `unparse_sexp`
        "#{key}=\"#{value}\""
      end

      attributes.empty? ? '' : " " + attributes.join(' ')
    end

    def extract_arguments(args_sexp)
      return '' unless args_sexp && args_sexp[1]

      # Handle the different structures in the arguments
      args_list = if args_sexp[1].is_a?(Array)
                    args_sexp[1].map { |arg| extract_argument_value(arg) }
                  else
                    [extract_argument_value(args_sexp[1])]
                  end

      args_list.join(', ')
    end

    def extract_argument_value(arg)
      case arg[0]
      when :string_literal
        # Extract string content from `:string_literal`
        if arg[1].is_a?(Array) && arg[1][1].is_a?(Array)
          "\"#{arg[1][1][1]}\""
        else
          "\"#{arg[1][1]}\""
        end
      when :symbol_literal
        # Extract symbol value
        ":#{arg[1][1]}"
      when :@tstring_content
        # Extract directly from `:@tstring_content`
        "\"#{arg[1]}\""
      else
        # If none of the above matches, fallback to inspect
        arg.inspect
      end
    end

    def extract_content(args)
      return '' unless args && args[1]

      # Extract the arguments array (args[1] should contain the list of arguments)
      args_list = args[1]

      # Ensure args_list is an array
      return '' unless args_list.is_a?(Array)

      # Iterate through each argument and extract content where possible
      args_list.map do |arg|
        case arg[0]
        when :string_literal
          # Extract content from `:string_literal`
          string_content = arg[1]
          if string_content.is_a?(Array) && string_content[0] == :string_content
            tstring = string_content[1]
            if tstring.is_a?(Array) && tstring[0] == :@tstring_content
              tstring[1] # Extract the actual string content
            else
              ''
            end
          else
            ''
          end
        when :@tstring_content
          # Directly extract the string value from `:@tstring_content`
          arg[1]
        else
          # Fallback in case the type is not recognized
          ''
        end
      end.join() # Join multiple arguments if there are any
    end

    def unparse_sexp(sexp)
      return '' unless sexp.is_a?(Array)

      type = sexp[0]
      case type
      when :string_literal
        sexp[1][1][1]
      when :@tstring_content
        sexp[1]
      else
        # Handle other types or return an empty string
        ''
      end
    end
  end
end
