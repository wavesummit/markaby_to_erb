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
      #pp parser
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
      when :if, :unless
       process_if(node, node.type)
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

    def process_if(node, type)
      condition_node, if_body, else_body = node.children

      add_line("<% #{type} #{extract_content(condition_node)} %>", :process_if)
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

    def process_assignment(node)

      var_name = node.children[0]
      value_node = node.children[1]
      value = extract_content(value_node)

      # Ensure strings are properly quoted
      value = "\"#{value}\"" if value_node.type == :str

      erb_assignment = "<% #{var_name} = #{value} %>"
      add_line(erb_assignment, :process_assignment)
    end

    def process_send(node)
      receiver, method_name, *args = node.children

      if helper_method?(method_name)
        arguments = args.map { |arg| extract_content(arg).inspect }.join(', ')
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
        content = args.map { |arg| extract_content(arg) }.join
        add_line(content, :process_send)
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
      when :sym
        ":#{node.children[0]}"
      when :lvar
        node.children[0].to_s
      when :array
        # Properly format array elements
        "[" + node.children.map { |element| "\"#{extract_content(element)}\"" }.join(", ") + "]"
      when :send
        receiver, method_name, *arguments = node.children
        receiver_str = receiver ? "#{extract_content(receiver)}." : ""
        arguments_str = arguments.map { |arg| extract_content(arg) }.join(", ")
        arguments_str = " #{arguments_str}" unless arguments_str.empty?
        "#{receiver_str}#{method_name}#{arguments_str}"
      else
        ""
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
      %w[html head title body h1 h2 h3 h4 h5 h6 ul li a div span p table tr td th form input label select option textarea button meta br hr img link].include?(method_name.to_s)
    end

    def iteration_method?(method_name)
      %w[each map times each_with_index inject].include?(method_name.to_s)
    end

    def self_closing_tag?(method_name)
      %w[meta input br hr img link].include?(method_name.to_s)
    end

    def helper_method?(method_name)
      %w[link_to link_to_remote image_tag form_for form_with label].include?(method_name.to_s)
    end

    def add_line(line, from_method)
      @buffer << (INDENT * @indent_level) + line
      #puts "Adding line: #{line} from #{from_method}" # For debugging purposes
    end

    def indent
      @indent_level += 1
      yield
      @indent_level -= 1
    end
  end
end
