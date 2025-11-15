require 'spec_helper'

RSpec.describe 'Real World Examples' do
  describe 'text_field partial' do
    it 'converts text_field.mab correctly' do
      markaby_code = <<~'MARKABY'
        if !settings[:use_placeholders]
          label :for => "form_#{@field.html_name}" do
            span @field.label
          end
        end
        div.asterion_input :style => ("width:#{@field.width}px" if !settings[:full_width_fields]) do
          text_field_tag "form[#{@field.html_name}]", value , :id => "form_#{@field.html_name}", :placeholder => (@field.label if settings[:use_placeholders])
        end
      MARKABY

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      
      # Check that the conversion produces valid ERB structure
      expect(erb_code).to include('<% if !settings[:use_placeholders] %>')
      expect(erb_code).to include('<label')
      expect(erb_code).to include('text_field_tag')
      expect(erb_code).to match(/div.*asterion_input/)  # More flexible match
      expect(erb_code).to include('@field.html_name')
      expect(erb_code).to include('@field.label')
    end
  end

  describe 'check_box partial' do
    it 'converts check_box.mab correctly' do
      markaby_code = <<~'MARKABY'
        hidden_field_tag "form[#{@field.html_name}]", t('.unchecked')
        check_box_tag "form[#{@field.html_name}]", t('.checked'), (value.present? && value != 'Unchecked'), :id => "form_#{@field.html_name}"
        label(:for => "form_#{@field.html_name}") { span(@field.label) }
      MARKABY

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      
      expect(erb_code).to include('hidden_field_tag')
      expect(erb_code).to include('check_box_tag')
      expect(erb_code).to include('<label')
      expect(erb_code).to include('<span>')
    end
  end

  describe 'gallery_thumbnails partial' do
    it 'converts gallery_thumbnails.mab correctly' do
      markaby_code = <<~'MARKABY'
        div.input_field.image_gallery_thumbnail_styles! do
          hidden_field :component, :image_type
          
          if thumbnails.include? "cropped"
            img.thumbnail_style.cropped_style! :src => '/images/gallery_ratio_cropped.gif', :style => 'margin:4px; margin-right:15px;', :class => component.image_type == :cropped ? 'selected' : ''
          end
          if thumbnails.include? "same_height"
            img.thumbnail_style.same_height_style! :src => '/images/gallery_ratio_height_even.gif', :style => 'margin:4px; margin-right:15px;', :class => [:same_height].include?(component.image_type) ? 'selected' : ''
          end
        end
      MARKABY

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      
      # The converter converts classes and ids separately, so check for both
      expect(erb_code).to include('div class="input_field"')
      expect(erb_code).to include('id="image_gallery_thumbnail_styles"')
      expect(erb_code).to include('hidden_field')
      expect(erb_code).to include('<% if thumbnails.include?')
      expect(erb_code).to include('<img')
    end
  end

  describe 'field partial' do
    it 'converts field.mab correctly' do
      markaby_code = <<~'MARKABY'
        if field.good? or authenticated?
          classes = ['form_field', "form_#{field.attributes['type'].to_s.demodulize.underscore}_field", "form_field_#{@field.html_name}"]
          classes.map! { |x| 'dialog_' + x} and classes.unshift('form_editor_field') if @editable
          classes << 'fieldWithErrors' if @form_errors and @form_errors[@field.html_name]
          classes << 'field_invalid' unless field.good?

          div(:class => classes.join(" ")) do
            value = params["form"] ? params["form"][@field.html_name] : ''

            render :partial => '/shared/form/field_editor', :locals => {:field => @field} if @editable
            render :partial => ('/shared/form/field/' + field.class.to_s.demodulize.underscore), :locals => {:field => field, :editable => @editable, :value => value, :settings => settings}

            if @form_errors and @form_errors[@field.html_name]
              div.formError @form_errors[@field.html_name]
            end
            
            unless field.good?
              p.formError { 'This is a pro-only feature' }
            end
          end
        end
      MARKABY

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      
      expect(erb_code).to include('<% if field.good? || authenticated? %>')
      expect(erb_code).to include('classes =')
      expect(erb_code).to include('render :partial')
      expect(erb_code).to include('<div class=')
      expect(erb_code).to include('<% unless field.good? %>')
    end
  end

  describe 'pages_tabs partial' do
    it 'converts pages_tabs.mab correctly' do
      markaby_code = <<~MARKABY
        content_for(:dialog_tabs ) do
          tabs = []
          tabs << { :label => t('.website_pages'), :url => { :controller => '/resource/page', :action => 'manage' }}
          tabs << { :label => t('.pageurl_redirects'), :url => { :controller => '/resource/redirect', :action => 'manage' }}
           tabs << { :label => t('.primary_navigation'), :url => { :controller => '/resource/website', :action => 'navigation' }}
          dialog_tabs( tabs )
        end
      MARKABY

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      
      expect(erb_code).to include('<% content_for :dialog_tabs do %>')
      expect(erb_code).to include('tabs = []')
      expect(erb_code).to include('tabs <<')
      expect(erb_code).to include('dialog_tabs')
    end
  end

  describe 'full gallery_thumbnails with javascript' do
    it 'converts the complete gallery_thumbnails.mab with javascript_tag' do
      markaby_code = <<~'MARKABY'
        div.input_field.image_gallery_thumbnail_styles! do
          hidden_field :component, :image_type
          
          if thumbnails.include? "cropped"
            img.thumbnail_style.cropped_style! :src => '/images/gallery_ratio_cropped.gif', :style => 'margin:4px; margin-right:15px;', :class => component.image_type == :cropped ? 'selected' : ''
          end
        end

        javascript_tag %{
          (function($){
            function hide_show(s){
              $('#thumbnail_height').hide();
              if ( s == 'cropped' ) {
                $('#image_size').hide();
                $('#square_sizes').show();
              }
            }
          }($j));
        }
      MARKABY

      converter = MarkabyToErb::Converter.new(markaby_code)
      erb_code = converter.convert
      
      # The converter converts classes and ids separately
      expect(erb_code).to include('div class="input_field"')
      expect(erb_code).to include('id="image_gallery_thumbnail_styles"')
      expect(erb_code).to include('javascript_tag')
      expect(erb_code).to include('function hide_show')
    end
  end
end

