require 'parser/current'

require_relative 'extractors/extractors'
require_relative 'processors/processors'
require_relative 'helpers/helpers'

module MarkabyToErb
  class Converter

    include MarkabyToErb::Extractors
    include MarkabyToErb::Processors
    include MarkabyToErb::Helpers

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
