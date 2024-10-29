require 'parser/current'

module MarkabyToErb
  class Converter
    def initialize(markaby_code)
      @markaby_code = markaby_code.encode('UTF-8')
      @buffer = []
      @indent_level = 0
    end

    def convert
      parser = Parser::CurrentRuby.parse(@markaby_code)
      pp parser if test?
      if parser.nil?
        puts 'Failed to parse the Markaby code. Please check the syntax.'
        exit
      end

      process_node(parser)
      @buffer.join("\n").encode('UTF-8')
    end

    private

    INDENT = '  '.freeze

    def process_node(node)
      return if node.nil?

      case node.type
      when :send
        process_send(node)
      when :lvasgn, :ivasgn
        process_assignment(node)
      when :block
        process_block(node)
      when :if
        process_if(node)
      when :begin
        process_begin(node)
      when :op_asgn
        process_op_asgn(node)
      when :str
        process_str(node)
      when :dstr
        process_dstr(node)
      when :yield
        process_yield(node)
      when :case
        process_case(node)
      when :next
        process_next(node)
      else
        puts "Unhandled node type: #{node.type}"
      end
    end

    def process_yield(node)
      add_line("<%= yield %>", :process_yield)
    end

    def process_begin(node)
      node.children.each do |child|
        process_node(child)
      end
    end

    def process_op_asgn(node)
      variable = extract_content(node.children[0])
      operator = node.children[1]
      value = extract_content(node.children[2])

      # Format the value with parentheses if it's a complex expression
      formatted_value = node.children[2].type == :begin ? "( #{value} )" : value
      formatted_value = "\"#{value}\"" if node.children[2].type == :str

      # Remove any extra spaces at beginning of lines and fix string concatenation
      formatted_value = formatted_value.strip

      add_line("<% #{variable} #{operator}= #{formatted_value} %>", :process_op_asgn)
    end

    def process_next(node)
      condition = node.children[0]
      if condition
        condition_str = extract_content(condition)
        add_line("<% next if #{condition_str} %>", :process_next)
      else
        add_line("<% next %>", :process_next)
      end
    end

    def process_str(node)
      value = node.children[0]
      add_line(value, :process_str)
    end

    def process_dstr(node)
      value = extract_dstr(node)
      add_line("<%= #{value} %>", :process_str)
    end

    def process_if(node)
      condition_node, if_body, else_body = node.children

      # Check if else_body is an :if node (indicating an elsif)
      if else_body&.type == :if
        # Handle if-elsif chain
        add_line("<% if #{extract_content(condition_node)} %>", :process_if)
        indent do
          process_node(if_body) if if_body
        end

        # Process all elsif conditions
        current_node = else_body
        while current_node&.type == :if
          condition, body, next_else = current_node.children
          add_line("<% elsif #{extract_content(condition)} %>", :process_if)
          indent do
            process_node(body) if body
          end
          current_node = next_else
        end

        # Handle final else if it exists
        if current_node
          add_line('<% else %>', :process_if)
          indent do
            process_node(current_node)
          end
        end
      elsif if_body.nil? && else_body
        # Convert to unless when we have nil if_body and non-nil else_body
        add_line("<% unless #{extract_content(condition_node)} %>", :process_if)
        indent do
          process_node(else_body)
        end
      else
        # Handle regular if-else statements
        add_line("<% if #{extract_content(condition_node)} %>", :process_if)
        indent do
          process_node(if_body) if if_body
        end
        if else_body
          add_line('<% else %>', :process_if)
          indent do
            process_node(else_body)
          end
        end
      end
      add_line('<% end %>', :process_if)
    end

    def process_assignment(node)
      case node.type
      when :lvasgn, :ivasgn
        var_name, value_node = node.children

        # Delegate to process_op_asgn if the value is an operator assignment
        if value_node.type == :op_asgn
          process_op_asgn(value_node)
        else
          value = extract_content(value_node)

          # Ensure strings are properly quoted
          value = "\"#{value}\"" if value_node.type == :str

          erb_assignment = "<% #{var_name} = #{value} %>"
          add_line(erb_assignment, :process_assignment)
        end

      else
        # Handle other types of nodes as needed
        add_line("Unknown assignment type: #{node.type}", :process_assignment)
      end
    end

    def process_method(node)
      receiver, method_name, *args = node.children
      arguments = args.map do |arg|
        [:str, :dstr].include?(arg.type) ? "\"#{extract_content(arg)}\"" : extract_content(arg)
      end.join(', ')

      result = [method_name, arguments].reject { |a| a.empty? }.join(' ')
      erb_code = "<%= #{result} %>"
      add_line(erb_code, :process_method)
    end

    def process_case(node)
      # The first child is the case expression
      case_expression_node = node.children[0]
      # The remaining children are the when clauses and possibly an else clause
      clauses = node.children[1..-1]

      # Extract the case expression content
      case_expression = extract_content(case_expression_node)

      # Start the case statement in ERB
      add_line("<% case #{case_expression} %>", :process_case)

      # Increase indentation for the when and else clauses
      indent do
        clauses.each do |clause|
          if clause&.type == :when
            # Handle 'when' clauses
            # Each 'when' clause can have multiple conditions
            conditions = clause.children[0..-2] # All but the last child
            body = clause.children[-1] # The last child is the body

            # Extract conditions as a comma-separated string
            condition_str = conditions.map { |cond| extract_content(cond) }.join(', ')

            # Add the 'when' line in ERB
            add_line("<% when #{condition_str} %>", :process_case)

            # Process the body of the 'when' clause
            indent do
              process_node(body)
            end

          else
            # Handle 'else' clause
            # Any clause that's not a 'when' is treated as 'else'
            body = clause

            # Add the 'else' line in ERB
            add_line("<% else %>", :process_case)

            # Process the body of the 'else' clause
            indent do
              process_node(body)
            end
          end
        end
      end

      # End the case statement in ERB
      add_line("<% end %>", :process_case)
    end

    def process_send(node)
      receiver, method_name, *args = node.children
      html_tag, classes, ids = extract_html_tag_and_attributes(node)

      if helper_call?(method_name)
        process_method(node)

      elsif method_name == :content_for
        process_content_for(node, args)

      elsif html_tag

        attributes = extract_attributes(args)
        attributes = append_classes(attributes, classes)
        attributes = append_ids(attributes, ids)

        content = args.reject { |arg| arg.type == :hash }.map do |arg|
          case arg.type
          when :lvar, :send
            "<%= #{extract_content(arg)} %>"
          else
            extract_content(arg)
          end
        end.join

        if content.empty?
          # self closing tags are like br, input
          if self_closing_tag?(html_tag)
            add_line("<#{html_tag}#{attributes}>", :process_send1)
          else
            add_line("<#{html_tag}#{attributes}/>", :process_send)
          end
        else
          # Add the opening tag and content in the same line if there's no nested block.
          add_line("<#{html_tag}#{attributes}>#{content}</#{html_tag}>", :process_send)
        end

      elsif method_name == :text && args.any?
        # Directly add the text content without ERB tags
        if args.first.type == :dstr
          # Call process_dstr here to handle dynamic strings
          content = extract_dstr(args.first)
          add_line("<%= #{content} %>", :process_send)
        elsif variable?(args.first) || function_call?(args.first)
          # Call process_dstr here to handle dynamic strings
          content = extract_content(args.first)
          add_line("<%= #{content} %>", :process_send)
        else
          content = args.map { |arg| extract_content(arg) }.join
          add_line(content, :process_send)
        end
      elsif method_name == :empty_tag!

        html_tag = node.children[2].children[0]
        attributes = extract_attributes(node.children.drop(2))
        add_line("<#{html_tag}#{attributes}/>", :process_block)

      elsif function_call?(node)
        process_method(node)
      else
        # Handle variable references
        add_line("<%= #{method_name} %>", :process_send)
      end
    end

    def simple_block?(body)
      return false unless body.is_a?(Parser::AST::Node) &&
                          body.type == :block &&
                          body.children[2] &&
                          body.children[2].children.length == 1

      # Get the actual content node (last expression in the block)
      content_node = body.children[2].children[0]

      # Check if content is an array or hash literal
      return false if content_node.type == :array ||
                      content_node.type == :hash

      true
    end

    def contains_complex_structure?(node)
      return true if [:array, :hash].include?(node.type)

      # Recursively check children for complex structures
      node.children.any? do |child|
        child.is_a?(Parser::AST::Node) &&
          ([:array, :hash].include?(child.type) || contains_complex_structure?(child))
      end
    end

    def process_content_for(method_call, body)
      content_key = extract_content(method_call.children[2])

      # Use inline form for simple content (strings, method calls, variables) or simple blocks
      if body.is_a?(Parser::AST::Node) && contains_complex_structure?(body) == false

        content = if body.type == :str
                    "\"#{extract_content(body)}\""
                  else
                    extract_content(body)
                  end

        add_line("<% content_for #{content_key}, #{content} %>", :process_content_for)
      else
        # Use block form for complex content
        add_line("<% content_for #{content_key} do %>", :process_content_for)
        indent do
          process_node(body) if body
        end
        add_line("<% end %>", :process_content_for)
      end
    end

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

    def process_block(node)
      method_call, args, body = node.children
      method_name = method_call.children[1]

      html_tag, classes, ids = extract_html_tag_and_attributes(node.children[0])

      if html_tag
        attributes = extract_attributes(method_call.children.drop(2))

        attributes = append_classes(attributes, classes)
        attributes = append_ids(attributes, ids)

        add_line("<#{html_tag}#{attributes}>", :process_block)

        indent do
          process_node(body) if body
        end
        add_line("</#{html_tag}>", :process_block)

      elsif method_name == :content_for

        process_content_for(method_call, body)

      elsif iteration_method?(method_name)
        # Handle iteration blocks, e.g., items.each do |item|
        receiver_chain = extract_receiver_chain(method_call.children[0])
        receiver_args = extract_argument_recursive(args).join(',')

        add_line("<% #{receiver_chain}.#{method_name} do |#{receiver_args}| %>", :process_block)

        indent do
          process_node(node.children[2]) if node.children[2]
        end
        add_line('<% end %>', :process_block)

      elsif [:xhtml_transitional, :xhtml_strict, :html4_transitional, :html4_strict].include? method_name
        add_line('<!DOCTYPE html>', :process_block)
        add_line('<html>', :process_block)
        indent do
          process_node(body) if body
        end
        add_line('</html>', :process_block)

      elsif method_name == :tag!
        html_tag = method_call.children[2].children[0]
        attributes = extract_attributes(method_call.children.drop(2))
        add_line("<#{html_tag}#{attributes}>", :process_block)
        indent do
          process_node(node.children[2]) if node.children[2]
        end
        add_line("</#{html_tag}>", :process_block)

      else
        # Combine method call with `do` in one line
        erb_code = "<%= #{extract_content(method_call)} do %>"
        add_line(erb_code, :process_block)

        indent do
          process_node(body) if body
        end
        add_line('<% end %>', :process_block)
      end
    end

    def extract_html_tag_and_attributes(node)
      return nil unless node.is_a?(Parser::AST::Node)
      return nil unless node.type == :send

      classes = []
      ids = []
      current_node = node
      base_tag = nil

      # Walk down the chain collecting classes and ids
      while current_node && current_node.type == :send
        receiver, method_name, *_args = current_node.children

        if receiver.nil?
          # We found the base tag (like h1)
          base_tag = method_name if html_tag?(method_name)
          break
        else
          # If it ends with !, it's an ID, otherwise it's a class
          if method_name.to_s.end_with?('!')
            ids.unshift(method_name.to_s.delete('!'))
          else
            classes.unshift(method_name)
          end
          current_node = receiver
        end
      end

      return nil unless base_tag

      # Return the tag and collected attributes
      [base_tag, classes, ids]
    end

    def extract_dstr(node)
      string_parts = node.children.map do |child|
        case child.type
        when :str
          child.children[0]
        when :begin, :evstr
          "\#{#{extract_content(child.children.first)}}"
        else
          # Handle other possible node types if necessary
          ''
        end
      end
      '"' + string_parts.join + '"'
    end

    def extract_receiver_chain(node)
      if node.nil?
        ''
      elsif node.type == :send
        # Recursively extract the method chain
        receiver = extract_receiver_chain(node.children[0])
        method_name = node.children[1].to_s
        if receiver.empty?
          method_name
        else
          "#{receiver}.#{method_name}"
        end
      else
        node.children[0].to_s
      end
    end

    def extract_content(node)
      return '' if node.nil?

      case node.type
      when :true
        'true'
      when :false
        'false'
      when :str
        node.children[0].to_s
      when :int
        node.children[0].to_i.to_s
      when :float
        node.children[0].to_f.to_s
      when :const
        node.children[1].to_s
      when :sym
        ":#{node.children[0]}"
      when :lvasgn
        node.children[0].to_s
      when :lvar, :cvar, :ivar, :gvar
        node.children[0].to_s
      when :begin
        # assuming only one child
        extract_content(node.children[0])
      when :hash
        extract_content_for_hash(node)
      when :array
        # Properly format array elements
        extract_content_for_array(node)
      when :send
        extract_content_for_send(node)
      when :dstr
        extract_content_for_dstr(node)
      when :if
        # Handle `if` statements
        condition, if_body, else_body = node.children
        "if #{extract_content(condition)} ? #{extract_content(if_body)} : #{extract_content(else_body)}"
      when :or, :and
        extract_content_for_operators(node)
      else
        ''
      end
    end

    def extract_content_for_operators(node)
      expressions = node.children.map do |child|
        case child.type
        when :send
          extract_content_for_send(child)
        when :or, :and
          extract_content_for_operators(child)
        else
          extract_content(child)
        end
      end

      operator = convert_operator(node.type)
      expressions.join(" #{operator} ")
    end

    def convert_operator(op)
      case op
      when :or
        "||"
      when :and
        "&&"
      else
        op.to_s
      end
    end

    def extract_content_for_dstr(node)
      # return node.children.map { |child| extract_content(child) }.join
      # Build the interpolated string, omitting ERB tags
      node.children.map do |child|
        case child.type
        when :str
          child.children[0] # Return static string parts directly
        when :begin, :evstr
          "\#{#{extract_content(child.children.first)}}" # Interpolate dynamic parts
        else
          ""
        end
      end.join
    end

    def extract_content_for_hash(node)
      '{' + node.children.map do |pair|
        key, value = pair.children

        # Determine the key's format
        key_str = key.type == :str ? "'#{extract_content(key)}'" : extract_content(key)

        # Determine if the value contains single quotes and adjust accordingly
        if value.type == :str
          content = extract_content(value)
          # Use double quotes if content contains single quotes
          hash_val = content.include?("'") ? "\"#{content}\"" : "'#{content}'"
        else
          hash_val = extract_content(value)
        end

        "#{key_str} => #{hash_val}"
      end.join(', ') + '}'
    end

    def extract_content_for_array(node)
      array_content = node.children.map do |element|
        case element.type
        when :hash
          extract_content_for_hash(element)
        when :str
          "\"#{extract_content(element)}\""
        when :send
          if element.children[1] == :t
            "t('#{extract_content(element.children[2])}')"
          else
            extract_content(element)
          end
        else
          extract_content(element)
        end
      end.join(', ')

      "[#{array_content}]"
    end

    def extract_content_for_send(node)
      receiver, method_name, *arguments = node.children

      # Special handling for comparison operators
      if %i[> < >= <= == !=].include?(method_name)
        receiver_str = receiver ? extract_content(receiver) : ''
        arg_str = arguments.map do |arg|
          arg.type == :str ? "'#{extract_content(arg)}'" : extract_content(arg)
        end.join
        return "#{receiver_str} #{method_name} #{arg_str}"
      end

      # Special handling for params[:key] syntax
      if receiver && receiver.type == :send && receiver.children[1] == :params && method_name == :[]
        key_node = arguments[0]
        key_str = extract_content(key_node)

        # Properly format the key based on its type
        if key_node.type == :str
          key_str = "'#{key_str}'" # Adds quotes around strings
        else
          key_str = key_str # Leaves variables or dynamic expressions as is
        end

        return "params[#{key_str}]"
      end

      # Handle array access (e.g., `STATUS_TO_READABLE[mail_account.status]`)
      if method_name == :[] && receiver
        receiver_str = extract_content(receiver)
        arguments_str = arguments.map { |arg| extract_content(arg) }.join(", ")
        return "#{receiver_str}[#{arguments_str}]"
      end

      if method_name == :t
        # Special case for translation calls
        return "t('#{extract_content(arguments[0])}')"
      end

      # Special handling for string concatenation with +
      if method_name == :+ && (receiver.type == :str || arguments[0].type == :str || arguments[0].type == :dstr)
        receiver_str = receiver.type == :str ? "'#{extract_content(receiver)}'" : extract_content(receiver)
        arg_str = if arguments[0].type == :str
                    "'#{extract_content(arguments[0]).gsub("\n", '\\n')}'"
                  elsif arguments[0].type == :dstr
                    "\"#{extract_content(arguments[0]).gsub("\n", '\\n')}\""
                  else
                    extract_content(arguments[0])
                  end
        return "#{receiver_str} + #{arg_str}"
      end

      # Special handling for the + operator in method chains
      if method_name == :+ && receiver && receiver.type == :send
        receiver_str = extract_content(receiver)
        arguments_str = arguments.map { |arg| extract_content(arg) }.join
        return "#{receiver_str} + #{arguments_str}" # No parentheses here
      end

      # Normal method call processing
      receiver_str = receiver ? extract_content(receiver) : ''
      arguments_str = arguments.map { |arg| extract_content(arg) }.join(', ')

      # Build the final method call string
      if receiver_str.empty?
        method_name.to_s + (arguments_str.empty? ? '' : "(#{arguments_str})")
      else
        receiver_str + '.' + method_name.to_s + (arguments_str.empty? ? '' : "(#{arguments_str})")
      end
    end

    def extract_argument_recursive(node)
      return [] if node.nil?

      if node.is_a?(Parser::AST::Node) && node.type == :arg
        [node.children[0].to_s]
      else
        node.children.flat_map { |child| extract_argument_recursive(child) if child.is_a?(Parser::AST::Node) }.compact
      end
    end

    def extract_attributes(args)
      return '' if args.empty?

      attributes = args.select { |arg| arg.type == :hash }.flat_map do |hash_arg|
        hash_arg.children.map do |pair|
          key, value = pair.children
          key_str = key.children[0].to_s.gsub(':', '')
          value_str = extract_content(value)
          "#{key_str}=\"#{value_str}\""
        end
      end

      attributes.empty? ? '' : " #{attributes.join(' ')}"
    end

    def html_tag?(method_name)
      %w[html head title body h1 h2 h3 h4 h5 h6 ul ol li a div span p
         table tr td th form input label select option
         textarea button meta br hr img link tbody thead
         hgroup i iframe object pre video tfoot dt em fieldset strong].include?(method_name.to_s)
    end

    def iteration_method?(method_name)
      %w[each map times each_with_index inject each_pair].include?(method_name.to_s)
    end

    def self_closing_tag?(method_name)
      %w[meta input br hr img link].include?(method_name.to_s)
    end

    def helper_call?(method_name)
      helpers = %w[select_field observe_field label form_tag form_for form_remote_tag submit_tag label_tag
                   text_field_tag password_field_tag select_tag check_box_tag radio_button_tag file_field_tag
                   link_to link_to_remote button_to
                   url_for image_tag stylesheet_link_tag javascript_include_tag date_select time_select
                   distance_of_time_in_words truncate highlight simple_format sanitize content_tag flash]

      helpers.include?(method_name.to_s)
    end

    def variable?(node)
      case node.type
      when :lvar, :ivar, :cvar, :gvar
        true  # This is a variable
      else
        false # Not a variable
      end
    end

    def function_call?(node)
      node.type == :send  # A `send` node represents a function call
    end

    def add_line(line, from_method)
      @buffer << (INDENT * @indent_level) + line
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
  end
end
