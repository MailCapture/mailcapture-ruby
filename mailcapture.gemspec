require_relative 'lib/mailcapture/version'

Gem::Specification.new do |spec|
  spec.name        = 'mailcapture'
  spec.version     = MailCapture::VERSION
  spec.summary     = 'Official Ruby SDK for the MailCapture email testing API'
  spec.description = 'Capture and assert on real transactional emails in integration and CI tests.'
  spec.homepage    = 'https://mailcapture.app'
  spec.license     = 'MIT'
  spec.authors     = ['MailCapture']

  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir['lib/**/*.rb', 'README.md']

  spec.add_development_dependency 'rake',    '~> 13.0'
  spec.add_development_dependency 'rspec',   '~> 3.13'
  spec.add_development_dependency 'webmock', '~> 3.23'
end
