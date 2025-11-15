require 'spec_helper'

RSpec.describe 'Additional examples' do
  # Note: Many of the original tests here are duplicates of tests in markaby_to_erb_spec.rb
  # This file focuses on additional edge cases and scenarios

  it 'handles nested conditionals with multiple levels' do
    markaby_code = <<~MARKABY
      if @user.present?
        if @user.admin?
          div.admin! do
            p "Admin Panel"
          end
        elsif @user.moderator?
          div.moderator! do
            p "Moderator Panel"
          end
        end
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% if @user.present? %>
        <% if @user.admin? %>
          <div id="admin">
            <p>Admin Panel</p>
          </div>
        <% elsif @user.moderator? %>
          <div id="moderator">
            <p>Moderator Panel</p>
          </div>
        <% end %>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles while loops' do
    markaby_code = <<~'MARKABY'
      @i = 0
      while @i < 5
        li "Item #{@i}"
        @i += 1
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% @i = 0 %>
      <% while @i < 5 %>
        <li><%= "Item #\{@i}" %></li>
        <% @i += 1 %>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles until loops' do
    markaby_code = <<~'MARKABY'
      @i = 0
      until @i >= 3
        p "Count: #{@i}"
        @i += 1
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% @i = 0 %>
      <% until @i >= 3 %>
        <p><%= "Count: #\{@i}" %></p>
        <% @i += 1 %>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles multiple rescue clauses' do
    markaby_code = <<~'MARKABY'
      begin
        div do
          text @risky_operation
        end
      rescue ArgumentError => @e
        div.error! do
          p "Argument error: #{@e.message}"
        end
      rescue StandardError => @e
        div.error! do
          p "Error: #{@e.message}"
        end
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% begin %>
        <div>
          <%= @risky_operation %>
        </div>
      <% rescue ArgumentError => @e %>
        <div id="error">
          <p><%= "Argument error: #\{@e.message}" %></p>
        </div>
      <% rescue StandardError => @e %>
        <div id="error">
          <p><%= "Error: #\{@e.message}" %></p>
        </div>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles complex method chains' do
    markaby_code = <<~MARKABY
      div do
        text @users.select { |u| u.active? }.map(&:name).join(", ")
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <div>
        <%= @users.select { |u| u.active? }.map(&:name).join(", ") %>
      </div>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles multiple class and id modifiers on same tag' do
    markaby_code = <<~MARKABY
      div.container.main.active! do
        p "Content"
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <div class="container main" id="active">
        <p>Content</p>
      </div>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles string interpolation with multiple variables' do
    markaby_code = <<~'MARKABY'
      p "Welcome #{@user.name}, you have #{@count} messages from #{@sender.name}"
    MARKABY

    expected_erb = <<~ERB.strip
      <p><%= "Welcome #\{@user.name}, you have #\{@count} messages from #\{@sender.name}" %></p>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles self-closing tags with multiple attributes' do
    markaby_code = <<~MARKABY
      img src: "photo.jpg", alt: "Photo", width: "100", height: "100", class: "thumbnail"
    MARKABY

    expected_erb = <<~ERB.strip
      <img src="photo.jpg" alt="Photo" width="100" height="100" class="thumbnail">
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles nested blocks with method calls' do
    markaby_code = <<~MARKABY
      div do
        @items.each do |item|
          div.item! do
            h3 item.title
            p item.description
          end
        end
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <div>
        <% @items.each do |item| %>
          <div id="item">
            <h3><%= item.title %></h3>
            <p><%= item.description %></p>
          </div>
        <% end %>
      </div>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles complex hash structures in attributes' do
    markaby_code = <<~MARKABY
      div data: { user: { id: @user.id, name: @user.name }, settings: { theme: 'dark' } } do
        p "Content"
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <div data="{:user => {:id => @user.id, :name => @user.name}, :settings => {:theme => 'dark'}}">
        <p>Content</p>
      </div>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles next statement in loops' do
    markaby_code = <<~MARKABY
      @items.each do |item|
        next if item.hidden?
        li item.name
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% @items.each do |item| %>
        <% if item.hidden? %>
          <% next %>
        <% end %>
        <li><%= item.name %></li>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles multiple attributes with special characters' do
    markaby_code = <<~MARKABY
      a href: "/path/to/page", class: "btn btn-primary", data: { toggle: "modal", target: "#myModal" } do
        text "Click Me"
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <a href="/path/to/page" class="btn btn-primary" data="{:toggle => 'modal', :target => '#myModal'}">
        Click Me
      </a>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles redo statement in loops' do
    markaby_code = <<~MARKABY
      @items.each do |item|
        redo if item.retry?
        li item.name
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% @items.each do |item| %>
        <% if item.retry? %>
          <% redo %>
        <% end %>
        <li><%= item.name %></li>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles retry statement in rescue blocks' do
    markaby_code = <<~'MARKABY'
      begin
        div do
          text @risky_operation
        end
      rescue => @e
        retry if @retry_count < 3
        p "Failed: #{@e.message}"
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% begin %>
        <div>
          <%= @risky_operation %>
        </div>
      <% rescue => @e %>
        <% if @retry_count < 3 %>
          <% retry %>
        <% end %>
        <p><%= "Failed: #\{@e.message}" %></p>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles for loops' do
    markaby_code = <<~MARKABY
      for item in @items
        li item.name
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% for item in @items %>
        <li><%= item.name %></li>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end
end
