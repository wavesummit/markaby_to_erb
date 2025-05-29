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
         "#{extract_content(condition)} ? #{extract_content(if_body)} : #{extract_content(else_body)}"
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

       # handle math operations
       if %i[+ * \ % -].include?(method_name) && receiver && receiver.type == :send
         receiver_str = receiver ? extract_content(receiver) : ''
         arg_str = arguments.map do |arg|
           arg.type == :str ? "'#{extract_content(arg)}'" : extract_content(arg)
         end.join
         return "#{receiver_str} #{method_name} #{arg_str}"
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

           if value.type == :dstr
             value_str = "<%=\"#{extract_content(value)}\"%>"
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
