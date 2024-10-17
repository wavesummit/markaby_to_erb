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
      process_sexp(sexp)
      @buffer.join("\n").encode('UTF-8')
    end

    private

    INDENT = '  '

    def process_sexp(sexp)
      puts sexp.inspect
      return if sexp.nil? || (sexp.is_a?(Array) && sexp.empty?)

      type = sexp[0]
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
        add_content(sexp[1])
      when :@ident
        add_line("<%= #{sexp[1]} %>")
      else
        puts "Unhandled S-expression type: #{type}"
        puts "Full S-expression: #{sexp.inspect}"
      end
    end

    def process_method_add_block(sexp)
      method_call = sexp[1]
      block = sexp[2]

      method_name = extract_method_name(method_call)
      if html_tag?(method_name)
        # Start the tag
        add_line("<#{method_name}>")

        # Process the block content with indentation
        if block && block[0] == :do_block
          indent do
            process_sexp(block[2]) # Process block body
          end
        end

        # End the tag
        add_line("</#{method_name}>")
      else
        process_sexp(method_call)
        process_sexp(block) if block
      end
    end

    def process_method_add_arg(sexp)
      method_call = sexp[1]
      args = sexp[2]

      method_name = extract_method_name(method_call)
      if html_tag?(method_name)
        # Start the tag
        add_line("<#{method_name}>")

        # Add content for the arguments with indentation
        if args
          indent do
            process_sexp(args)
          end
        end

        # End the tag
        add_line("</#{method_name}>")
      else
        process_sexp(method_call)
        process_sexp(args) if args
      end
    end

    def process_command(sexp)
      method_name = sexp[1][1]
      args = sexp[2]

      if method_name == 'text'
        content = extract_string(args)
        add_content(content)
      elsif html_tag?(method_name)
        # Start the tag
        add_line("<#{method_name}>")

        # Process arguments (which could be inner content)
        if args
          indent do
            process_sexp(args)
          end
        end

        # End the tag
        add_line("</#{method_name}>")
      elsif helper_method?(method_name)
        erb_code = "<%= #{method_name}"
        if args && args[1]
          arguments = extract_arguments(args)
          erb_code += " #{arguments}"
        end
        erb_code += " %>"
        add_line(erb_code)
      else
        process_helper_method(method_name, args)
      end
    end

    def process_string_literal(sexp)
      content = sexp[1][1][1] rescue ''
      add_content(content)
    end

    def process_do_block(sexp)
      body = sexp[2]
      process_sexp(body) if body
    end

    def process_bodystmt(sexp)
      body = sexp[1]
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
      %w[html head title body h1 h2 h3 h4 h5 h6 ul li a div span p table tr td th form input label select option textarea button].include?(method_name)
    end

    def add_line(line)
      @buffer << (INDENT * @indent_level) + line
      puts "Adding line: #{line}" # For debugging purposes
    end

    def add_content(content)
      @buffer << (INDENT * (@indent_level + 1)) + content
      puts "Adding content: #{content}" # For debugging purposes
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

    def extract_arguments(args)
      args.inspect
    end
  end
end
