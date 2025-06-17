require 'spec_helper'

RSpec.describe 'Additional examples' do
  it 'converts td { user.name } to ERB' do
    markaby_code = <<~MARKABY
      td { user.name }
    MARKABY

    expected_erb = <<~ERB.strip
      <td>
        <%= user.name %>
      </td>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts form_tag with hash arguments' do
    markaby_code = <<~MARKABY
      form_tag({:controller => :ssl, :action => :contacts_form}, {:id => 'contact_creation_form', :class => 'ssl-form'})
    MARKABY

    expected_erb = <<~ERB.strip
      <%= form_tag({:controller => :ssl, :action => :contacts_form}, {:id => 'contact_creation_form', :class => 'ssl-form'}) %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts ftp_account updated_at strftime to ERB' do
    markaby_code = <<~MARKABY
      ftp_account.updated_at.strftime("%H:%M%P on %Y-%m-%d")
    MARKABY

    expected_erb = <<~ERB.strip
      <%= ftp_account.updated_at.strftime("%H:%M%P on %Y-%m-%d") %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts h2 with interpolation' do
    markaby_code = <<~MARKABY
      h2 "Learn how #{partner.name} can help you get online quickly."
    MARKABY

    expected_erb = <<~ERB.strip
      <h2>Learn how <%= partner.name %> can help you get online quickly.</h2>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts blockquote tag' do
    markaby_code = <<~MARKABY
      blockquote
    MARKABY

    expected_erb = <<~ERB.strip
      <blockquote></blockquote>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts link_to with image_tag' do
    markaby_code = <<~MARKABY
      link_to "Facebook #{image_tag 'facebook_64.png', :size => '64x64', :alt => 'Facebook'}", '/auth/facebook', :class => 'auth_provider'
    MARKABY

    expected_erb = <<~ERB.strip
      <%= link_to "Facebook #{image_tag 'facebook_64.png', :size => '64x64', :alt => 'Facebook'}", '/auth/facebook', :class => 'auth_provider' %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts code tag with css' do
    markaby_code = <<~MARKABY
      code '#feature_support h3 { background-image: url(/partners/1/support.png) }'
    MARKABY

    expected_erb = <<~ERB.strip
      <code>#feature_support h3 { background-image: url(/partners/1/support.png) }</code>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts conditional meta tag' do
    markaby_code = <<~MARKABY
      meta :name => 'description', :content => partner.meta_description if partner and partner.meta_description.present?
    MARKABY

    expected_erb = <<~ERB.strip
      <% if partner && partner.meta_description.present? %>
        <meta name="description" content="<%= partner.meta_description %>">
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts ajax_form with block' do
    markaby_code = <<~MARKABY
      ajax_form :url => {:action => 'add_to_list'}, :confirm_leave => :discard do
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <%= ajax_form :url => {:action => 'add_to_list'}, :confirm_leave => :discard do %>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'handles negated condition' do
    markaby_code = <<~MARKABY
      if !perma_flagged_user.contacted
      end
    MARKABY

    expected_erb = <<~ERB.strip
      <% if !perma_flagged_user.contacted %>
      <% end %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end

  it 'converts limit_opts assignment and translation' do
    markaby_code = <<~MARKABY
      limit_opts = (1..15).collect { |n| [n,n] }
      limit_opts << [t('.show_all'), 0]
    MARKABY

    expected_erb = <<~ERB.strip
      <% limit_opts = (1..15).collect { |n| [n, n] } %>
      <% limit_opts << [t('.show_all'), 0] %>
    ERB

    expect_conversion(markaby_code, expected_erb)
  end
end

