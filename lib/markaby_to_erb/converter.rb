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

    def process_method_add_block(sexp)
      method_call = sexp[1] # Represents the method call part (e.g., `[:method_add_arg, ...]`)
      block = sexp[2]       # Represents the block part (e.g., `[:do_block, ...]`)


      # Extract the method name (e.g., "h4")
      # method_call[1] is important without the method name was nil
      method_name = extract_method_name(method_call[1])

      if html_tag?(method_name)
        # Step 1: Add the opening tag


        # Step 2: Process the block content
        if block && block[0] == :do_block
          add_line("<#{method_name}>",:process_method_add_block)

          indent do
            process_bodystmt(block[2]) # Extract and process the block body (`:bodystmt`)
          end

          # Step 3: Add the closing tag after processing the block content
          add_line("</#{method_name}>",:process_method_add_block)

        else
          # If there is no block, make it a self-closing tag
          add_line("<#{method_name} />")
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

      #pp sexp

      method_name = extract_method_name(method_call)
      if html_tag?(method_name)

        if args.nil? || args.empty?
          add_line("<#{method_name} />",:process_method_add_arg)
        else
          # Start the tag
          add_line("<#{method_name}>",:process_method_add_arg)

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
      method_name = sexp[1][1] # Extract the command name (e.g., "text")
      args = sexp[2]           # Extract the arguments

      if method_name == 'text'
        # Extract and add the string content passed to `text`
        content = extract_string(args)
        add_content(content, :process_command)
      elsif html_tag?(method_name)
        attributes = extract_attributes(args)
        if args.nil? || args[1].empty? || (args[1][0][0] == :bare_assoc_hash && args[1][1].nil? )
          add_line("<#{method_name}#{attributes} />",:process_command)
        else
        # Otherwise, create an opening tag
          add_line("<#{method_name}#{attributes}>",:process_command)

          # Process the arguments, which could be content inside the tag
          if args && args[1]
            indent do
              process_sexp(args)
            end
          end
          # Add closing tag
          add_line("</#{method_name}>",:process_command)
        end
      elsif helper_method?(method_name)
        erb_code = "<%= #{method_name}"
        if args && args[1]
          arguments = extract_arguments(args)
          erb_code += " #{arguments}"
        end
        erb_code += " %>"
        add_content(erb_code, :process_command)
      else
        process_helper_method(method_name, args)
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
      %w[link_to link_to_remote image_tag].include?(method_name)
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

    def extract_arguments(args)
      args.inspect
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
