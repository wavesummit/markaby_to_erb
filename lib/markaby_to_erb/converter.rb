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
        puts "Failed to parse the Markaby code. Please check the syntax."
        exit
      end

      process_node(parser)
      @buffer.join("\n").encode('UTF-8')
    end

    private

    INDENT = '  '

    def process_node(node)
      return if node.nil?

      case node.type
      when :send
        process_send(node)
      when :lvasgn
        process_assignment(node)
      when :block
        process_block(node)
      when :if
       process_if(node)
      when :begin
        process_begin(node)
      else
        puts "Unhandled node type: #{node.type}"
      end
    end

    def process_begin(node)
      node.children.each do |child|
        process_node(child)
      end
    end

    def process_dstr(node)
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
          add_line("<% else %>", :process_if)
          indent do
            process_node(current_node)
          end
        end

        add_line("<% end %>", :process_if)
      elsif if_body.nil? && else_body
        # Convert to unless when we have nil if_body and non-nil else_body
        add_line("<% unless #{extract_content(condition_node)} %>", :process_if)
        indent do
          process_node(else_body)
        end
        add_line("<% end %>", :process_if)
      else
        # Handle regular if-else statements
        add_line("<% if #{extract_content(condition_node)} %>", :process_if)
        indent do
          process_node(if_body) if if_body
        end
        if else_body
          add_line("<% else %>", :process_if)
          indent do
            process_node(else_body)
          end
        end
        add_line("<% end %>", :process_if)
      end
    end

    def process_assignment(node)
      var_name, value_node = node.children
      value = extract_content(value_node)

      # Ensure strings are properly quoted
      value = "\"#{value}\"" if value_node.type == :str

      erb_assignment = "<% #{var_name} = #{value} %>"
      add_line(erb_assignment, :process_assignment)
    end

    def process_send(node)
      receiver, method_name, *args = node.children

      if helper_method?(method_name)
        arguments = args.map do |arg|
           arg.type == :str ? "\"#{extract_content(arg)}\"" : extract_content(arg)
        end.join(', ')
        erb_code = "<%= #{method_name} #{arguments} %>"
        add_line(erb_code, :process_send)

      elsif html_tag?(method_name)
        attributes = extract_attributes(args)
        content = args.reject { |arg| arg.type == :hash }.map { |arg|
          case arg.type
          when :lvar, :send
            "<%= #{extract_content(arg)} %>"
          else
            extract_content(arg)
          end
        }.join

        if content.empty?
          if self_closing_tag?(method_name)
            add_line("<#{method_name}#{attributes}>", :process_send)
          else
            add_line("<#{method_name}#{attributes}/>", :process_send)
          end
        else
          # Add the opening tag and content in the same line if there's no nested block.
          add_line("<#{method_name}#{attributes}>#{content}</#{method_name}>", :process_send)
        end

      elsif method_name == :text && args.any?
        # Directly add the text content without ERB tags
        if args.first.type == :dstr
          # Call process_dstr here to handle dynamic strings
          content = process_dstr(args.first)
          add_line("<%= #{content} %>", :process_send)
        else
          content = args.map { |arg| extract_content(arg) }.join
          add_line(content, :process_send)
        end

      else
        # Handle variable references
        add_line("<%= #{method_name} %>", :process_send)
      end
    end

    def process_content_recursively(args)
      args.each do |arg|
        if arg.is_a?(Parser::AST::Node) && arg.type == :send
          process_send(arg)
        else
          add_line(extract_content(arg), :process_content_recursively)
        end
      end
    end

    def process_block(node)
      method_call, args, body = node.children
      method_name = method_call.children[1]
      attributes = extract_attributes(method_call.children.drop(2))

      if html_tag?(method_name)
        add_line("<#{method_name}#{attributes}>", :process_block)
        indent do
          process_node(body) if body
        end
        add_line("</#{method_name}>", :process_block)
      elsif iteration_method?(method_name)

        # Handle iteration blocks, e.g., items.each do |item|
        receiver = method_call.children[0].children.compact.first
        receiver_args = extract_argument_recursive(args).join(",")

        add_line("<% #{receiver}.#{method_name} do |#{receiver_args}| %>", :process_block)
        indent do
          process_node(node.children[2]) if node.children[2]
        end
        add_line("<% end %>", :process_block)

      else
        process_node(method_call)
        add_line("<% do %>", :process_block)
        indent do
          process_node(body) if body
        end
        add_line("<% end %>", :process_block)
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
        node.children[0].to_i
      when :float
        node.children[0].to_f
      when :sym
        ":#{node.children[0]}"
      when :lvar
        node.children[0].to_s
      when :begin
        #assuming only one child
        extract_content(node.children[0])
      when :hash
        # Handle hashes
        # can't just to_s on a hash as we need variable names as well as strings for values
        "{" + node.children.map do |pair|
          key, value = pair.children
          hash_val = value.type == :str ?  "'#{extract_content(value)}'" :  extract_content(value)
          "#{extract_content(key)} => #{hash_val}"
        end.join(", ") + "}"
      when :array
        # Properly format array elements
        "[" + node.children.map { |element| "\"#{extract_content(element)}\"" }.join(", ") + "]"
      when :send
          extract_content_for_send(node)
      when :dstr
        # Handle dynamic strings
        result = node.children.map { |child| extract_content(child) }.join
      else
        ""
      end
    end

    def extract_content_for_send(node)
      receiver, method_name, *arguments = node.children

      # Special handling for comparison operators
      if [:>, :<, :>=, :<=, :==, :!=].include?(method_name)
        receiver_str = receiver ? extract_content(receiver) : ""
        arg_str = arguments.map { |arg| extract_content(arg) }.join
        return "#{receiver_str} #{method_name} #{arg_str}"
      end

      #deal with params 
      if receiver && receiver.type == :send && receiver.children[1] == :params && method_name == :[]
        # If it's params[:key], we generate the correct syntax
        param_key = arguments[0].type == :str ? ":#{arguments[0].children[0]}" : arguments[0].children[0]
        return "params[#{param_key}]"
      end

      # Normal method call processing
      receiver_str = receiver ? extract_content(receiver) : ""
      arguments_str = arguments.map { |arg| extract_content(arg) }.join(", ")
      receiver_str + (receiver_str.empty? ? '' : '.') + "#{method_name}#{arguments_str.empty? ? '' : "(#{arguments_str})"}"
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
      %w[html head title body h1 h2 h3 h4 h5 h6 ul li a div span p table tr td th form input label select option textarea button meta br hr img link].include?(method_name.to_s)
    end

    def iteration_method?(method_name)
      %w[each map times each_with_index inject].include?(method_name.to_s)
    end

    def self_closing_tag?(method_name)
      %w[meta input br hr img link].include?(method_name.to_s)
    end

    def helper_method?(method_name)
      %w[link_to link_to_remote image_tag form_for form_remote_tag label].include?(method_name.to_s)
    end

    def add_line(line, from_method)
      @buffer << (INDENT * @indent_level) + line
      puts "Adding line: #{line} from #{from_method}" if test?
    end

    def test?
      defined?(RSpec)
    end

    def indent
      @indent_level += 1
      yield
      @indent_level -= 1
    end
  end
end
