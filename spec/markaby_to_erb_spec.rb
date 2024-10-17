require 'spec_helper'

RSpec.describe MarkabyToErb::Converter do
  it 'converts simple Markaby code to ERB' do
    markaby_code = <<~MARKABY
      h1 "Hello, World!"
    MARKABY

    expected_erb = <<~ERB.strip
      <h1>
        Hello, World!
      </h1>
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

  # Additional test cases
end
