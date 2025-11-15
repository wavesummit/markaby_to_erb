module MarkabyToErb
  module Helpers
    def html_tag?(method_name)
      %w[html head title body h1 h2 h3 h4 h5 h6 ul ol li a div span p
         table tr td th form input label select option
         textarea button meta br hr img link tbody thead
         hgroup i iframe object pre video tfoot dt em fieldset strong
         blockquote code].include?(method_name.to_s)
    end

    def iteration_method?(method_name)
      %w[each map times each_with_index inject each_pair].include?(method_name.to_s)
    end

    def self_closing_tag?(method_name)
      %w[meta input br hr img link].include?(method_name.to_s)
    end

    def keyword_arguments_method?(method_name)
      %w[render].include?(method_name.to_s)
    end

    def helper_call?(method_name)
      helpers = %w[render select_field observe_field form_tag form_for form_remote_tag submit_tag label_tag
                   text_field_tag password_field_tag select_tag check_box_tag radio_button_tag file_field_tag
                   link_to link_to_remote button_to
                   url_for image_tag stylesheet_link_tag javascript_include_tag date_select time_select
                   distance_of_time_in_words truncate highlight simple_format sanitize content_tag flash number_to_human_size]

      helpers.include?(method_name.to_s)
    end

    def variable?(node)
      case node.type
      when :lvar, :ivar, :cvar, :gvar
        true  # This is a variable
      else
        false # Not a variable
      end
    end



  end
end
