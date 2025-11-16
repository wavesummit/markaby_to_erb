#!/usr/bin/env ruby

require 'json'
require 'parser/current'
require 'logger'

# Add lib to load path
lib_path = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib_path)

# Require all necessary files
require File.join(lib_path, 'markaby_to_erb', 'exceptions')
require File.join(lib_path, 'markaby_to_erb', 'extractors', 'extractors')
require File.join(lib_path, 'markaby_to_erb', 'processors', 'processors')
require File.join(lib_path, 'markaby_to_erb', 'helpers', 'helpers')
require File.join(lib_path, 'markaby_to_erb', 'converter')

# Path to test directory - set via TEST_PROJECT_PATH environment variable
test_project_path = ENV['TEST_PROJECT_PATH']
if test_project_path.nil? || test_project_path.empty?
  puts "Error: TEST_PROJECT_PATH environment variable must be set"
  puts "Usage: TEST_PROJECT_PATH=/path/to/project ruby test_all_mab_files.rb"
  exit 1
end
errors = []
success_count = 0
total_count = 0

Dir.glob(File.join(test_project_path, '**/*.mab')).each do |mab_file|
  total_count += 1
  relative_path = mab_file.sub(test_project_path + '/', '')
  
  begin
    markaby_code = File.read(mab_file)
    converter = MarkabyToErb::Converter.new(markaby_code, validate_output: false)
    erb_code = converter.convert
    
    success_count += 1
    print '.' if total_count % 10 == 0
    $stdout.flush
  rescue => e
    errors << {
      file: relative_path,
      error: e.class.name,
      message: e.message,
      full_path: mab_file
    }
    print 'E'
    $stdout.flush
  end
end

puts "\n\n=== Test Results ==="
puts "Total files: #{total_count}"
puts "Successful: #{success_count}"
puts "Failed: #{errors.length}"

if errors.any?
  puts "\n=== Files with Errors ==="
  errors.each do |error|
    puts "\nFile: #{error[:file]}"
    puts "Error: #{error[:error]}"
    puts "Message: #{error[:message]}"
  end
  
  # Write errors to file
  File.write('/tmp/mab_errors.json', JSON.pretty_generate(errors))
  puts "\n\nErrors written to /tmp/mab_errors.json"
end

