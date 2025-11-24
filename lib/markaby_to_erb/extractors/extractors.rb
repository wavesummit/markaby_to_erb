 module MarkabyToErb
   module Extractors
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
       elsif node.type == :begin
         extract_receiver_chain(node.children[0])
       elsif node.type == :erange
         rstart = node.children[0].children[0]
         rend = node.children[1].children[0]
         "(#{rstart}...#{rend})"
       elsif node.type == :const
         # Handle constants like LINKABLE_ACCOUNT_TYPES
         parent = node.children[0]
         constant_name = node.children[1].to_s
         if parent && parent.type == :const
           # Namespaced constant like Date::ABBR_MONTHNAMES
           parent_str = extract_receiver_chain(parent)
           "#{parent_str}::#{constant_name}"
         elsif parent && parent.type == :send
           # Constant access on a method call result (e.g., account[:class_name]::SERVICE_NAME)
           parent_str = extract_receiver_chain(parent)
           "#{parent_str}::#{constant_name}"
         else
           constant_name
         end
       elsif node.type == :ivar || node.type == :cvar || node.type == :gvar
         # Handle instance/class/global variables
         node.children[0].to_s
       elsif node.type == :send
         # Recursively extract the method chain
         receiver = extract_receiver_chain(node.children[0])
         method_name = node.children[1].to_s
         arguments = node.children[2..-1] || []
         
         # Handle hash/array access (method_name == :[])
         if method_name == :[] && !arguments.empty?
           receiver_str = receiver.empty? ? '' : extract_receiver_chain(node.children[0])
           key_str = arguments.map do |arg|
             if arg.type == :str
               "'#{extract_content(arg)}'"
             elsif arg.type == :send && arg.children[1] == :[]
               # Handle nested hash access like account[:class_name]
               extract_content_for_send(arg)
             else
               extract_content(arg)
             end
           end.join(", ")
           return "#{receiver_str}[#{key_str}]"
         end
         
         # If this is a method call on a hash access result, use extract_content_for_send
         # to properly handle the hash access
         if node.children[0] && node.children[0].is_a?(Parser::AST::Node) && 
            node.children[0].type == :send && node.children[0].children[1] == :[]
           return extract_content_for_send(node)
         end
         
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
      when :nil
        'nil'
      when :str
        node.children[0].to_s
       when :int
         node.children[0].to_i.to_s
       when :float
         node.children[0].to_f.to_s
      when :const
        # Handle namespaced constants like Date::ABBR_MONTHNAMES
        # Structure: s(:const, parent_const, constant_name)
        parent = node.children[0]
        constant_name = node.children[1].to_s
        if parent && parent.type == :const
          # Recursively extract the parent namespace
          parent_str = extract_content(parent)
          "#{parent_str}::#{constant_name}"
        elsif parent && parent.type == :send
          # Constant access on a method call result (e.g., account[:class_name]::SERVICE_NAME)
          parent_str = extract_content_for_send(parent)
          "#{parent_str}::#{constant_name}"
        else
          constant_name
        end
       when :sym
         ":#{node.children[0]}"
       when :lvasgn
         node.children[0].to_s
       when :lvar, :cvar, :ivar, :gvar
         node.children[0].to_s
      when :begin
        # assuming only one child
        extract_content(node.children[0])
      when :irange, :erange
        # Handle ranges like 1..15 or 1...15
        start_node = node.children[0]
        end_node = node.children[1]
        start_str = extract_content(start_node)
        end_str = extract_content(end_node)
        range_op = node.type == :erange ? '...' : '..'
        "(#{start_str}#{range_op}#{end_str})"
      when :hash
        extract_content_for_hash(node)
      when :array
        # Properly format array elements
        extract_content_for_array(node)
      when :send
        extract_content_for_send(node)
      when :block
        extract_content_for_block(node)
      when :dstr
        extract_content_for_dstr(node)
      when :regexp
        # Handle regex literals like /pattern/ or /pattern/options
        pattern_node = node.children[0]
        options_node = node.children[1]
        pattern = pattern_node.children[0].to_s
        options = options_node ? options_node.children[0].to_s : ''
        # Escape forward slashes in pattern for output
        escaped_pattern = pattern.gsub('/', '\\/')
        options_str = options.empty? ? '' : options
        "/#{escaped_pattern}/#{options_str}"
      when :if
        # Handle `if` statements (including ternary operators)
        condition, if_body, else_body = node.children
        # Unwrap :begin nodes in condition
        condition_str = if condition && condition.type == :begin
                         extract_content(condition.children[0])
                       else
                         extract_content(condition)
                       end
        
        # If else_body is nil, this is a modifier if statement, not a ternary
        # Don't output as ternary - return the statement with modifier
        if else_body.nil? && if_body
          statement_str = extract_content(if_body)
          "#{statement_str} if #{condition_str}"
        elsif if_body && else_body
          # This is a ternary operator (both branches exist)
          # Preserve quotes on string literals in ternary operators
          true_str = if if_body.type == :str
                      "'#{extract_content(if_body)}'"
                    else
                      extract_content(if_body)
                    end
          false_str = if else_body.nil? || else_body.type == :nil
                       'nil'
                     elsif else_body.type == :str
                       "'#{extract_content(else_body)}'"
                     elsif else_body.type == :dstr
                       # For dynamic strings in ternary false branch, wrap in double quotes
                       dstr_content = extract_content_for_dstr(else_body)
                       "\"#{dstr_content}\""
                     else
                       extract_content(else_body)
                     end
          # Output ternary operator - check if we're in a JavaScript string context
          # For JavaScript strings (detected by checking if parent is a dstr in a hash), preserve space
          # Otherwise, add space after colon for readability (Ruby style)
          # Heuristic: if the false_str is an empty string in quotes AND true_str is NOT a string literal, preserve space
          # This handles: @collection ? @collection.permalink : "" (in JS strings - true_str is a variable/property)
          # But not: 'width:286px' : '' (regular ternary - true_str is a string literal, no space)
          is_js_string_context = (false_str == '""' || false_str == "''") && 
                                 !true_str.start_with?("'") && !true_str.start_with?('"')
          space_after_colon = is_js_string_context ? " : " : " : "
          "#{condition_str} ? #{true_str}#{space_after_colon}#{false_str}"
        else
          # Fallback - shouldn't happen in normal cases
          extract_content(if_body || else_body)
        end
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
         "&&"  # Convert 'and' to '&&' for consistency with Ruby style
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

     def extract_content_for_hash(node, with_brackets = true)
       result = node.children.map do |pair|
         key, value = pair.children

         # Determine the key's format
         key_str = key.type == :str ? "'#{extract_content(key)}'" : extract_content(key)

         # Handle nil values
         if value.nil? || value.type == :nil
           hash_val = 'nil'
         # Determine if the value contains single quotes and adjust accordingly
         elsif value.type == :str
           content = extract_content(value)
           # Use double quotes if content contains single quotes
           hash_val = content.include?("'") ? "\"#{content}\"" : "'#{content}'"
         elsif value.type == :dstr
           # For dynamic strings (string interpolation), check if it's a JavaScript string
           # JavaScript strings contain $, jQuery syntax, or JavaScript function calls
           dstr_content = extract_content_for_dstr(value)
           # Check if this looks like a JavaScript string (contains $, jQuery, or JS syntax)
           is_javascript_string = dstr_content.include?('$(') || dstr_content.include?('$j.') || 
                                  dstr_content.include?('innerHTML') || dstr_content.include?('function(')
           
           if is_javascript_string
             # For JavaScript strings, don't wrap in quotes and keep #{...} as-is
             # The interpolation should remain as #{...} not converted to ERB
             hash_val = dstr_content
           else
             # For regular dynamic strings, wrap in double quotes
             hash_val = "\"#{dstr_content}\""
           end
         else
           hash_val = extract_content(value)
         end

         "#{key_str} => #{hash_val}"
       end.join(', ')
       with_brackets ? "{#{result}}" : result
     end

     def extract_content_for_array(node)
       array_content = node.children.map do |element|
         case element.type
         when :hash
           extract_content_for_hash(element)
         when :str
           "\"#{extract_content(element)}\""
         when :dstr
           # For dstr in array context, extract without outer quotes and without escaping #
           string_parts = element.children.map do |child|
             case child.type
             when :str
               child.children[0]
             when :begin, :evstr
               "\#{#{extract_content(child.children.first)}}"
             else
               ''
             end
           end
           "\"#{string_parts.join}\""
         when :send
           # Use extract_content_for_send to handle t() calls with dstr properly
           extract_content_for_send(element)
         else
           extract_content(element)
         end
       end.join(', ')

       "[#{array_content}]"
     end

     def extract_content_for_block(node)
       # Extract block expression like method { |args| body }
       # Note: This is used when blocks are part of expressions, not when processing block bodies
       method_call, args, body = node.children
       receiver, method_name, *method_args = method_call.children
       
       receiver_str = receiver ? extract_content(receiver) : ''
       block_args = if args && args.type == :args
                      args.children.map { |arg| arg.children[0].to_s }.join(', ')
                    else
                      ''
                    end
       block_body = body ? extract_content(body) : ''
       
       # Format block args - some tests expect {|p| (no space), others expect { |n| (with space)
       # Use { |args| format (with space) for consistency
       block_args_formatted = block_args.empty? ? '' : " |#{block_args}|"
       if receiver_str.empty?
         method_args_str = method_args.map { |a| extract_content(a) }.join(', ')
         "#{method_name}(#{method_args_str}) {#{block_args_formatted} #{block_body} }"
       else
         "#{receiver_str}.#{method_name} {#{block_args_formatted} #{block_body} }"
       end
     end

     def extract_content_for_send(node)
      receiver, method_name, *arguments = node.children
      method_name_str = method_name.to_s

       # Special handling for << operator (shovel operator)
       if method_name == :<< && receiver
         receiver_str = extract_content(receiver)
         arg_str = arguments.map do |arg|
           if arg.type == :str
             "'#{extract_content(arg)}'"
           else
             extract_content(arg)
           end
         end.join(', ')
         return "#{receiver_str} << #{arg_str}"
       end

       # Special handling for ! operator (negation)
       if method_name == :! && receiver
         receiver_str = extract_content(receiver)
         return "!#{receiver_str}"
       end

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
        arguments_str = arguments.map do |arg|
          # If argument is a string literal, quote it
          if arg.type == :str
            "'#{extract_content(arg)}'"
          elsif arg.type == :send && arg.children[1] == :[]
            # Handle nested hash access like account[:class_name]
            extract_content_for_send(arg)
          else
            extract_content(arg)
          end
        end.join(", ")
        return "#{receiver_str}[#{arguments_str}]"
      end

      if method_name == :t
        # Special case for translation calls
        # Use double quotes if argument contains interpolation (dstr)
        arg = arguments[0]
        if arg && arg.type == :dstr
          # For dynamic strings with interpolation, use double quotes
          # Extract dstr preserving #{...} syntax (don't convert to ERB)
          dstr_content = extract_content_for_dstr(arg)
          return "t(\"#{dstr_content}\")"
        else
          return "t('#{extract_content(arg)}')"
        end
      end

      # Special handling for + operator (string concatenation and array addition)
      if method_name == :+
        # Handle string concatenation
        # Check if either side is a string (receiver or argument)
        # Also handle nested + operations where the receiver might be another + operation
        receiver_is_str = receiver && (receiver.type == :str || receiver.type == :dstr)
        receiver_is_plus = receiver && receiver.type == :send && receiver.children[1] == :+
        arg_is_str = arguments[0] && (arguments[0].type == :str || arguments[0].type == :dstr)
        
        if receiver_is_str || arg_is_str || receiver_is_plus
          receiver_str = if receiver.type == :str
                          "'#{extract_content(receiver)}'"
                        elsif receiver.type == :dstr
                          extract_dstr(receiver)
                        elsif receiver_is_plus
                          # Recursively extract nested + operations
                          extract_content(receiver)
                        else
                          extract_content(receiver)
                        end
          arg_str = if arguments[0].type == :str
                      "'#{extract_content(arguments[0]).gsub("\n", '\\n')}'"
                    elsif arguments[0].type == :dstr
                      "\"#{extract_content(arguments[0]).gsub("\n", '\\n')}\""
                    else
                      extract_content(arguments[0])
                    end
          return "#{receiver_str} + #{arg_str}"
        # Handle array addition (e.g., ["Visa"]+["MasterCard"])
        elsif receiver && (receiver.type == :array || arguments[0]&.type == :array)
          receiver_str = extract_content(receiver)
          arg_str = extract_content(arguments[0])
          return "#{receiver_str}+#{arg_str}"
        end
      end

      # Special handling for % operator (string formatting)
      if method_name == :% && receiver && (receiver.type == :str || receiver.type == :dstr)
        receiver_str = if receiver.type == :str
                         "\"#{extract_content(receiver)}\""
                       else
                         extract_dstr(receiver)
                       end
        arg_str = arguments.map { |arg| extract_content(arg) }.join(', ')
        return "#{receiver_str} % #{arg_str}"
      end

      # handle math operations
      if %i[+ * \ % -].include?(method_name) && receiver && receiver.type == :send
        receiver_str = receiver ? extract_content(receiver) : ''
        arg_str = arguments.map do |arg|
          arg.type == :str ? "'#{extract_content(arg)}'" : extract_content(arg)
        end.join
        return "#{receiver_str} #{method_name} #{arg_str}"
      end

      # Normal method call processing
      # Special handling for method calls on dstr (like "string".html_safe)
      if receiver && receiver.type == :dstr
        dstr_content = extract_dstr(receiver)
        receiver_str = dstr_content
      else
        receiver_str = receiver ? extract_content(receiver) : ''
      end
      
      arguments_str = arguments.map do |arg|
        if arg.type == :block_pass
          # Handle &:method syntax (symbol-to-proc)
          symbol_node = arg.children[0]
          if symbol_node.type == :sym
            "&:#{symbol_node.children[0]}"
          else
            "&:#{extract_content(symbol_node)}"
          end
        elsif arg.type == :str
          # Quote string arguments - use single quotes for simple strings (matches Ruby style)
          # But use double quotes if the string contains a space (for consistency with some tests)
          # Also use double quotes for image_tag arguments to match test expectations
          str_content = extract_content(arg)
          # Use double quotes if string contains space or if this is an image_tag argument, single quotes otherwise
          # Check if parent method is image_tag by checking the call stack (simplified: always use double quotes for now)
          if str_content.include?(' ')
            "\"#{str_content}\""
          elsif method_name == :image_tag
            # Use double quotes for image_tag arguments
            "\"#{str_content}\""
          else
            "'#{str_content}'"
          end
        elsif arg.type == :dstr
          # For dynamic strings, preserve interpolation syntax
          dstr_content = extract_content_for_dstr(arg)
          "\"#{dstr_content}\""
        else
          extract_content(arg)
        end
      end.join(', ')

      # Build the final method call string
      # For helper methods like image_tag, don't use parentheses for single string argument
      if receiver_str.empty?
        if arguments_str.empty?
          default_instance_variable_name(method_name_str)
        elsif method_name == :image_tag && arguments.length == 1 && arguments[0].type == :str
          # image_tag with single string argument - no parentheses
          # Use double quotes for image_tag arguments to match test expectations
          str_arg = arguments[0]
          str_content = str_arg.children[0]  # Get the string content directly
          quoted_arg = "\"#{str_content}\""
          "#{method_name_str} #{quoted_arg}"
        else
          "#{method_name_str}(#{arguments_str})"
        end
      else
        receiver_str + '.' + method_name_str + (arguments_str.empty? ? '' : "(#{arguments_str})")
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
       return { regular: '', conditional_style: nil } if args.empty?

       regular_attrs = []
       conditional_style = nil

       args.select { |arg| arg.type == :hash }.flat_map do |hash_arg|
         hash_arg.children.map do |pair|
           key, value = pair.children
           key_str = key.children[0].to_s.gsub(':', '')

          # Check for conditional style attribute (modifier if)
          # Handle both direct :if and :if wrapped in :begin (due to parentheses)
          style_if_node = if value.type == :if
                           value
                         elsif value.type == :begin && value.children[0] && value.children[0].type == :if
                           value.children[0]
                         else
                           nil
                         end
          
          if key_str == 'style' && style_if_node && style_if_node.children[2].nil?
            # This is a modifier if: "value if condition" (possibly wrapped in parentheses)
            condition = style_if_node.children[0]
            style_value = style_if_node.children[1]
            
            # Extract condition and style value
            condition_str = extract_content(condition)
            
            # Extract style value (should be a dstr with interpolation)
            if style_value.type == :dstr
              # Build style content by converting #{...} to <%= ... %>
              style_parts = []
              style_value.children.each do |child|
                case child.type
                when :str
                  style_parts << child.children[0]
                when :begin, :evstr
                  interpolation_code = extract_content(child.children.first)
                  style_parts << "<%= #{interpolation_code} %>"
                end
              end
              style_content = style_parts.join
              conditional_style = { condition: condition_str, style_content: style_content }
            end
            next # Skip adding to regular attributes
          end

          if value.type == :dstr
            # For dynamic strings, extract properly and use ERB interpolation
            # Extract the dstr content without quotes, then wrap in ERB
            dstr_parts = value.children.map do |child|
              case child.type
              when :str
                child.children[0]
              when :begin, :evstr
                "\#{#{extract_content(child.children.first)}}"
              else
                ''
              end
            end
            dstr_content = dstr_parts.join
            value_str = "<%= \"#{dstr_content}\" %>"
          elsif value.type == :if || (value.type == :begin && value.children[0] && value.children[0].type == :if)
            # Handle ternary operators in attributes
            # May be wrapped in :begin due to parentheses
            if_node = value.type == :if ? value : value.children[0]
            condition, if_body, else_body = if_node.children
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
                      elsif else_body && else_body.type == :dstr
                        # Handle dstr in false branch (e.g., "#{var}_dialog")
                        dstr_parts = else_body.children.map do |child|
                          case child.type
                          when :str
                            child.children[0]
                          when :begin, :evstr
                            "\#{#{extract_content(child.children.first)}}"
                          else
                            ''
                          end
                        end
                        "\"#{dstr_parts.join}\""
                      else
                        extract_content(else_body)
                      end
            value_str = "<%= #{condition_str} ? #{true_str} : #{false_str} %>"
          elsif value.type == :send || value.type == :lvar || value.type == :ivar || value.type == :cvar || value.type == :gvar
            # For method calls and variables, wrap in ERB tags
            value_str = "<%= #{extract_content(value)} %>"
          else
            value_str = extract_content(value)
          end
          regular_attrs << "#{key_str}=\"#{value_str}\""
         end
       end

       regular_attrs_str = regular_attrs.empty? ? '' : " #{regular_attrs.join(' ')}"
       { regular: regular_attrs_str, conditional_style: conditional_style }
     end


   end
 end
