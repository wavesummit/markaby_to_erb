# spec/spec_helper.rb
begin
  require 'pry'
  require 'pry-byebug'
  require 'simplecov'
  SimpleCov.start
rescue LoadError
  # Do nothing
end

require 'bundler/setup'
require 'markaby_to_erb'

RSpec.configure do |config|
  config.before(:suite) do
    # Get command line arguments
    args = ARGV.join(' ')
    # Enable debug if running a specific test (either by line number)
    ENV['DEBUG'] = if args.match(/:[\d]+/)
                     '1'
                   else
                     nil
                   end
  end
end

def expect_conversion(markaby_code, expected_erb)
  converter = MarkabyToErb::Converter.new(markaby_code)
  erb_code = converter.convert
  expect(erb_code.strip).to eq(expected_erb.strip)
end
