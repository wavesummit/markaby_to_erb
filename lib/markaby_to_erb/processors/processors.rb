  module MarkabyToErb
    module Processors

      def contains_html_or_helper?(node)
        return false unless node
        case node.type
        when :send
          method_name = node.children[1]
          receiver = node.children[0]
          arguments = node.children[2..-1] || []
          # Check for HTML tags, helper calls, or Markaby-specific methods like 'text'
          # Also check if method call has empty parentheses (e.g., do_stuff()) - these should be full blocks
          has_empty_parens = arguments.empty? && method_name != :[] && method_name != :!
          # Check if receiver is an HTML tag (e.g., img.thumbnail_style.cropped_style!)
          # Recursively check the receiver chain
          receiver_is_html = receiver && contains_html_in_receiver_chain?(receiver)
          html_tag?(method_name) || helper_call?(method_name) || method_name == :text || 
            has_empty_parens || receiver_is_html
        when :begin
          node.children.any? { |child| contains_html_or_helper?(child) }
        when :block
          # Check if block contains HTML tags or helper calls
          method_call, args, body = node.children
          method_name = method_call.children[1] if method_call && method_call.type == :send
          # Check if the method call itself is an HTML tag or helper
          if method_name && (html_tag?(method_name) || helper_call?(method_name))
            return true
          end
          # Check the block body for HTML tags or helpers
          contains_html_or_helper?(body)
        else
          false
        end
      end

      def contains_html_in_receiver_chain?(node)
        return false unless node
        return false unless node.type == :send
        method_name = node.children[1]
        receiver = node.children[0]
        # Check if this method call is on an HTML tag
        return true if html_tag?(method_name)
        # Recursively check the receiver
        return contains_html_in_receiver_chain?(receiver) if receiver
        false
      end

      def process_if(node)
        condition_node, if_body, else_body = node.children

        # Check if this is a ternary operator (both branches are simple expressions)
        # Ternary: condition ? true_value : false_value
        # Don't convert to ternary if branches contain HTML tags or helper calls
        # Also don't convert if dstr nodes contain HTML (should be converted to ERB format)
        # Don't convert assignments to ternary (they should be full if/else blocks)
        excluded_types = [:begin, :if, :while, :until, :rescue, :kwbegin, :lvasgn, :ivasgn, :cvasgn, :gvasgn, :op_asgn]
        is_ternary = if_body && else_body && 
                     !excluded_types.include?(if_body.type) &&
                     !excluded_types.include?(else_body.type) &&
                     !contains_html_or_helper?(if_body) &&
                     !contains_html_or_helper?(else_body) &&
                     !dstr_contains_html?(if_body) &&
                     !dstr_contains_html?(else_body)
        
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
                    elsif if_body.type == :dstr
                      # For dynamic strings, wrap in double quotes
                      dstr_content = extract_content_for_dstr(if_body)
                      "\"#{dstr_content}\""
                    else
                      extract_content(if_body)
                    end
          false_str = if else_body.type == :str
                       "'#{extract_content(else_body)}'"
                     elsif else_body.type == :dstr
                       # For dynamic strings, wrap in double quotes
                       dstr_content = extract_content_for_dstr(else_body)
                       "\"#{dstr_content}\""
                     else
                       extract_content(else_body)
                     end
          # Output ternary operator - check if we're in a JavaScript string context
          # For JavaScript strings, preserve space after colon
          # Otherwise, remove space after colon to match test expectations
          # Heuristic: if the false_str is an empty string in quotes AND true_str is NOT a string literal, preserve space
          # This handles: @collection ? @collection.permalink : "" (in JS strings - true_str is a variable/property)
          # But not: 'width:286px' : '' (regular ternary - true_str is a string literal, no space)
          is_js_string_context = (false_str == '""' || false_str == "''") && 
                                 !true_str.start_with?("'") && !true_str.start_with?('"')
          space_after_colon = is_js_string_context ? " : " : ":"
          add_line("<% #{condition_str} ? #{true_str}#{space_after_colon}#{false_str} %>", :process_if)
          return
        end

        # Handle modifier forms like "retry if condition" or "statement if condition"
        # Modifier if: statement if condition (no else_body, simple if_body)
        # Also handle modifier unless: statement unless condition (same structure, but uses unless)
        # Don't treat assignments as modifier statements
        # Don't treat HTML tags or helper calls as modifier statements (they should be full blocks)
        if else_body.nil? && if_body && ![:begin, :if, :while, :until, :rescue, :kwbegin, :block, :lvasgn, :ivasgn, :op_asgn].include?(if_body.type)
          # Check if it's a special control flow statement that should stay as modifier
          if if_body.type == :retry || if_body.type == :redo || if_body.type == :break || if_body.type == :next
            add_line("<% if #{extract_content(condition_node)} %>", :process_if)
            indent do
              process_node(if_body)
            end
            add_line("<% end %>", :process_if)
            return
          elsif contains_html_or_helper?(if_body)
            # Body contains HTML tags or helper calls - must be a full block, not a modifier
            add_line("<% if #{extract_content(condition_node)} %>", :process_if)
            indent do
              process_node(if_body)
            end
            add_line("<% end %>", :process_if)
            return
          else
            # Regular modifier if/unless - output as "statement if/unless condition"
            # For now, always output as "if" - unless detection would require checking the original source
            statement_str = extract_content(if_body)
            condition_str = extract_content(condition_node)
            add_line("<% #{statement_str} if #{condition_str} %>", :process_if)
            return
          end
        end

        # Check if else_body is an :if node (indicating an elsif)
        # But first check if it's actually an unless block (if_body is nil)
        if else_body&.type == :if
          # Check if this is actually an unless block (if_body is nil, else_body is non-nil)
          # In that case, we should process it as a nested unless, not as an elsif chain
          nested_condition, nested_if_body, nested_else_body = else_body.children
          if nested_if_body.nil? && nested_else_body
            # This is a nested unless block - process it as unless, not elsif
            # The outer unless wraps the inner unless
            add_line("<% unless #{extract_content(condition_node)} %>", :process_if)
            indent do
              add_line("<% unless #{extract_content(nested_condition)} %>", :process_if)
              indent do
                process_node(nested_else_body)
              end
              add_line('<% end %>', :process_if)
            end
            add_line('<% end %>', :process_if)
            return
          else
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
          end
        elsif if_body.nil? && else_body
          # Convert to unless when we have nil if_body and non-nil else_body
          # This handles "unless condition; ... end" which is represented as "if condition; nil; else; ... end"
          # Check if it's a modifier form: "statement unless condition"
          excluded_types = [:begin, :if, :while, :until, :rescue, :kwbegin, :block, :lvasgn, :ivasgn, :op_asgn]
          is_simple_statement = else_body && !excluded_types.include?(else_body.type)
          
          # Don't treat HTML tags or helper calls as modifier statements (they should be full blocks)
          if is_simple_statement && !contains_html_or_helper?(else_body)
            # Modifier unless - output as "statement unless condition"
            statement_str = extract_content(else_body)
            condition_str = extract_content(condition_node)
            add_line("<% #{statement_str} unless #{condition_str} %>", :process_if)
            return
          else
            # Regular unless block
            add_line("<% unless #{extract_content(condition_node)} %>", :process_if)
            indent do
              process_node(else_body)
            end
            add_line('<% end %>', :process_if)
            return
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

      def process_unless(node)
        # unless nodes have structure: [condition, body] (2 children) or [condition, body, else_body] (3 children)
        # For modifier form: "statement unless condition", we have [condition, statement] (2 children)
        # For regular form: "unless condition; statement; end", we have [condition, statement] (2 children)
        # The difference is detected by checking if body is a simple statement (not a block)
        condition_node = node.children[0]
        unless_body = node.children[1]
        else_body = node.children[2]  # nil for modifier form and regular unless

        # Handle modifier forms like "statement unless condition"
        # Modifier unless has: no else_body, and unless_body is a simple statement (not a block)
        # Don't treat assignments as modifier statements
        # Check if this is a modifier form - same logic as process_if
        # For modifier unless, the AST structure is: [condition, body] (2 children)
        # The source is "body unless condition", so body is the second child
        # Handle modifier forms: "statement unless condition"
        # Modifier unless has: no else_body, and unless_body is a simple statement (not a block)
        # The AST structure for modifier unless is: [condition, body] (2 children)
        # For "classes << 'field_invalid' unless field.good?", the structure is:
        # [:unless, [:send, ...], [:send, nil, :classes, :<<, ...]]
        # So condition_node is the condition, and unless_body is the statement
        if else_body.nil? && unless_body
          # Check if unless_body is a simple statement (not a block or assignment)
          unless_body_type = unless_body.type
          # Exclude complex statements that should be full blocks
          excluded_types = [:begin, :if, :while, :until, :rescue, :kwbegin, :block, :lvasgn, :ivasgn, :op_asgn]
          is_simple_statement = !excluded_types.include?(unless_body_type)
          
          # Don't treat HTML tags or helper calls as modifier statements (they should be full blocks)
          if is_simple_statement && !contains_html_or_helper?(unless_body)
            # Modifier unless - output as "statement unless condition"
            statement_str = extract_content(unless_body)
            condition_str = extract_content(condition_node)
            add_line("<% #{statement_str} unless #{condition_str} %>", :process_unless)
            return
          end
        end

        # Handle regular unless statements
        add_line("<% unless #{extract_content(condition_node)} %>", :process_unless)
        indent do
          process_node(unless_body) if unless_body
        end
        if else_body
          add_line('<% else %>', :process_unless)
          indent do
            process_node(else_body)
          end
        end
        add_line('<% end %>', :process_unless)
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
        when :unless
          process_unless(node)
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
        when :const
          process_const(node)
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
        when :and
          process_and(node)
        when :or
          process_or(node)
        when :lvar
          process_lvar(node)
        when :ivar
          process_ivar(node)
        else
          raise ConversionError.new("Unhandled node type: #{node.type}",
                                    node_type: node.type,
                                    line_number: @buffer.length + 1,
                                    context: "Processing node in #{caller_locations(1, 1).first.label}")
        end
      end

      def process_yield(node)
        add_line("<%= yield %>", :process_yield)
      end

      def process_const(node)
        # Handle constant references like Mab, Date::ABBR_MONTHNAMES, etc.
        # Output as ERB expression since constants are typically used for output
        const_str = extract_content(node)
        add_line("<%= #{const_str} %>", :process_const)
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

      def process_and(node)
        # For :and nodes used as statements, process both children as separate statements
        # e.g., "foo and bar" becomes two statements: foo, then bar
        left, right = node.children
        process_node(left) if left
        process_node(right) if right
      end

      def process_or(node)
        # For :or nodes used as statements, process both children as separate statements
        # e.g., "foo or bar" becomes two statements: foo, then bar
        left, right = node.children
        process_node(left) if left
        process_node(right) if right
      end

      def process_lvar(node)
        # Local variable reference - output with ERB tags when in output context
        var_name = node.children[0]
        add_line("<%= #{var_name} %>", :process_lvar)
      end

      def process_ivar(node)
        # Instance variable reference - output with ERB tags when in output context
        var_name = node.children[0]
        add_line("<%= #{var_name} %>", :process_ivar)
      end

      def has_interpolation?(dstr_node)
        return false unless dstr_node && dstr_node.type == :dstr
        dstr_node.children.any? { |child| [:begin, :evstr].include?(child.type) }
      end

      def dstr_contains_html?(dstr_node)
        return false unless dstr_node && dstr_node.type == :dstr
        # Check if any string parts contain HTML tags
        dstr_node.children.any? do |child|
          if child.type == :str
            # Check if string contains HTML tags (simple pattern: < followed by word characters)
            child.children[0] =~ /<[a-zA-Z]/
          else
            false
          end
        end
      end

      def process_method_with_heredoc_interpolation(node, dstr_node, arg_index)
        # Process method call with heredoc string argument containing interpolation
        # Convert #{...} interpolations to ERB tags while preserving the heredoc structure
        receiver, method_name, *args = node.children
        
        # Build arguments before the heredoc
        args_before = args[0...arg_index]
        args_after = args[(arg_index + 1)..-1]
        
        # Process heredoc with interpolation
        heredoc_parts = []
        dstr_node.children.each do |child|
          case child.type
          when :str
            heredoc_parts << { type: :string, content: child.children[0] }
          when :begin, :evstr
            interpolation_code = extract_content(child.children.first)
            # Normalize quotes - convert single to double for consistency
            if interpolation_code.include?("'") && !interpolation_code.include?('"')
              interpolation_code = interpolation_code.gsub(/'/, '"')
            end
            # Check if interpolation contains a ternary operator and preserve spacing for JS strings
            # In JavaScript strings (heredoc context), ternary operators should have space after colon
            # The interpolation code might have :"" (no space) or : "" (with space) from extract_content
            # Normalize spacing: ensure exactly one space before colon when followed by empty string
            if interpolation_code.include?('?') && interpolation_code.match(/:\s*(""|'')/)
              # Only add space if there's no space before colon (avoid double spaces)
              unless interpolation_code.include?(' : ""') || interpolation_code.include?(" : ''")
                interpolation_code = interpolation_code.gsub(/:/, ' : ') if interpolation_code.end_with?('""') || interpolation_code.end_with?("''")
              end
            end
            heredoc_parts << { type: :erb, content: interpolation_code }
          end
        end
        
        # Build the heredoc content, replacing #{...} with <%= ... %>
        heredoc_content = heredoc_parts.map do |part|
          if part[:type] == :string
            part[:content]
          else
            "<%= #{part[:content]} %>"
          end
        end.join
        
        # Build method call arguments
        receiver_str = receiver ? extract_content(receiver) : ''
        method_call_str = if receiver_str.empty?
                           method_name.to_s
                         else
                           "#{receiver_str}.#{method_name}"
                         end
        
        # Build arguments before heredoc
        args_before_str = args_before.map { |arg| extract_content(arg) }.join(', ')
        
        # Build arguments after heredoc
        args_after_str = args_after.map { |arg| extract_content(arg) }.join(', ')
        
        # Format heredoc with proper indentation
        heredoc_lines = heredoc_content.split("\n", -1)
        
        # Output the method call with heredoc
        if args_before_str.empty? && args_after_str.empty?
          # Only heredoc argument
          add_line("<%= #{method_call_str} %{", :process_method_with_heredoc_interpolation)
          heredoc_lines.each_with_index do |line, idx|
            if line.empty?
              next if idx == 0 || idx == heredoc_lines.length - 1
              add_line("", :process_method_with_heredoc_interpolation)
            else
              add_line("  #{line}", :process_method_with_heredoc_interpolation)
            end
          end
          add_line("} %>", :process_method_with_heredoc_interpolation)
        else
          # Has other arguments - need to format carefully
          args_before_part = args_before_str.empty? ? '' : "#{args_before_str}, "
          args_after_part = args_after_str.empty? ? '' : ", #{args_after_str}"
          
          add_line("<%= #{method_call_str} #{args_before_part}%{", :process_method_with_heredoc_interpolation)
          heredoc_lines.each_with_index do |line, idx|
            if line.empty?
              next if idx == 0 || idx == heredoc_lines.length - 1
              add_line("", :process_method_with_heredoc_interpolation)
            else
              # Strip any existing leading whitespace and add exactly 2 spaces
              stripped_line = line.lstrip
              add_line("  #{stripped_line}", :process_method_with_heredoc_interpolation)
            end
          end
          add_line("}#{args_after_part} %>", :process_method_with_heredoc_interpolation)
        end
      end

      def process_javascript_tag_with_interpolation(node, dstr_node)
        # Process javascript_tag with dynamic string that contains interpolations
        # Convert #{...} interpolations to ERB tags while preserving the heredoc structure
        # Reconstruct the JavaScript string by walking through dstr children
        js_content_parts = []
        dstr_node.children.each do |child|
          case child.type
          when :str
            # Static string part - keep as-is
            js_content_parts << child.children[0]
          when :begin, :evstr
            # Interpolation - replace #{...} with <%= ... %>
            interpolation_code = extract_content(child.children.first)
            # Normalize quotes in interpolation - use double quotes for consistency
            # Convert single quotes to double quotes, including empty strings
            if interpolation_code.include?("'") && !interpolation_code.include?('"')
              interpolation_code = interpolation_code.gsub(/'/, '"')
            end
            # Check if interpolation contains a ternary operator and preserve spacing for JS strings
            # In JavaScript strings, ternary operators should have space after colon: condition ? true : false
            # The interpolation code from extract_content has :"" (no space), we need : "" (with space)
            # Match :"" or :'' (with or without space before quotes) and add space before colon
            if interpolation_code.include?('?') && interpolation_code.match(/:\s*(""|'')/)
              # Replace :"" with : "" and :'' with : '' (add space before colon)
              interpolation_code = interpolation_code.gsub(/:\s*(""|'')/, ' : \1')
            end
            js_content_parts << "<%= #{interpolation_code} %>"
          end
        end
        
        # Join all parts to reconstruct the JavaScript string
        js_content = js_content_parts.join
        
        # Output the javascript_tag call with heredoc
        # Split into lines to preserve formatting
        js_lines = js_content.split("\n", -1)
        add_line("<%= javascript_tag %{", :process_javascript_tag_with_interpolation)
        js_lines.each_with_index do |line, idx|
          # Preserve original indentation (2 spaces for content lines)
          # Skip empty lines at start/end, but keep internal empty lines
          if line.empty?
            # Only add empty line if it's not at the start or end
            next if idx == 0 || idx == js_lines.length - 1
            add_line("", :process_javascript_tag_with_interpolation)
          else
            # Strip any existing leading whitespace and add exactly 2 spaces
            stripped_line = line.lstrip
            add_line("  #{stripped_line}", :process_javascript_tag_with_interpolation)
          end
        end
        add_line("} %>", :process_javascript_tag_with_interpolation)
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
        # If the dstr contains HTML tags, convert interpolations to ERB format
        if dstr_contains_html?(node)
          # Convert HTML string with interpolation to ERB format
          html_parts = []
          node.children.each do |child|
            case child.type
            when :str
              html_parts << child.children[0]
            when :begin, :evstr
              interpolation_code = extract_content(child.children.first)
              html_parts << "<%= #{interpolation_code} %>"
            end
          end
          add_line(html_parts.join, :process_dstr)
        else
          # Regular dynamic string - use string interpolation syntax
          value = extract_dstr(node)
          add_line("<%= #{value} %>", :process_str)
        end
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
              # Check if this is a capture block
              block_method_call = value_node.children[0]
              if block_method_call && block_method_call.type == :send && block_method_call.children[1] == :capture
                # Handle capture block specially
                var_name_str = var_name.to_s
                add_line("<% #{var_name_str} = capture do %>", :process_assignment)
                capture_body = value_node.children[2]
                indent do
                  process_node(capture_body) if capture_body
                end
                add_line("<% end %>", :process_assignment)
                return
              else
                value = extract_block_expression(value_node)
              end
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
        # Format block args - use { |args| format (with space) for consistency
        block_args_formatted = block_args.empty? ? '' : " |#{block_args}|"
        if receiver_str.empty?
          method_args_str = method_args.map { |a| extract_content(a) }.join(', ')
          "#{method_name}(#{method_args_str}) {#{block_args_formatted} #{block_body} }"
        else
          "#{receiver_str}.#{method_name} {#{block_args_formatted} #{block_body} }"
        end
      end

      def process_method(node, statement_context: false)
        receiver, method_name, *args = node.children
        
        # Special handling for javascript_tag with dynamic strings
        if method_name == :javascript_tag && args.first && args.first.type == :dstr
          process_javascript_tag_with_interpolation(node, args.first)
          return
        end
        
        # Check for heredoc strings (%{...}) with interpolation in arguments
        # These need special handling to convert #{...} to ERB tags
        # Only treat as heredoc if it's a multi-line string (contains newlines)
        heredoc_arg_index = args.find_index do |arg|
          arg.type == :dstr && has_interpolation?(arg) && 
          arg.children.any? { |child| child.type == :str && child.children[0].include?("\n") }
        end
        if heredoc_arg_index
          process_method_with_heredoc_interpolation(node, args[heredoc_arg_index], heredoc_arg_index)
          return
        end
        
        # Check if first argument is a capture block
        first_arg_is_capture = args.first && args.first.type == :block && 
                               args.first.children[0] && args.first.children[0].type == :send &&
                               args.first.children[0].children[1] == :capture
        
        if first_arg_is_capture
          # Handle capture block as first argument specially
          capture_block = args.first
          remaining_args = args[1..-1]
          
          # Build method call with capture block
          receiver_str = receiver ? extract_content(receiver) : ''
          method_call_str = if receiver_str.empty?
                            method_name.to_s
                          else
                            "#{receiver_str}.#{method_name}"
                          end
          
          # Output: <%= method_name capture do %>
          add_line("<%= #{method_call_str} capture do %>", :process_method)
          
          # Process capture block body
          capture_body = capture_block.children[2]
          indent do
            process_node(capture_body) if capture_body
          end
          
          # Output remaining arguments after end
          if remaining_args.any?
            remaining_args_str = remaining_args.map.with_index do |arg, index|
              if arg.type == :hash
                hash_count = remaining_args.count { |a| a.type == :hash }
                has_nested_hash = arg.children.any? { |pair| pair.children[1] && pair.children[1].type == :hash }
                is_last = (index == remaining_args.length - 1)
                # Always wrap hash arguments when they come after a capture block
                should_wrap = true
                extract_content_for_hash(arg, should_wrap)
              elsif [:str, :dstr].include?(arg.type)
                "\"#{extract_content(arg)}\""
              else
                extract_content(arg)
              end
            end.join(', ')
            add_line("<% end, #{remaining_args_str} %>", :process_method)
          else
            add_line("<% end %>", :process_method)
          end
          return
        end
        
        # Count how many hash arguments we have
        hash_count = args.count { |arg| arg.type == :hash }
        arguments = args.map.with_index do |arg, index|
          if arg.type == :hash
            # Check if hash contains nested hashes (complex structure)
            has_nested_hash = arg.children.any? do |pair|
              pair.children[1] && pair.children[1].type == :hash
            end
            
            # Check if hash has string values with quotes (complex strings that need braces)
            has_quoted_strings = arg.children.any? do |pair|
              value = pair.children[1]
              value && value.type == :str && (value.children[0].include?("'") || value.children[0].include?('"'))
            end
            
            # Check if hash has only simple values (variables or simple strings without quotes)
            has_only_simple_values = arg.children.all? do |pair|
              value = pair.children[1]
              if !value
                true
              elsif value.type == :str
                # Simple string (no quotes in content)
                !value.children[0].include?("'") && !value.children[0].include?('"')
              else
                # Variable or other non-string value
                true
              end
            end
            
            # Check if there are non-hash arguments before this hash
            has_non_hash_before = args[0...index].any? { |a| a.type != :hash }
            
            # Special case: select_tag expects no braces even with non-hash args before
            is_select_tag = method_name == :select_tag
            
            # For hash arguments, don't wrap in curly braces if:
            # 1. It's the last argument
            # 2. It's the only hash argument
            # 3. It doesn't contain nested hashes
            # 4. It doesn't have quoted strings (which need braces for clarity)
            # 5. It has only simple values AND (there are no non-hash args before OR it's select_tag)
            # Otherwise, keep the braces for clarity
            is_last = (index == args.length - 1)
            # Keep braces if there are non-hash args before, unless it's select_tag
            should_wrap = hash_count > 1 || !is_last || has_nested_hash || has_quoted_strings || (is_last && has_non_hash_before && (!has_only_simple_values || !is_select_tag))
            extract_content_for_hash(arg, should_wrap)
          elsif [:str, :dstr].include?(arg.type)
            "\"#{extract_content(arg)}\""
          else
            extract_content(arg)
          end
        end.join(', ')

        # Build the method call with receiver if present
        receiver_str = receiver ? extract_content(receiver) : ''
        method_name_str = method_name.to_s

        # Build the method call
        # Don't use parentheses for hash arguments - match existing ERB style
        # Existing ERB files show: ajax_form :url => {...}, :confirm_leave => :save do
        if arguments.empty?
          result = if receiver_str.empty?
                     default_instance_variable_name(method_name_str)
                   else
                     "#{receiver_str}.#{method_name_str}"
                   end
        else
          method_call_str = receiver_str.empty? ? method_name_str : "#{receiver_str}.#{method_name_str}"
          # No parentheses - Ruby style, matches existing ERB files
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

          attrs_result = extract_attributes(args)
          attributes = attrs_result[:regular]
          conditional_style = attrs_result[:conditional_style]
          attributes = append_classes(attributes, classes)
          attributes = append_ids(attributes, ids)

          content = args.reject { |arg| arg.type == :hash }.map do |arg|
            case arg.type
            when :lvar, :send, :ivar, :cvar, :gvar
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

          # Handle conditional style attribute
          if conditional_style
            # Output opening tag with conditional style
            tag_start = "<#{html_tag}#{attributes}"
            add_line("#{tag_start}<% if #{conditional_style[:condition]} %> style=\"#{conditional_style[:style_content]}\"<% end %>>", :process_send)
            if content.empty?
              # self closing tags are like br, input
              if self_closing_tag?(html_tag)
                # Already output above
              else
                add_line("</#{html_tag}>", :process_send)
              end
            else
              add_line("#{content}</#{html_tag}>", :process_send)
            end
          elsif content.empty?
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
          attrs_result = extract_attributes(node.children.drop(2))
          attributes = attrs_result[:regular]
          add_line("<#{html_tag}#{attributes}/>", :process_send)

        elsif method_name == :end_form
          add_line("</form>", :process_send)

        elsif method_name == :<<
          # Handle << operator (shovel operator) as a statement, not output
          receiver_str = receiver ? extract_content(receiver) : ''
          arg_str = args.map do |arg|
            # Quote string literals
            if arg.type == :str
              "'#{extract_content(arg)}'"
            else
              extract_content(arg)
            end
          end.join(', ')
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
          add_line("<%= #{default_instance_variable_name(method_name.to_s)} %>", :process_send)
        end
      end

      def process_content_for(method_call, body)
        content_key = extract_content(method_call.children[2])
        # Ensure content_key has parentheses if it's a symbol (no space before paren)
        content_key_str = if content_key.start_with?(':')
                           "(#{content_key})"
                         else
                           content_key
                         end

        # Special handling for arrays - use raw and join
        if body && body.type == :array
          # Extract array elements directly from AST to preserve structure
          array_elements = body.children.map { |element| extract_content(element) }
          add_line("<% content_for#{content_key_str} do %>", :process_content_for)
          # Format array with proper indentation
          if array_elements.length > 1
            formatted_array = "[\n    " + array_elements.join(",\n    ") + "\n  ]"
          else
            formatted_array = "[#{array_elements.join(', ')}]"
          end
          add_line("  <%= raw #{formatted_array}.join %>", :process_content_for)
          add_line("<% end %>", :process_content_for)
        else
          # Always use block form for content_for when it was originally a block
          # This preserves the semantic meaning and ensures proper evaluation
          if body
            # For string literals, use inline form for compactness
            if body.type == :str
              str_content = extract_content(body)
              add_line("<% content_for #{content_key}, #{str_content.inspect} %>", :process_content_for)
            # For simple method calls (like t(...)), use inline form for compactness
            elsif body.type == :send && is_simple_method_call?(body)
              method_content = extract_content(body)
              add_line("<% content_for #{content_key}, #{method_content} %>", :process_content_for)
            else
              # For other content, use block form
              add_line("<% content_for #{content_key} do %>", :process_content_for)
              indent do
                process_node(body)
              end
              add_line("<% end %>", :process_content_for)
            end
          else
            add_line("<% content_for #{content_key} do %>", :process_content_for)
            add_line("<% end %>", :process_content_for)
          end
        end
      end

      def is_simple_method_call?(node)
        return false unless node.type == :send
        receiver, method_name, *args = node.children
        # Simple if: no receiver, single method call, and argument is a simple string or symbol
        return false if receiver # Has a receiver (like obj.method)
        return false if args.length != 1 # Must have exactly one argument
        return false if args.empty? # No arguments (might be a variable)
        
        # Only allow simple string or symbol arguments (like t('.key') or t(:key))
        # Don't allow hashes or complex arguments - those should use block form
        arg = args.first
        return true if [:str, :sym].include?(arg.type)
        return false
      end

      def process_capture(method_call, body)
        # capture used as standalone statement (e.g., content = capture { ... })
        add_line("capture do", :process_capture)
        indent do
          process_node(body) if body
        end
        add_line("end", :process_capture)
      end

      def process_block(node)
        method_call, args, body = node.children
        method_name = method_call.children[1]

        html_tag, classes, ids = extract_html_tag_and_attributes(node.children[0])

        if html_tag
          attrs_result = extract_attributes(method_call.children.drop(2))
          attributes = attrs_result[:regular]
          conditional_style = attrs_result[:conditional_style]

          attributes = append_classes(attributes, classes)
          attributes = append_ids(attributes, ids)

          # Handle conditional style attribute
          if conditional_style
            tag_start = "<#{html_tag}#{attributes}"
            add_line("#{tag_start}<% if #{conditional_style[:condition]} %> style=\"#{conditional_style[:style_content]}\"<% end %>>", :process_block)
          else
            add_line("<#{html_tag}#{attributes}>", :process_block)
          end

          # Check if body is string concatenation - split across lines
          if body && body.type == :send && body.children[1] == :+
            # Handle string concatenation in block bodies
            process_string_concatenation_in_block(body, html_tag)
          else
            indent do
              process_node(body) if body
            end
          end
          add_line("</#{html_tag}>", :process_block)

        elsif method_name == :content_for

          process_content_for(method_call, body)

        elsif method_name == :capture

          process_capture(method_call, body)

        elsif iteration_method?(method_name)
          # Handle iteration blocks, e.g., items.each do |item|
          receiver_node = method_call.children[0]
          # If receiver is a hash/array access (send node with []), use extract_content_for_send
          if receiver_node && receiver_node.type == :send && receiver_node.children[1] == :[]
            receiver_chain = extract_content_for_send(receiver_node)
          else
            receiver_chain = extract_receiver_chain(receiver_node)
          end
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
          attrs_result = extract_attributes(method_call.children.drop(2))
          attributes = attrs_result[:regular]
          add_line("<#{html_tag}#{attributes}>", :process_block)
          indent do
            process_node(node.children[2]) if node.children[2]
          end
          add_line("</#{html_tag}>", :process_block)

        else
          # For helper methods or other method calls with blocks, use <% not <%=
          # The block itself doesn't output - the content inside does
          # Extract method call without parentheses to match existing ERB style
          receiver, method_name_node, *args = method_call.children
          receiver_str = receiver ? extract_content(receiver) : ''
          method_name_str = method_name_node.to_s
          
          # Extract arguments without parentheses (match existing ERB style)
          arguments_str = args.map do |arg|
            if arg.type == :hash
              # Don't wrap hash arguments in braces when in blocks
              extract_content_for_hash(arg, false)
            else
              extract_content(arg)
            end
          end.join(', ')
          
          method_call_str = if receiver_str.empty?
                            method_name_str
                          else
                            "#{receiver_str}.#{method_name_str}"
                          end
          
          if arguments_str.empty?
            erb_code = "<% #{method_call_str} do %>"
          else
            # No parentheses - matches existing ERB files like: ajax_form :url => {...}, :confirm_leave => :save do
            erb_code = "<% #{method_call_str} #{arguments_str} do %>"
          end
          
          add_line(erb_code, :process_block)

          indent do
            process_node(body) if body
          end
          add_line('<% end %>', :process_block)
        end
      end

      def process_string_concatenation_in_block(node, html_tag)
        # node is a :send with :+ method (string concatenation)
        # Split the concatenation across lines: string parts as text, method calls as ERB
        parts = []
        
        def extract_concatenation_parts(node, parts)
          return unless node && node.type == :send && node.children[1] == :+
          
          receiver = node.children[0]
          arg = node.children[2]
          
          # Process receiver (might be nested concatenation)
          if receiver.type == :send && receiver.children[1] == :+
            extract_concatenation_parts(receiver, parts)
          elsif receiver.type == :str
            parts << { type: :string, content: receiver.children[0] }
          elsif receiver.type == :send
            parts << { type: :method, node: receiver }
          end
          
          # Process argument
          if arg.type == :str
            parts << { type: :string, content: arg.children[0] }
          elsif arg.type == :send
            parts << { type: :method, node: arg }
          end
        end
        
        extract_concatenation_parts(node, parts)
        
        # Output parts with proper formatting (indented)
        indent do
          parts.each do |part|
            if part[:type] == :string
              # Output string as text (trimmed)
              content = part[:content].strip
              if !content.empty?
                add_line(content, :process_string_concatenation_in_block)
              end
            elsif part[:type] == :method
              # Output method call as ERB tag
              # Use process_method to get proper formatting, but extract the ERB code
              # and add it as a line (not using add_line from process_method)
              receiver, method_name, *args = part[:node].children
              arguments = args.map.with_index do |arg, index|
                if arg.type == :hash
                  # For hash arguments in string concatenation context, don't wrap in braces
                  hash_count = args.count { |a| a.type == :hash }
                  is_last = (index == args.length - 1)
                  has_nested_hash = arg.children.any? { |pair| pair.children[1] && pair.children[1].type == :hash }
                  should_wrap = hash_count > 1 || !is_last || has_nested_hash
                  extract_content_for_hash(arg, should_wrap)
                elsif arg.type == :str
                  # Use single quotes for string arguments in this context
                  "'#{extract_content(arg)}'"
                elsif arg.type == :dstr
                  "\"#{extract_dstr(arg)}\""
                else
                  extract_content(arg)
                end
              end.join(', ')
              receiver_str = receiver ? extract_content(receiver) : ''
              method_call_str = receiver_str.empty? ? method_name.to_s : "#{receiver_str}.#{method_name}"
              result = arguments.empty? ? method_call_str : "#{method_call_str}(#{arguments})"
              add_line("<%= #{result} %>", :process_string_concatenation_in_block)
            end
          end
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
