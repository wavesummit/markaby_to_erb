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
    it 'converts string interpolation in JavaScript strings to Ruby interpolation' do
      # Issue: JavaScript heredocs should use Ruby interpolation with j() for HTML escaping
      # NOT ERB tags, because ERB tags inside heredocs cause syntax errors
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          var url = '/resource/asset/image/manage' + '#{@collection ? "/collection/" + @collection.permalink : ""}';
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          var url = '/resource/asset/image/manage' + '#{j(@collection ? '/collection/' + @collection.permalink  : '')}';
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts image_tag in JavaScript string interpolation' do
      # Issue: Helper calls inside JavaScript heredocs should use #{j(...)} NOT <%= ... %>
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          $('#asterion_theme_list').html('<div>#{image_tag "loading_black.gif"}</div>');
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          $('#asterion_theme_list').html('<div>#{j(image_tag "loading_black.gif")}</div>');
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts translation calls in JavaScript string interpolation' do
      # Issue: Translation calls inside JavaScript heredocs should use #{j(t(...))} NOT <%= t(...) %>
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          $('#el').html('#{t(".your_comment_is_being_updated")}');
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          $('#el').html('#{j(t('.your_comment_is_being_updated'))}');
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts hash access in JavaScript string interpolation' do
      # Issue: Hash access inside JavaScript heredocs should use #{j(...)} NOT <%= ... %>
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          var data = { pageviews: #{@flot_json[:pageviews]}, visits: #{@flot_json[:visits]} };
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          var data = { pageviews: #{j(@flot_json[:pageviews])}, visits: #{j(@flot_json[:visits])} };
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts string interpolation in JavaScript heredoc to Ruby interpolation (not ERB tags)' do
      # Issue: When Markaby uses #{variable} inside javascript_tag heredoc,
      # it should convert to #{j(variable)} NOT <%= variable %>
      # ERB tags inside heredocs cause syntax errors
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          (function($){
            if ($('#like_url input').val() == '') {
              $('#like_url input').val('#{website.url}');
            }
          }($j));
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          (function($){
            if ($('#like_url input').val() == '') {
              $('#like_url input').val('#{j(website.url)}');
            }
          }($j));
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts translation calls in JavaScript heredoc to Ruby interpolation' do
      # Issue: Translation calls inside javascript_tag heredoc should use #{j(t(...))}
      # NOT <%= t(...) %> to avoid syntax errors
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          (function($){
            $.asterion.confirm_delete({
              link_target  : 'a.confirm_delete',
              title        : '#{t('.delete_comment')}',
              msg_target   : 'span.delete_comment',
              button1_txt  : '#{t('.delete_comment')}'
            });
          })($j);
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          (function($){
            $.asterion.confirm_delete({
              link_target  : 'a.confirm_delete',
              title        : '#{j(t('.delete_comment'))}',
              msg_target   : 'span.delete_comment',
              button1_txt  : '#{j(t('.delete_comment'))}'
            });
          })($j);
        } %>
      ERB
      expect_conversion(markaby_code, expected_erb)
    end

    it 'converts instance variables in JavaScript heredoc to Ruby interpolation' do
      # Issue: Instance variables inside javascript_tag heredoc should use #{j(@variable)}
      # NOT <%= @variable %> to avoid syntax errors
      markaby_code = <<~'MARKABY'
        javascript_tag %{
          (function($){
            $('#component_tag').html('<option value="">#{t('.display_all')}</option>');
          })($j);
        }
      MARKABY

      expected_erb = <<~'ERB'.strip
        <%= javascript_tag %{
          (function($){
            $('#component_tag').html('<option value="">#{j(t('.display_all'))}</option>');
          })($j);
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
end

