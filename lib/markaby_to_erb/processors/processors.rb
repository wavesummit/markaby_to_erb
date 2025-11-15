  module MarkabyToErb
    module Processors

      def process_if(node)
        condition_node, if_body, else_body = node.children

        # Check if this is a ternary operator (both branches are simple expressions)
        # Ternary: condition ? true_value : false_value
        is_ternary = if_body && else_body && 
                     ![:begin, :if, :while, :until, :rescue, :kwbegin].include?(if_body.type) &&
                     ![:begin, :if, :while, :until, :rescue, :kwbegin].include?(else_body.type)
        
        if is_ternary
          # Output as ternary operator
          # Unwrap :begin nodes in condition
          condition_str = if condition_node.type == :begin
                           extract_content(condition_node.children[0])
                         else
                           extract_content(condition_node)
                         end
          true_str = if if_body.type == :str
                      "'#{extract_content(if_body)}'"
                    else
                      extract_content(if_body)
                    end
          false_str = if else_body.type == :str
                       "'#{extract_content(else_body)}'"
                     else
                       extract_content(else_body)
                     end
          add_line("<% #{condition_str} ? #{true_str}:#{false_str} %>", :process_if)
          return
        end

        # Handle modifier forms like "retry if condition"
        if if_body&.type == :retry || if_body&.type == :redo || if_body&.type == :break || if_body&.type == :next
          add_line("<% if #{extract_content(condition_node)} %>", :process_if)
          indent do
            process_node(if_body)
          end
          add_line("<% end %>", :process_if)
          return
        end

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
        when :kwbegin
          process_kwbegin(node)
        when :rescue
          process_rescue(node)
        when :resbody
          process_resbody(node)
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
        when :while
          process_while(node)
        when :until
          process_until(node)
        when :for
          process_for(node)
        when :break
          process_break(node)
        when :redo
          process_redo(node)
        when :retry
          process_retry(node)
        else
          puts "Unhandled node type: #{node.type}"
        end
      end

      def process_yield(node)
        add_line("<%= yield %>", :process_yield)
      end

      def process_begin(node)
        # Check if this begin node has rescue clauses
        # A begin node with rescue has: [body, resbody1, resbody2, ...]
        has_rescue = node.children.any? { |child| child&.type == :resbody }
        
        if has_rescue
          # First child is the main body
          body = node.children[0]
          # Remaining children are rescue clauses
          rescue_clauses = node.children[1..-1]
          
          add_line("<% begin %>", :process_begin)
          indent do
            process_node(body) if body
          end
          
          rescue_clauses.each do |rescue_clause|
            if rescue_clause&.type == :resbody
              # resbody structure: [exception_list, exception_var, body]
              exception_list, exception_var, rescue_body = rescue_clause.children
              
              rescue_line = "<% rescue"
              if exception_list
                exception_str = exception_list.children.map { |e| extract_content(e) }.join(', ')
                rescue_line += " #{exception_str}"
              end
              if exception_var
                rescue_line += " => #{extract_content(exception_var)}"
              end
              rescue_line += " %>"
              
              add_line(rescue_line, :process_begin)
              indent do
                process_node(rescue_body) if rescue_body
              end
            end
          end
          
          add_line("<% end %>", :process_begin)
        else
          # Regular begin block without rescue - just process children
          node.children.each do |child|
            process_node(child)
          end
        end
      end

      def process_kwbegin(node)
        # kwbegin is used for begin/end blocks (as opposed to { } blocks)
        # It can contain rescue clauses
        if node.children.first&.type == :rescue
          # If first child is rescue, process it
          process_rescue(node.children.first)
        else
          # Otherwise, process as regular begin
          add_line("<% begin %>", :process_kwbegin)
          indent do
            node.children.each do |child|
              process_node(child)
            end
          end
          add_line("<% end %>", :process_kwbegin)
        end
      end

      def process_rescue(node)
        # rescue structure: [body, resbody1, resbody2, ..., else_clause]
        # body is the main code block
        # resbody nodes are rescue clauses
        # last child might be an else clause
        body = node.children[0]
        rescue_clauses = node.children[1..-1].select { |c| c&.type == :resbody }
        else_clause = node.children.last if node.children.last&.type != :resbody
        
        add_line("<% begin %>", :process_rescue)
        # Check if body is a single HTML tag call - don't indent in that case
        is_single_html_tag = body && body.type == :send && html_tag?(body.children[1])
        if is_single_html_tag
          process_node(body) if body
        else
          indent do
            process_node(body) if body
          end
        end
        
        rescue_clauses.each do |rescue_clause|
          process_resbody(rescue_clause)
        end
        
        if else_clause
          add_line("<% else %>", :process_rescue)
          indent do
            process_node(else_clause)
          end
        end
        
        add_line("<% end %>", :process_rescue)
      end

      def process_resbody(node)
        # resbody structure: [exception_list, exception_var, body]
        exception_list, exception_var, rescue_body = node.children
        
        rescue_line = "<% rescue"
        if exception_list
          exception_str = exception_list.children.map { |e| extract_content(e) }.join(', ')
          rescue_line += " #{exception_str}"
        end
        if exception_var
          # exception_var can be :ivasgn, :lvasgn, or a variable node
          var_name = if exception_var.type == :ivasgn || exception_var.type == :lvasgn
                       exception_var.children[0].to_s
                     else
                       extract_content(exception_var)
                     end
          rescue_line += " => #{var_name}"
        end
        rescue_line += " %>"
        
        add_line(rescue_line, :process_resbody)
        # Check if rescue_body is a single HTML tag call - don't indent in that case
        is_single_html_tag = rescue_body && rescue_body.type == :send && html_tag?(rescue_body.children[1])
        if is_single_html_tag
          process_node(rescue_body) if rescue_body
        else
          indent do
            process_node(rescue_body) if rescue_body
          end
        end
      end

      def process_op_asgn(node)
        # For :op_asgn, children are: [variable_node, operator, value_node]
        variable_node = node.children[0]
        operator = node.children[1]
        value_node = node.children[2]
        
        # Extract variable name directly from the node
        # Handle both :ivar/:lvar (variable reference) and :ivasgn/:lvasgn (assignment target)
        variable = if variable_node.type == :ivar || variable_node.type == :lvar
                     variable_node.children[0].to_s
                   elsif variable_node.type == :ivasgn || variable_node.type == :lvasgn
                     variable_node.children[0].to_s
                   else
                     extract_content(variable_node)
                   end
        
        value = extract_content(value_node)

        # Format the value with parentheses if it's a complex expression
        formatted_value = value_node.type == :begin ? "( #{value} )" : value
        formatted_value = "\"#{value}\"" if value_node.type == :str

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

      def process_while(node)
        condition, body = node.children
        condition_str = extract_content(condition)
        add_line("<% while #{condition_str} %>", :process_while)
        indent do
          process_node(body) if body
        end
        add_line("<% end %>", :process_while)
      end

      def process_until(node)
        condition, body = node.children
        condition_str = extract_content(condition)
        add_line("<% until #{condition_str} %>", :process_until)
        indent do
          process_node(body) if body
        end
        add_line("<% end %>", :process_until)
      end

      def process_for(node)
        # for item in collection
        # node.children: [variable, collection, body]
        variable, collection, body = node.children
        var_name = variable.children[0].to_s
        collection_str = extract_content(collection)
        add_line("<% for #{var_name} in #{collection_str} %>", :process_for)
        indent do
          process_node(body) if body
        end
        add_line("<% end %>", :process_for)
      end

      def process_break(node)
        condition = node.children[0]
        if condition
          condition_str = extract_content(condition)
          add_line("<% break if #{condition_str} %>", :process_break)
        else
          add_line("<% break %>", :process_break)
        end
      end

      def process_redo(node)
        condition = node.children[0]
        if condition
          condition_str = extract_content(condition)
          add_line("<% redo if #{condition_str} %>", :process_redo)
        else
          add_line("<% redo %>", :process_redo)
        end
      end

      def process_retry(node)
        condition = node.children[0]
        if condition
          condition_str = extract_content(condition)
          add_line("<% retry if #{condition_str} %>", :process_retry)
        else
          add_line("<% retry %>", :process_retry)
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
            # Handle blocks (e.g., (1..15).collect { |n| [n, n] })
            if value_node.type == :block
              value = extract_block_expression(value_node)
            elsif value_node.type == :dstr
              # Preserve quotes for dstr in assignments
              value = extract_dstr(value_node)
            elsif value_node.type == :begin
              # Handle begin nodes (parentheses) - check if inner is % operator
              inner = value_node.children[0]
              if inner && inner.type == :send && inner.children[1] == :%
                # % operator - keep parentheses
                value = "(#{extract_content(inner)})"
              else
                value = extract_content(value_node)
              end
            elsif value_node.type == :send && value_node.children[1] == :%
              # % operator - wrap in parentheses for assignments
              value = "(#{extract_content(value_node)})"
            else
              value = extract_content(value_node)
            end

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

      def extract_block_expression(node)
        # node is a :block type with children: [method_call, args, body]
        method_call, args, body = node.children
        receiver, method_name, *method_args = method_call.children
        
        # Extract receiver chain (e.g., (1..15)) - use extract_content which handles ranges
        receiver_str = receiver ? extract_content(receiver) : ''
        
        # Extract block arguments (e.g., |n|)
        block_args = if args && args.type == :args
                       args.children.map { |arg| arg.children[0].to_s }.join(', ')
                     else
                       ''
                     end
        
        # Extract block body (e.g., [n, n])
        block_body = body ? extract_content(body) : ''
        
        # Build the expression: receiver.method { |args| body }
        # Format block args - test expects {|p| format (no space after {)
        block_args_formatted = block_args.empty? ? '' : "|#{block_args}|"
        if receiver_str.empty?
          method_args_str = method_args.map { |a| extract_content(a) }.join(', ')
          "#{method_name}(#{method_args_str}) {#{block_args_formatted} #{block_body} }"
        else
          "#{receiver_str}.#{method_name} {#{block_args_formatted} #{block_body} }"
        end
      end

      def process_method(node, statement_context: false)
        receiver, method_name, *args = node.children
        # Count how many hash arguments we have
        hash_count = args.count { |arg| arg.type == :hash }
        arguments = args.map.with_index do |arg, index|
          if arg.type == :hash
            # Check if hash contains nested hashes (complex structure)
            has_nested_hash = arg.children.any? do |pair|
              pair.children[1] && pair.children[1].type == :hash
            end
            
            # For hash arguments, don't wrap in curly braces only if:
            # 1. It's the only argument (no other arguments at all)
            # 2. It doesn't contain nested hashes
            # Otherwise, keep the braces for clarity
            is_only_arg = (args.length == 1)
            should_wrap = hash_count > 1 || !is_only_arg || has_nested_hash
            extract_content_for_hash(arg, should_wrap)
          elsif [:str, :dstr].include?(arg.type)
            "\"#{extract_content(arg)}\""
          else
            extract_content(arg)
          end
        end.join(', ')

        # Build the method call with receiver if present
        receiver_str = receiver ? extract_content(receiver) : ''
        method_call_str = if receiver_str.empty?
                           method_name.to_s
                         else
                           "#{receiver_str}.#{method_name}"
                         end

        # Build the method call
        # Only add parentheses if there are multiple hash arguments (for clarity)
        # or if the arguments contain complex structures
        if arguments.empty?
          result = method_call_str
        elsif hash_count > 1
          # Multiple hash arguments - use parentheses for clarity
          result = "#{method_call_str}(#{arguments})"
        else
          # Single argument or simple arguments - no parentheses (Ruby style)
          result = "#{method_call_str} #{arguments}"
        end
        # If it's a statement context and has no arguments, use <% instead of <%=
        erb_code = if statement_context && arguments.empty? && receiver_str.empty?
                     "<% #{result} %>"
                   else
                     "<%= #{result} %>"
                   end
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
            # For helper calls with multiple arguments, process through process_method
            # but ensure hash arguments don't get wrapped in curly braces
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
            when :dstr
              # Handle dynamic strings with interpolation
              dstr_content = extract_dstr(arg)
              "<%= #{dstr_content} %>"
            when :if
              # Handle ternary operators in tag content
              condition, if_body, else_body = arg.children
              condition_str = if condition && condition.type == :begin
                               extract_content(condition.children[0])
                             else
                               extract_content(condition)
                             end
              true_str = if if_body && if_body.type == :str
                          "'#{extract_content(if_body)}'"
                        else
                          extract_content(if_body)
                        end
              false_str = if else_body && else_body.type == :str
                           "'#{extract_content(else_body)}'"
                         else
                           extract_content(else_body)
                         end
              "<%= #{condition_str} ? #{true_str} : #{false_str} %>"
            else
              extract_content(arg)
            end
          end.join

          if content.empty?
            # self closing tags are like br, input
            if self_closing_tag?(html_tag)
              add_line("<#{html_tag}#{attributes}>", :process_send1)
            else
              add_line("<#{html_tag}#{attributes}></#{html_tag}>", :process_send)
            end
          else
            # Add the opening tag and content in the same line if there's no nested block.
            add_line("<#{html_tag}#{attributes}>#{content}</#{html_tag}>", :process_send)
          end

        elsif method_name == :text && args.any?
          # Directly add the text content without ERB tags
          if args.first.type == :dstr
            # For dstr with only static string parts (no interpolation), output directly
            # Check if all parts are :str (no interpolation)
            all_static = args.first.children.all? { |child| child.type == :str }
            if all_static
              # Extract all string parts and join them
              parts = args.first.children.map { |child| child.children[0] }
              content = parts.join
              # Handle backslash escapes that continue lines
              # If a line ends with { and the next line starts with }, join them
              lines = content.split("\n")
              processed_lines = []
              i = 0
              while i < lines.length
                if lines[i].end_with?('{') && i + 1 < lines.length && lines[i + 1].start_with?('}')
                  # Join lines (backslash escape removed the newline)
                  processed_lines << lines[i] + lines[i + 1]
                  i += 2
                else
                  processed_lines << lines[i]
                  i += 1
                end
              end
              # Format with proper indentation (2 spaces for continuation lines, but not for closing tags)
              formatted = processed_lines.map.with_index do |line, i|
                if i == 0 || line.strip.start_with?('</')
                  line
                else
                  "  #{line}"
                end
              end.join("\n")
              add_line(formatted, :process_send)
            else
              # Has interpolation, use ERB tags
              content = extract_dstr(args.first)
              add_line("<%= #{content} %>", :process_send)
            end
          elsif variable?(args.first) || function_call?(args.first)
            # Call process_dstr here to handle dynamic strings
            content = extract_content(args.first)
            add_line("<%= #{content} %>", :process_send)
          elsif args.first.type == :str
            # For static strings, output directly without ERB tags
            # Remove backslash escapes and preserve newlines
            content = args.first.children[0].gsub('\\', '').gsub("\n", "\n        ")
            add_line(content, :process_send)
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

        elsif method_name == :<<
          # Handle << operator (shovel operator) as a statement, not output
          receiver_str = receiver ? extract_content(receiver) : ''
          arg_str = args.map { |arg| extract_content(arg) }.join(', ')
          add_line("<% #{receiver_str} << #{arg_str} %>", :process_send)
        elsif method_name == :+
          # Handle + operator (string concatenation) in block bodies
          # Check if this is string concatenation
          receiver_is_str = receiver && (receiver.type == :str || receiver.type == :dstr)
          arg_is_str = args[0] && (args[0].type == :str || args[0].type == :dstr)
          receiver_is_plus = receiver && receiver.type == :send && receiver.children[1] == :+
          
          if receiver_is_str || arg_is_str || receiver_is_plus
            # Extract the concatenation expression
            content = extract_content(node)
            add_line("<%= #{content} %>", :process_send)
          else
            # Not string concatenation, process as normal method call
            process_method(node)
          end
        elsif function_call?(node)
          # Method calls in statement context (not inside tags) should use <% not <%=
          process_method(node, statement_context: true)
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
