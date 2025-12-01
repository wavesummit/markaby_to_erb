require 'spec_helper'

RSpec.describe MarkabyToErb::Converter, 'real world issues' do
    
    it 'handles standalone constant references' do
      markaby_code = <<~'MARKABY'
        Mab
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= Mab %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles empty files' do
      markaby_code = ""

      expected_erb = ""

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles files with only comments' do
      markaby_code = <<~'MARKABY'
        # nothing here yet
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%# nothing here yet %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles files with multiple comment lines' do
      markaby_code = <<~'MARKABY'
        # nothing here!
        # placeholder for future code
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%# nothing here! %>
        <%# placeholder for future code %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles files with comments and blank lines' do
      markaby_code = <<~'MARKABY'
        # nothing here yet

        # more comments
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%# nothing here yet %>

        <%# more comments %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles ternary operators in class attributes' do
      markaby_code = <<~'MARKABY'
        div(:class => (@content_for_dialog_size.nil? ? 'medium_dialog' : "#{@content_for_dialog_size}_dialog")) do
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <div class="<%= @content_for_dialog_size.nil? ? 'medium_dialog' : "#{@content_for_dialog_size}_dialog" %>">
        </div>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles instance variables as tag content' do
      markaby_code = <<~'MARKABY'
        h1 @content_for_dialog_heading
      MARKABY

      expected_erb = <<~'ERB'.strip
        <h1><%= @content_for_dialog_heading %></h1>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles nested unless statements' do
      markaby_code = <<~'MARKABY'
        unless params[:controller] == 'resource/help'
          li do
            link_to t('.help'), "#{wiki_url(help_path)}"
          end unless @content_for_help_path == 'none'
        end unless @content_for_dialog_header_tools
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% unless @content_for_dialog_header_tools %>
          <% unless params[:controller] == 'resource/help' %>
            <% unless @content_for_help_path == 'none' %>
              <li>
                <%= link_to t('.help'), "#{wiki_url(help_path)}" %>
              </li>
            <% end %>
          <% end %>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

  describe 'string interpolation in hash keys' do
    it 'quotes string interpolation in hash keys' do
      markaby_code = <<~'MARKABY'
        label :for => "form_#{@field.html_name}" do
          span @field.label
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <label for="<%= "form_#{@field.html_name}" %>">
          <span><%= @field.label %></span>
        </label>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'quotes string interpolation in id attribute' do
      markaby_code = <<~'MARKABY'
        text_field_tag "form[#{@field.html_name}]", value, :id => "form_#{@field.html_name}"
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= text_field_tag "form[#{@field.html_name}]", value, {:id => "form_#{@field.html_name}"} %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'JavaScript string interpolation' do
    it 'converts string interpolation in JavaScript strings to ERB' do
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          var url = '/resource/asset/image/manage' + '#{@collection ? "/collection/" + @collection.permalink : ""}';
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          var url = '/resource/asset/image/manage' + '<%= @collection ? "/collection/" + @collection.permalink  : "" %>';
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts image_tag in JavaScript string interpolation' do
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          $('#asterion_theme_list').html('<div>#{image_tag "loading_black.gif"}</div>');
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          $('#asterion_theme_list').html('<div><%= image_tag "loading_black.gif" %></div>');
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts translation calls in JavaScript string interpolation' do
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          $('#el').html('#{t(".your_comment_is_being_updated")}');
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          $('#el').html('<%= t(".your_comment_is_being_updated") %>');
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts hash access in JavaScript string interpolation' do
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          var data = { pageviews: #{@flot_json[:pageviews]}, visits: #{@flot_json[:visits]} };
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          var data = { pageviews: <%= @flot_json[:pageviews] %>, visits: <%= @flot_json[:visits] %> };
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'local variables in output' do
    it 'converts local variable to ERB output tag' do
      markaby_code = <<~'MARKABY'
        @content_for_dialog_header_tools.each do |item|
          li do
            item
          end
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% @content_for_dialog_header_tools.each do |item| %>
          <li>
            <%= item %>
          </li>
        <% end %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'string interpolation in single quotes' do
    it 'converts string interpolation in single quotes to double quotes' do
      markaby_code = <<~'MARKABY'
        select_field :component, :stat_type, PAGE_COUNTER_TYPE.collect { |type| [t("page_counter_type.#{type}"), type] }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= select_field :component, :stat_type, PAGE_COUNTER_TYPE.collect { |type| [t("page_counter_type.#{type}"), type] } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'array in content_for blocks' do
    it 'converts array in content_for block' do
      markaby_code = <<~'MARKABY'
        content_for(:dialog_header_tools) do
          [
            link_to(t('.preview_changes'), '#', :class => 'dialog_button'),
            link_to(t('.save_changes'), '#', :class => 'dialog_button')
          ]
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% content_for(:dialog_header_tools) do %>
          <%= raw [
            link_to(t('.preview_changes'), '#', {:class => 'dialog_button'}),
            link_to(t('.save_changes'), '#', {:class => 'dialog_button'})
          ].join %>
        <% end %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'hash access with string keys' do
    it 'converts hash access with string keys' do
      markaby_code = <<~'MARKABY'
        if @navigation_item
          active = @navigation_item.attributes['type'] == icon[:type]
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% if @navigation_item %>
          <% active = @navigation_item.attributes['type'] == icon[:type] %>
        <% end %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'collection preview example' do
    it 'converts collection preview with JavaScript interpolation' do
      markaby_code = <<~'MARKABY'
        dialog_button :function, t('.upload_images'), %{
          $j.asterion.assetSelect(function(id, url) { updateCollectionPreview(); }, 
            { upload: true, type : 'image', collection : '#{@collection ? @collection.permalink : ""}', closeOnUpload : true
          });
        }, :class => 'general dialog_button icon upload_icon'
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= dialog_button :function, t('.upload_images'), %{
          $j.asterion.assetSelect(function(id, url) { updateCollectionPreview(); }, 
          { upload: true, type : 'image', collection : '<%= @collection ? @collection.permalink : "" %>', closeOnUpload : true
          });
        }, {:class => 'general dialog_button icon upload_icon'} %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'text field with conditional style' do
    it 'converts text field with conditional style attribute' do
      markaby_code = <<~'MARKABY'
        div.asterion_input :style => ("width:#{@field.width}px" if !settings[:full_width_fields]) do
          text_field_tag "form[#{@field.html_name}]", value, :id => "form_#{@field.html_name}"
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <div class="asterion_input"<% if !settings[:full_width_fields] %> style="width:<%= @field.width %>px"<% end %>>
          <%= text_field_tag "form[#{@field.html_name}]", value, {:id => "form_#{@field.html_name}"} %>
        </div>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'form field with string literals' do
    it 'quotes string literals in array operations' do
      markaby_code = <<~'MARKABY'
        classes << 'fieldWithErrors' if @form_errors and @form_errors[@field.html_name]
        classes << 'field_invalid' unless field.good?
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% classes << 'fieldWithErrors' if @form_errors && @form_errors[@field.html_name] %>
        <% classes << 'field_invalid' unless field.good? %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'default instance variable output option' do
    it 'prefixes bare identifiers with @ when enabled' do
      markaby_code = <<~'MARKABY'
        h1 dialog_heading
      MARKABY

      expected_erb = <<~'ERB'.strip
        <h1><%= @dialog_heading %></h1>
      ERB

      expect_conversion(markaby_code, expected_erb, default_to_instance_variables: true)
    end

    it 'leaves path helper style methods unchanged' do
      markaby_code = <<~'MARKABY'
        p account_path
      MARKABY

      expected_erb = <<~'ERB'.strip
        <p><%= account_path %></p>
      ERB

      expect_conversion(markaby_code, expected_erb, default_to_instance_variables: true)
    end
  end

  describe 'HTML string interpolation in conditionals' do
    it 'converts HTML strings with interpolation in if/else blocks' do
      markaby_code = <<~'MARKABY'
        if collection.assets.size == 0
          '--'
        else
          "<b>#{collection.assets.size}</b>"
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% if collection.assets.size == 0 %>
          --
        <% else %>
          <b><%= collection.assets.size %></b>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  # ==========================================================================
  # Tests for issues found during Hydra project conversion (392 files)
  # ==========================================================================

  describe 'elsif inside tag blocks' do
    it 'converts if/elsif/end inside a td block' do
      markaby_code = <<~'MARKABY'
        td :align => 'center' do
          if @notification.state == 'informational'
            link_to icon('information'), { :controller => 'notifications', :action => 'index' }
          elsif @notification.state == 'warning'
            link_to icon('alert'), { :controller => 'notifications', :action => 'index' }
          end
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <td align="center">
          <% if @notification.state == 'informational' %>
            <%= link_to icon('information'), {:controller => 'notifications', :action => 'index'} %>
          <% elsif @notification.state == 'warning' %>
            <%= link_to icon('alert'), {:controller => 'notifications', :action => 'index'} %>
          <% end %>
        </td>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts if/elsif/else/end inside a div block' do
      markaby_code = <<~'MARKABY'
        div.status do
          if user.active?
            span.green "Active"
          elsif user.pending?
            span.yellow "Pending"
          else
            span.red "Inactive"
          end
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <div class="status">
          <% if user.active? %>
            <span class="green">Active</span>
          <% elsif user.pending? %>
            <span class="yellow">Pending</span>
          <% else %>
            <span class="red">Inactive</span>
          <% end %>
        </div>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'ternary expressions with complex hash parameters' do
    it 'converts conditional hash assignment with full if/else blocks' do
      # When both branches are assignments, they should be full if/else blocks
      markaby_code = <<~'MARKABY'
        if selected
          inputProps = {:class => 'checkbox', :checked => 'checked'}
        else
          inputProps = {:class => 'checkbox'}
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% if selected %>
          <% inputProps = {:class => 'checkbox', :checked => 'checked'} %>
        <% else %>
          <% inputProps = {:class => 'checkbox'} %>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'comparison operators in tag blocks' do
    it 'converts greater than comparison in conditionals' do
      markaby_code = <<~'MARKABY'
        if items.count > 0
          ul do
            items.each do |item|
              li item.name
            end
          end
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% if items.count > 0 %>
          <ul>
            <% items.each do |item| %>
              <li><%= item.name %></li>
            <% end %>
          </ul>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts less than comparison in conditionals' do
      markaby_code = <<~'MARKABY'
        if page < total_pages
          link_to "Next", next_page_path
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% if page < total_pages %>
          <%= link_to "Next", next_page_path %>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts greater than or equal comparison' do
      markaby_code = <<~'MARKABY'
        span.badge count if count >= 1
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% if count >= 1 %>
          <span class="badge"><%= count %></span>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'UTF-8 encoded content' do
    it 'handles UTF-8 special characters in strings' do
      markaby_code = <<~'MARKABY'
        p "Copyright © 2024"
      MARKABY

      expected_erb = <<~'ERB'.strip
        <p>Copyright © 2024</p>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles UTF-8 in tag content' do
      markaby_code = <<~'MARKABY'
        span "Ñoño"
      MARKABY

      expected_erb = <<~'ERB'.strip
        <span>Ñoño</span>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'end_form helper pattern' do
    it 'already handles end_form as closing form tag' do
      # Note: end_form is already handled in the converter
      markaby_code = <<~'MARKABY'
        end_form
      MARKABY

      expected_erb = <<~'ERB'.strip
        </form>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'complex nested conditionals in blocks' do
    it 'converts multiple elsif branches with helper calls' do
      markaby_code = <<~'MARKABY'
        td do
          if status == 'active'
            image_tag "icons/green.png"
          elsif status == 'pending'
            image_tag "icons/yellow.png"
          elsif status == 'suspended'
            image_tag "icons/orange.png"
          else
            image_tag "icons/red.png"
          end
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <td>
          <% if status == 'active' %>
            <%= image_tag "icons/green.png" %>
          <% elsif status == 'pending' %>
            <%= image_tag "icons/yellow.png" %>
          <% elsif status == 'suspended' %>
            <%= image_tag "icons/orange.png" %>
          <% else %>
            <%= image_tag "icons/red.png" %>
          <% end %>
        </td>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'tag with class and hash attributes' do
    it 'converts tag.class with hash attributes' do
      markaby_code = <<~'MARKABY'
        td.price(:style => 'text-align: right') { order.total }
      MARKABY

      # Note: attribute order may vary (style before class is acceptable)
      expected_erb = <<~'ERB'.strip
        <td style="text-align: right" class="price">
          <%= order.total %>
        </td>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts tag.class.another_class with hash attributes' do
      markaby_code = <<~'MARKABY'
        div.container.fluid(:id => 'main') do
          p "Content"
        end
      MARKABY

      # Note: attribute order may vary (id before class is acceptable)
      expected_erb = <<~'ERB'.strip
        <div id="main" class="container fluid">
          <p>Content</p>
        </div>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'form helpers with multiple hash arguments' do
    it 'converts form_tag with url hash and options hash' do
      markaby_code = <<~'MARKABY'
        form_tag({:controller => 'users', :action => 'create'}, {:id => 'user_form', :class => 'form'}) do
          text_field_tag :name
          submit_tag "Save"
        end
      MARKABY

      # Note: hash arguments are flattened without braces in block context
      expected_erb = <<~'ERB'.strip
        <% form_tag :controller => 'users', :action => 'create', :id => 'user_form', :class => 'form' do %>
          <%= text_field_tag :name %>
          <%= submit_tag "Save" %>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'nested iteration with conditionals' do
    it 'converts each loop with if/elsif inside' do
      markaby_code = <<~'MARKABY'
        @items.each do |item|
          tr do
            td item.name
            td do
              if item.status == 'active'
                span.green "Active"
              elsif item.status == 'inactive'
                span.red "Inactive"
              end
            end
          end
        end
      MARKABY

      expected_erb = <<~'ERB'.strip
        <% @items.each do |item| %>
          <tr>
            <td><%= item.name %></td>
            <td>
              <% if item.status == 'active' %>
                <span class="green">Active</span>
              <% elsif item.status == 'inactive' %>
                <span class="red">Inactive</span>
              <% end %>
            </td>
          </tr>
        <% end %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  # ==========================================================================
  # Tests for issues that still need fixes (from CONVERSION_ISSUES.md)
  # ==========================================================================

  describe 'Ruby method definitions (def node)' do
    it 'raises a clear error for method definitions in views' do
      markaby_code = <<~'MARKABY'
        def spacer
          label {"&nbsp;"}
        end
        tr { spacer }
      MARKABY

      # Method definitions in views should raise a helpful error
      expect {
        MarkabyToErb::Converter.new(markaby_code).convert
      }.to raise_error(MarkabyToErb::ConversionError, /method definition/i)
    end
  end

  describe 'form_tag with symbol values' do
    it 'handles form_tag with symbol values in hash' do
      markaby_code = <<~'MARKABY'
        form_tag({:controller => :users, :action => :create}, {:id => 'my_form'})
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= form_tag({:controller => :users, :action => :create}, {:id => 'my_form'}) %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles form_tag with mixed string and symbol values' do
      markaby_code = <<~'MARKABY'
        form_tag({:controller => 'users', :action => :new}, {:class => 'form'})
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= form_tag({:controller => 'users', :action => :new}, {:class => 'form'}) %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'HTML entities before method calls' do
    it 'handles html_safe with HTML entities' do
      markaby_code = <<~'MARKABY'
        p 'Hello &middot; World'.html_safe
      MARKABY

      expected_erb = <<~'ERB'.strip
        <p><%= 'Hello &middot; World'.html_safe %></p>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end

    it 'handles link_to_remote with HTML entities' do
      markaby_code = <<~'MARKABY'
        link_to_remote 'Lookup &middot;'.html_safe, :url => { :action => 'lookup' }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= link_to_remote 'Lookup &middot;'.html_safe, :url => {:action => 'lookup'} %>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end

  describe 'space before parentheses in method chaining' do
    # Note: This is actually valid Ruby syntax - `td.price (hash)` is calling
    # `price` with no args, then evaluating `(hash)` separately.
    # The fix is in the source code, not the converter. But we should handle
    # the correct form: `td.price(hash)`
    it 'converts tag.class(hash) with block correctly' do
      markaby_code = <<~'MARKABY'
        td.price(:style => 'text-decoration: line-through', :align => 'right') { order_command.price }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <td style="text-decoration: line-through" align="right" class="price">
          <%= order_command.price %>
        </td>
      ERB

      expect_conversion(markaby_code, expected_erb)
    end
  end
end

