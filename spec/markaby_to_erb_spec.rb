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
      logged_out = false
      html do
        body do
          if logged_in
            p "You are logged in."
          elsif logged_out
            p "You have been logged out."
          else
            p "Please log in to continue."
          end
        end
      end

    MARKABY
    expected_erb = <<~ERB.strip
      <% logged_in = true %>
      <% logged_out = false %>
      <html>
        <body>
          <% if logged_in %>
            <p>You are logged in.</p>
          <% elsif logged_out %>
            <p>You have been logged out.</p>
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

  # form_remote_tag is replaced with
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

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      select_tag 'package', options_for_select('Starter' => STARTER_PACKAGE, 'Basic' => BASIC_PACKAGE, 'Email' => EMAIL_PACKAGE)
    MARKABY

    expected_erb = <<~ERB.strip
      <%= select_tag "package", options_for_select({'Starter' => STARTER_PACKAGE, 'Basic' => BASIC_PACKAGE, 'Email' => EMAIL_PACKAGE}) %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      completed_transaction.commands.each do |command|
        tooltip = ''
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <% completed_transaction.commands.each do |command| %>
        <% tooltip = "" %>
      <% end %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tooltip = ''
      tooltip += 'test'
    MARKABY
    expected_erb = <<~ERB.strip
      <% tooltip = "" %>
      <% tooltip += "test" %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tooltip = obj.method.method
      tooltip += obj.method.method
      tooltip += ( obj.method.method + obj.method.method )
    MARKABY

    expected_erb = <<~ERB.strip
      <% tooltip = obj.method.method %>
      <% tooltip += obj.method.method %>
      <% tooltip += ( obj.method.method + obj.method.method ) %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tooltip += ( obj.method.method + obj.method.method )
    MARKABY

    expected_erb = <<~ERB.strip
      <% tooltip += ( obj.method.method + obj.method.method ) %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tooltip = ''
      total = Money.new
      completed_transaction.commands.each do |command|
        tooltip += command.description + ' | ' + command.price.to_s + "\n | "
        total += command.price
      end
      tooltip += 'Total: ' + total.to_s
    MARKABY

    expected_erb = <<~ERB.strip
      <% tooltip = "" %>
      <% total = Money.new %>
      <% completed_transaction.commands.each do |command| %>
        <% tooltip += command.description + ' | ' + command.price.to_s + "\\n | " %>
        <% total += command.price %>
      <% end %>
      <% tooltip += 'Total: ' + total.to_s %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      select_tag 'package', options_for_select('Starter' => STARTER_PACKAGE, 'Basic' => BASIC_PACKAGE, 'Advanced' => PRO_PACKAGE, 'Corporate' => CORPORATE_PACKAGE, 'VIP' => VIP_PACKAGE, 'Email'  => EMAIL_PACKAGE)
      observe_field("package", :function => "alert('hello')")
    MARKABY
    expected_erb = <<~ERB.strip
      <%= select_tag "package", options_for_select({'Starter' => STARTER_PACKAGE, 'Basic' => BASIC_PACKAGE, 'Advanced' => PRO_PACKAGE, 'Corporate' => CORPORATE_PACKAGE, 'VIP' => VIP_PACKAGE, 'Email' => EMAIL_PACKAGE}) %>
      <%= observe_field "package", {:function => "alert('hello')"} %>
    ERB

    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tag!(:my_custom_tag, :class => "custom") do
        text "Custom content"
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <my_custom_tag class="custom">
        Custom content
      </my_custom_tag>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      empty_tag!(:img, :src => "image.png")
    MARKABY

    expected_erb = <<~ERB.strip
      <img src="image.png"/>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      th do
        'Type'
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <th>
        Type
      </th>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      th do
        td { "#\{some_var}" }
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <th>
        <td>
          <%= "#\{some_var}" %>
        </td>
      </th>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      div do
        text @some_var
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <div>
        <\%= @some_var %>
      </div>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      select_tag 'type', options_for_select(@command_types)
    MARKABY
    expected_erb = <<~ERB.strip
      <%= select_tag "type", options_for_select(@command_types) %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      select_tag 'type', options_for_select(@@command_types)
    MARKABY
    expected_erb = <<~ERB.strip
      <%= select_tag "type", options_for_select(@@command_types) %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      br.break.breaker!
    MARKABY
    expected_erb = <<~ERB.strip
      <br class="break" id="breaker">
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      div.main.main_container! do
        h1.head.header! "Welcome"
        p "This is a sample paragraph."
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <div class="main" id="main_container">
        <h1 class="head" id="header">Welcome</h1>
        <p>This is a sample paragraph.</p>
      </div>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      table do
        thead do
          tr do
            th { 'Credential' }
          end
        end

        tbody.credentials! do
          render :partial => "listed_credential", :collection => listed_credentials
        end
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <table>
        <thead>
          <tr>
            <th>
              Credential
            </th>
          </tr>
        </thead>
        <tbody id="credentials">
          <%= render {:partial => 'listed_credential', :collection => listed_credentials} %>
        </tbody>
      </table>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tbody.searchedLogins do
        render(:partial => 'user', :collection => @results) unless @results.nil?
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <tbody class="searchedLogins">
        <% unless @results.nil? %>
          <%= render {:partial => 'user', :collection => @results} %>
        <% end %>
      </tbody>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      @event.session.each_pair do |k,v|
        ul do
            v.each_pair do |setting, value|
              li do
                strong setting.to_s
                text ": #\{value}"
              end
            end
          end
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% @event.session.each_pair do |k,v| %>
        <ul>
          <% v.each_pair do |setting,value| %>
            <li>
              <strong><%= setting.to_s %></strong>
              <%= ": #\{value}" %>
            </li>
          <% end %>
        </ul>
      <% end %>

    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      tr :id => "searchResult-#\{marked_user.id}" do
      render :partial => 'user_row', :locals => {:marked_user => marked_user}
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <tr id=\"searchResult-#\{marked_user.id}\">
        <%= render {:partial => 'user_row', :locals => {:marked_user => marked_user}} %>
      </tr>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      pagination_links_each(user_pages, { :window_size => 5}) do |number|
        link_to_remote number.to_s, :url => { :action => 'perma_flagged_users', :page => number }
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <%= pagination_links_each(user_pages, {:window_size => 5}) do %>
        <%= link_to_remote number.to_s, {:url => {:action => 'perma_flagged_users', :page => number}} %>
      <% end %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      div.userInfo! do
        yield
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <div id="userInfo">
        <%= yield %>
      </div>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      table do
        tr do
          td STATUS_TO_READABLE[mail_account.status]
        end
      end
    MARKABY
    expected_erb = <<~ERB.strip
      <table>
        <tr>
          <td><%= STATUS_TO_READABLE[mail_account.status] %></td>
        </tr>
      </table>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      some_var = 1
      case some_var
      when 1
        p 'Hello'
      when 2
        p 'Good Bye'
      else
        p 'Can I help you'
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% some_var = 1 %>
      <% case some_var %>
        <% when 1 %>
          <p>Hello</p>
        <% when 2 %>
          <p>Good Bye</p>
        <% else %>
          <p>Can I help you</p>
      <% end %>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      content_for(:dialog_size) { 'large' }
      content_for(:dialog_heading) { t('.manage_categories')}
      content_for(:dialog_tabs) do
      dialog_tabs([
        { :label => t('.blog_posts'), :url => { :controller => '/resource/blog/post', :action => 'manage' } },
        { :active => true, :label => t('.categories'),:url => { :controller => '/resource/blog/category', :action => 'manage'} }
      ])
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% content_for :dialog_size, "large" %>
      <% content_for :dialog_heading, t('.manage_categories') %>

      <% content_for :dialog_tabs do %>
        <%= dialog_tabs([
          { label: t('.blog_posts'), url: { controller: '/resource/blog/post', action: 'manage' } },
          { active: true, label: t('.categories'), url: { controller: '/resource/blog/category', action: 'manage' } }
        ]) %>
      <% end %>

    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end

  it 'converts markaby code' do
    markaby_code = <<~MARKABY
      @output_xml_instruction = false
      xhtml_transitional do
        head do
          text '<script src="https://code.jquery.com/jquery-1.12.4.min.js"></script>'
          stylesheet_link_tag 'setup'
          javascript_include_tag 'admin'
          javascript_tag '$.asterion.dialog.handleKeypress = function() { }'
          text "<link rel='shortcut icon' href='#\{@website.brand.default_favicon_url}' />"
        end
        body do
          text content_for_layout
        end
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% @output_xml_instruction = false %>
      <!DOCTYPE html>
      <html>
        <head>
          <script src="https://code.jquery.com/jquery-1.12.4.min.js"></script>
          <%= stylesheet_link_tag "setup" %>
          <%= javascript_include_tag "admin" %>
          <%= javascript_tag "$.asterion.dialog.handleKeypress = function() { }" %>
          <%= "<link rel='shortcut icon' href='#\{@website.brand.default_favicon_url}' />" %>
        </head>
        <body>
          <%= content_for_layout %>
        </body>
      </html>
    ERB
    converter = MarkabyToErb::Converter.new(markaby_code)
    erb_code = converter.convert
    expect(erb_code.strip).to eq(expected_erb)
  end
end
