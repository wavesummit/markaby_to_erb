# MarkabyToErb

[![Ruby Version](https://img.shields.io/badge/ruby-%3E%3D%202.5.0-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

A Ruby gem that converts [Markaby](https://github.com/markaby/markaby) code to ERB (Embedded Ruby) templates. Perfect for migrating legacy Rails applications from Markaby to standard ERB templates.

## Overview

MarkabyToErb parses Markaby code using Ruby's AST and converts it to equivalent ERB templates. It handles complex Markaby constructs including HTML tags, Rails helpers, control flow statements, string interpolation, and more.

## Features

- ✅ **Comprehensive Markaby Support**
  - HTML tags with classes and IDs (`div.content!`, `h1.title`)
  - Blocks and nested structures
  - Rails helpers (`link_to`, `form_tag`, `image_tag`, etc.)
  - Control flow (`if`, `unless`, `while`, `until`, `for`, `case`)
  - Exception handling (`begin`, `rescue`, `ensure`)
  - String interpolation and concatenation
  - Ternary operators
  - Iteration methods (`each`, `map`, `times`, etc.)
  - `capture` method for capturing block output

- ✅ **Production Ready**
  - Proper exception handling (`ParseError`, `ConversionError`)
  - 95+ test cases with 90%+ code coverage
  - Real-world examples tested
  - Graceful error messages with context

- ✅ **Flexible Usage**
  - Programmatic API for integration
  - Command-line tool for batch conversion
  - Single file or directory processing

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'markaby_to_erb'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install markaby_to_erb
```

## Requirements

- Ruby >= 2.5.0
- Parser gem (~> 3.0)

## Usage

### Programmatic API

```ruby
require 'markaby_to_erb'

markaby_code = <<~MARKABY
  html do
    head do
      title "My Page"
    end
    body do
      h1 "Hello, World!"
      p "This is a paragraph."
    end
  end
MARKABY

converter = MarkabyToErb::Converter.new(markaby_code)
erb_code = converter.convert

puts erb_code
# Output:
# <html>
#   <head>
#     <title>My Page</title>
#   </head>
#   <body>
#     <h1>Hello, World!</h1>
#     <p>This is a paragraph.</p>
#   </body>
# </html>
```

#### Default to Instance Variables

You can opt-in to treating bare identifiers in tag content as instance variables—handy when older Markaby views assume everything is an `@var`.

**Programmatic API:**
```ruby
converter = MarkabyToErb::Converter.new(
  markaby_code,
  default_to_instance_variables: true
)
```

**Command Line:**
```bash
markaby_to_erb -i file.mab --default-to-instance-variables
```

When enabled, identifiers such as `dialog_heading` become `@dialog_heading`, while helper calls or `_path`/`_url` methods are left untouched.

### Command-Line Interface

#### Convert a single file

```bash
markaby_to_erb -i app/views/layouts/application.mab
```

This creates `app/views/layouts/application.html.erb` in the same directory (default extension is `.html.erb`).

For Rails 2.3 compatibility, use the `-e` option to specify `.erb`:

```bash
markaby_to_erb -i app/views/layouts/application.mab -e .erb
```

#### Convert a directory

```bash
markaby_to_erb -d app/views/partials
```

Converts all `.mab` and `.markaby` files in the directory and subdirectories.

#### Specify output location

```bash
markaby_to_erb -i input.mab -o output.html.erb
markaby_to_erb -d app/views -o converted_views
```

#### Rename original files

```bash
markaby_to_erb -i file.mab -r
```

Renames `file.mab` to `file.mab.old` after conversion.

#### CLI Options

```
Usage: markaby_to_erb [options]

Options:
  -i, --input FILE                 Input Markaby file
  -d, --directory DIR              Input directory containing Markaby files
  -o, --output FILE_OR_DIR         Output ERB file or directory (optional)
  -r, --rename-old                 Rename original Markaby file by appending _old to its name
  -v, --verbose                    Enable verbose logging
      --dry-run                    Preview changes without writing files
      --no-validate                Skip output validation
      --default-to-instance-variables
                                   Convert local variables to instance variables by default
  -e, --extension EXT              Output file extension (e.g., .erb or .html.erb, default: .html.erb)
  -h, --help                       Displays Help
```

#### Additional CLI Examples

**Rails 2.3 compatibility (use .erb extension):**

```bash
markaby_to_erb -i app/views/layouts/application.mab -e .erb
```

This creates `app/views/layouts/application.erb` instead of the default `.html.erb`.

**Enable default to instance variables:**

```bash
markaby_to_erb -i file.mab --default-to-instance-variables
```

This treats bare identifiers in tag content as instance variables (e.g., `dialog_heading` becomes `@dialog_heading`).

**Preview changes without writing files:**

```bash
markaby_to_erb -i file.mab --dry-run
```

**Verbose logging:**

```bash
markaby_to_erb -i file.mab -v
```

**Skip output validation:**

```bash
markaby_to_erb -i file.mab --no-validate
```

## Examples

### Basic HTML Tags

**Markaby:**
```ruby
h1 "Welcome"
div.content do
  p "This is content"
end
```

**ERB Output:**
```erb
<h1>Welcome</h1>
<div class="content">
  <p>This is content</p>
</div>
```

### Classes and IDs

**Markaby:**
```ruby
div.content.sidebar! do
  h2 "Title"
end
```

**ERB Output:**
```erb
<div class="content sidebar" id="sidebar">
  <h2>Title</h2>
</div>
```

### Rails Helpers

**Markaby:**
```ruby
link_to "Home", root_path, class: "nav-link"
form_tag users_path do
  text_field_tag :name
  submit_tag "Save"
end
```

**ERB Output:**
```erb
<%= link_to "Home", root_path, :class => "nav-link" %>
<%= form_tag users_path do %>
  <%= text_field_tag :name %>
  <%= submit_tag "Save" %>
<% end %>
```

### Control Flow

**Markaby:**
```ruby
if user.signed_in?
  p "Welcome, #{user.name}!"
else
  link_to "Sign in", new_session_path
end

@items.each do |item|
  li item.name
end
```

**ERB Output:**
```erb
<% if user.signed_in? %>
  <p>Welcome, <%= user.name %>!</p>
<% else %>
  <%= link_to "Sign in", new_session_path %>
<% end %>

<% @items.each do |item| %>
  <li><%= item.name %></li>
<% end %>
```

### String Interpolation

**Markaby:**
```ruby
h2 "Hello, #{user.name}!"
p "You have #{@count} messages"
```

**ERB Output:**
```erb
<h2>Hello, <%= user.name %>!</h2>
<p>You have <%= @count %> messages</p>
```

### Ternary Operators

**Markaby:**
```ruby
p @comment.visible? ? "Published" : "Draft"
```

**ERB Output:**
```erb
<p><%= @comment.visible? ? "Published" : "Draft" %></p>
```

### Exception Handling

**Markaby:**
```ruby
begin
  render partial: "form"
rescue => e
  p "Error: #{e.message}"
end
```

**ERB Output:**
```erb
<% begin %>
  <%= render :partial => "form" %>
<% rescue => e %>
  <p>Error: <%= e.message %></p>
<% end %>
```

### Capture Method

**Markaby:**
```ruby
link_to capture {
  img :src => friend.logo
  div.friend_name friend.nickname
}, friend.uri, { :rel => friend.relationship }
```

**ERB Output:**
```erb
<%= link_to capture do %>
  <img src="<%= friend.logo %>">
  <div class="friend_name"><%= friend.nickname %></div>
<% end, friend.uri, {:rel => friend.relationship} %>
```

**Markaby (assigned to variable):**
```ruby
content = capture {
  h1 "Title"
  p "Description"
}
```

**ERB Output:**
```erb
<% content = capture do %>
  <h1>Title</h1>
  <p>Description</p>
<% end %>
```

## Error Handling

The converter raises specific exceptions that you can catch and handle:

```ruby
require 'markaby_to_erb'

begin
  converter = MarkabyToErb::Converter.new(markaby_code)
  erb_code = converter.convert
rescue MarkabyToErb::ParseError => e
  puts "Failed to parse Markaby code: #{e.message}"
  puts "Parser error: #{e.parser_error.message}" if e.parser_error
rescue MarkabyToErb::ConversionError => e
  puts "Conversion failed: #{e.message}"
  puts "Node type: #{e.node_type}" if e.node_type
  puts "Context: #{e.context}" if e.context
end
```

### Exception Types

- **`MarkabyToErb::ParseError`**: Raised when Markaby code cannot be parsed
  - `markaby_code`: The original code that failed to parse
  - `parser_error`: The underlying parser exception

- **`MarkabyToErb::ConversionError`**: Raised when conversion encounters an unsupported construct
  - `node_type`: The AST node type that couldn't be converted
  - `context`: Additional context about where the error occurred

## Supported Markaby Features

### HTML Tags
All standard HTML tags are supported, including: `html`, `head`, `body`, `div`, `span`, `p`, `h1-h6`, `ul`, `ol`, `li`, `table`, `tr`, `td`, `th`, `form`, `input`, `button`, `a`, `img`, `meta`, `br`, `hr`, `link`, `script`, `style`, and more.

### Rails Helpers
- Form helpers: `form_tag`, `form_for`, `text_field_tag`, `select_tag`, `check_box_tag`, etc.
- URL helpers: `link_to`, `link_to_remote`, `button_to`
- Asset helpers: `image_tag`, `stylesheet_link_tag`, `javascript_include_tag`
- Other: `render`, `content_for`, `flash`, `truncate`, `highlight`, etc.

### Control Structures
- Conditionals: `if`, `unless`, `elsif`, ternary operators
- Loops: `while`, `until`, `for`
- Iteration: `each`, `map`, `times`, `each_with_index`, `inject`, `each_pair`
- Flow control: `break`, `next`, `redo`, `retry`
- Exception handling: `begin`, `rescue`, `ensure`

### Ruby Features
- Variables: instance (`@var`), local (`var`), class (`@@var`), global (`$var`)
- String interpolation: `"Hello #{name}"`
- String concatenation: `"Hello " + name`
- Method calls and chains
- Hash and array literals
- Ranges: `1..10`, `1...10`
- Namespaced constants: `Date::ABBR_MONTHNAMES`
- `capture` method for capturing block output to variables or as method arguments

## Testing

Run the test suite:

```bash
bundle exec rspec
```

Run with coverage:

```bash
COVERAGE=true bundle exec rspec
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`bundle exec rspec`)
6. Commit your changes (`git commit -am 'Add some feature'`)
7. Push to the branch (`git push origin my-new-feature`)
8. Create a new Pull Request

## Known Limitations

- Some advanced Markaby Builder features may not be fully supported
- Comments from original Markaby code are not preserved

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).

## Author

James Moxley - moxley.james@gmail.com

## Links

- [GitHub Repository](https://github.com/wavesummit/markaby_to_erb)
- [Markaby Documentation](https://github.com/markaby/markaby)

## Changelog

### Version 0.1.0
- Initial release
- Basic Markaby to ERB conversion
- CLI tool for batch processing
- Comprehensive test coverage
- Exception handling
