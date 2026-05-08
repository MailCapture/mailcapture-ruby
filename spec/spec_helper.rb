require 'webmock/rspec'
require 'mailcapture'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end
  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.order = :random

  # Disable all real network connections in tests.
  WebMock.disable_net_connect!
end

# ─── Shared helpers ──────────────────────────────────────────────────────────

BASE = 'https://mailcapture.app'

def stub_json(method, path, status:, body:)
  stub_request(method, "#{BASE}#{path}")
    .to_return(
      status: status,
      body: body.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
end

def ping_body(username = 'alice')
  {
    status: 'ok', username: username,
    address_template: "#{username}-{tag}@mailcapture.app",
    example: "#{username}-signup@mailcapture.app"
  }
end

def capture_body(id: 'cap-1', tag: 'signup', otp: '123456')
  {
    id: id, tag: tag, subject: 'Test Email',
    otp: otp, body_text: 'Hello', body_html: '<p>Hello</p>',
    latency_ms: 100, status: 'captured',
    received_at: '2024-01-01T00:00:00Z'
  }
end

def latest_body(cap = capture_body)
  { items: [cap], count: 1, next_after: '2024-01-01T00:00:01Z' }
end

def timeout_body
  { status: 'error', message: 'REQUEST_TIMEOUT', detail: 'Timed out' }
end

def error_body(message, detail = nil)
  { status: 'fail', message: message, detail: detail }
end

def new_client(**opts)
  MailCapture.new(api_key: 'mc_testkey', **opts)
end
