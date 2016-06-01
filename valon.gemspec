# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'valon/version'

Gem::Specification.new do |spec|
  spec.name          = "valon"
  spec.version       = Valon::VERSION
  spec.authors       = ["David MacMahon"]
  spec.email         = ["davidm@astro.berkeley.edu"]

  spec.summary       = %q{Ruby interface to Valon synthesizers}
  spec.description   = %q{Query and/or program a Valon synthesizer from the command line.}
  spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "serialport", "~> 1.3"

  spec.add_development_dependency "bundler", "~> 1.9"
  spec.add_development_dependency "rake", "~> 10.0"
end
