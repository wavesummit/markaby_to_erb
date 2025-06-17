Gem::Specification.new do |spec|
  spec.name          = "markaby_to_erb"
  spec.version       = MarkabyToErb::VERSION
  spec.authors       = ["James Moxley"]
  spec.email         = ["moxley.james@gmail.com"]

  spec.summary       = "A gem to convert Markaby code to ERB templates."
  spec.description   = "This gem parses Markaby code and outputs equivalent ERB templates for Rails applications."
  spec.homepage      = "https://github.com/wavesummit/markaby_to_erb"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "bin/*", "*.md", "LICENSE"]
  spec.require_paths = ["lib"]

  # Specify the required Ruby version
  spec.required_ruby_version = '>= 2.5.0'

  spec.add_dependency 'parser', '~> 3.0'
end
