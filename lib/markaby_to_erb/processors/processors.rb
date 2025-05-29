  module MarkabyToErb
    module Processors

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
              condition_str = conditions.map { |cond|
                cond.type == :str ? "\'#{extract_content(cond)}\'" : extract_content(cond)
              }.join(', ')

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

          # render takes in
          if args.size == 1 && args[0]&.type == :hash
            add_line("<%= #{method_name} #{extract_content_for_hash(args[0], false)} %>", :process_send)
          else
            process_method(node)
          end

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
          add_line("<#{html_tag}#{attributes}/>", :process_send)

        elsif method_name == :end_form
          add_line("</form>", :process_send)

        elsif function_call?(node)
          process_method(node)
        else
          # Handle variable references
          add_line("<%= #{method_name} %>", :process_send)
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


      def function_call?(node)
        node.type == :send  # A `send` node represents a function call
      end

      def contains_complex_structure?(node)
        return true if [:array, :hash].include?(node.type)

        # Recursively check children for complex structures
        node.children.any? do |child|
          child.is_a?(Parser::AST::Node) &&
            ([:array, :hash].include?(child.type) || contains_complex_structure?(child))
        end
      end

    end
   end
