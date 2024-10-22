require 'spec_helper'

RSpec.describe MarkabyToErb::Converter do
  it 'converts simple Markaby code to ERB' do
    markaby_code = <<~MARKABY
      h1 "Hello, World!"
    MARKABY

    expected_erb = <<~ERB.strip
      <h1>Hello, World!</h1>
    ERB

    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert

    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      h4 do
        text "TADA!"
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <h4>
        TADA!
      </h4>
    ERB

    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
        meta charset: "utf-8"
      MARKABY

      expected_erb = <<~ERB.strip
        <meta charset="utf-8">
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      html do
        head do
          title "Sample Page"
          meta charset: "utf-8"
        end
        body do
          h1 "Hello, World!"
          p "This is a paragraph in Markaby."
          a "Click here", href: "https://example.com"
        end
      end
      MARKABY

      expected_erb = <<~ERB.strip
        <html>
          <head>
            <title>Sample Page</title>
            <meta charset="utf-8">
          </head>
          <body>
            <h1>Hello, World!</h1>
            <p>This is a paragraph in Markaby.</p>
            <a href="https://example.com">Click here</a>
          </body>
        </html>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      div id: "container" do
        ul do
          li "Item 1"
          li "Item 2", class: "highlighted"
          li do
            a "Nested Link", href: "https://example.com"
          end
        end
      end
      MARKABY

      expected_erb = <<~ERB.strip
        <div id="container">
          <ul>
            <li>Item 1</li>
            <li class="highlighted">Item 2</li>
            <li>
              <a href="https://example.com">Nested Link</a>
            </li>
          </ul>
        </div>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby_code' do

    markaby_code = <<~MARKABY
      label "Name:"
    MARKABY

    expected_erb = <<~ERB.strip
    <%= label "Name:" %>
    ERB

    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)

  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      form action: "/submit", method: "post" do
        label "Name:"
        input type: "text", name: "username"
        br
        label "Password:"
        input type: "password", name: "password"
        br
        input type: "submit", value: "Login"
      end
      MARKABY

      expected_erb = <<~ERB.strip
        <form action="/submit" method="post">
          <%= label "Name:" %>
          <input type="text" name="username">
          <br>
          <%= label "Password:" %>
          <input type="password" name="password">
          <br>
          <input type="submit" value="Login">
        </form>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      greeting = "Welcome to the Site!"
      html do
        body do
          h2 greeting
          p "This content is dynamically generated with a variable."
        end
      end
      MARKABY

      expected_erb = <<~ERB.strip
      <% greeting = "Welcome to the Site!" %>
      <html>
        <body>
          <h2><%= greeting %></h2>
          <p>This content is dynamically generated with a variable.</p>
        </body>
      </html>

      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      @items.each do |item|
        li item.name
      end
      MARKABY

      expected_erb = <<~ERB.strip
        <% @items.each do |item| %>
          <li><%= item.name %></li>
        <% end %>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
          items.each do |i,item|
            li item
          end
      MARKABY
      expected_erb = <<~ERB.strip
        <% items.each do |i,item| %>
          <li><%= item %></li>
        <% end %>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
        items = ["Apple", "Banana", "Cherry"]
          ul do
          items.each do |i,item|
            li item
          end
        end
      MARKABY
      expected_erb = <<~ERB.strip
      <% items = ["Apple", "Banana", "Cherry"] %>
      <ul>
        <% items.each do |i,item| %>
          <li><%= item %></li>
        <% end %>
      </ul>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      logged_in = true
      html do
        body do
          if logged_in
            p "You are logged in."
          else
            p "Please log in to continue."
          end
        end
      end

      MARKABY
      expected_erb = <<~ERB.strip
      <% logged_in = true %>
      <html>
        <body>
          <% if logged_in %>
            <p>You are logged in.</p>
          <% else %>
            <p>Please log in to continue.</p>
          <% end %>
        </body>
      </html>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      table do
        tr do
          th "Name"
          th "Age"
        end
        tr do
          td "Alice"
          td "30"
        end
        tr do
          td "Bob"
          td "25"
        end
      end

      MARKABY
      expected_erb = <<~ERB.strip
      <table>
        <tr>
          <th>Name</th>
          <th>Age</th>
        </tr>
        <tr>
          <td>Alice</td>
          <td>30</td>
        </tr>
        <tr>
          <td>Bob</td>
          <td>25</td>
        </tr>
      </table>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end


  it 'converts markaby code' do
      markaby_code = <<~MARKABY

        text "Associated by credit card (\#{user.name}) "
        link_to_remote "[+]", :url => {:controller => 'user', :action  => 'assoc_cc_block', :id => user.id}

      MARKABY
      expected_erb = <<~ERB.strip
        <%= "Associated by credit card (\#{user.name}) " %>
        <%= link_to_remote "[+]", {:url => {:controller => 'user', :action => 'assoc_cc_block', :id => user.id}} %>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
       unless x > 10
          text "Hello"
        end
      MARKABY

      expected_erb = <<~ERB.strip
        <% unless x > 10 %>
          Hello
        <% end %>
      ERB

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
      markaby_code = <<~MARKABY
        div do
          span "This content is shown"
        end unless some_var
      MARKABY

      expected_erb = <<~ERB.strip
      <% unless some_var %>
        <div>
          <span>This content is shown</span>
        </div>
      <% end %>
      ERB
      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end

  
  it 'converts markaby code' do
      markaby_code = <<~MARKABY
      form_remote_tag(:url => { :controller => 'user', :action => 'add_command_form', :order_id => params['order_id'], :id => params['id']})
        label "Hello"
      end_form

      MARKABY

      expected_erb = <<~ERB.strip
      <%= form_remote_tag {:url => {:controller => 'user', :action => 'add_command_form', :order_id => params[:order_id], :id => params[:id]}} %>
      <%= label "Hello" %>
      <%= end_form %>
      ERB
      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      expect(erb_code.strip).to eq(expected_erb)
  end





  # Additional test cases
end
