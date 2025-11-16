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
        # Handle namespaced constants like Date::ABBR_MONTHNAMES
        # Structure: s(:const, parent_const, constant_name)
        parent = node.children[0]
        constant_name = node.children[1].to_s
        if parent && parent.type == :const
          # Recursively extract the parent namespace
          parent_str = extract_content(parent)
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
      when :if
        # Handle `if` statements (including ternary operators)
        condition, if_body, else_body = node.children
        # Unwrap :begin nodes in condition
        condition_str = if condition && condition.type == :begin
                         extract_content(condition.children[0])
                       else
                         extract_content(condition)
                       end
        # Preserve quotes on string literals in ternary operators
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
        "#{condition_str} ? #{true_str}:#{false_str}"
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

     def extract_content_for_hash(node, with_brackets = true)
       result = node.children.map do |pair|
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
         arguments_str = arguments.map { |arg| extract_content(arg) }.join(", ")
         return "#{receiver_str}[#{arguments_str}]"
       end

       if method_name == :t
         # Special case for translation calls
         return "t('#{extract_content(arguments[0])}')"
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
          # Quote string arguments
          "\"#{extract_content(arg)}\""
        else
          extract_content(arg)
        end
      end.join(', ')

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
          elsif value.type == :send || value.type == :lvar || value.type == :ivar || value.type == :cvar || value.type == :gvar
            # For method calls and variables, wrap in ERB tags
            value_str = "<%= #{extract_content(value)} %>"
          else
            value_str = extract_content(value)
          end
          "#{key_str}=\"#{value_str}\""
         end
       end

       attributes.empty? ? '' : " #{attributes.join(' ')}"
     end


   end
 end
