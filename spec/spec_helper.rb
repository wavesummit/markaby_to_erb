# spec/spec_helper.rb


begin
  require 'pry'
  require 'pry-byebug'
  require 'simplecov'
  SimpleCov.start
rescue LoadError
  # Do nothing if Pry is not available
end

require 'bundler/setup'
require 'markaby_to_erb'

RSpec.configure do |config|
  # Configuration options for RSpec
end
