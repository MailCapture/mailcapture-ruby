# mailcapture

Official Ruby gem for [MailCapture](https://mailcapture.app) — a real email capture API for integration testing OTP codes, verification links, and other transactional emails.

Zero runtime dependencies. Works with any Ruby web framework (Rails, Sinatra, Hanami, Roda, or plain Rack).

## Requirements

- Ruby 3.1+

## Installation

Add to your Gemfile:

```ruby
gem 'mailcapture'
```

Or install directly:

```bash
gem install mailcapture
```

## Quick start

```ruby
mc = MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY'])
mc.ping  # validates key, caches username

# In your test:
mc.delete('signup')
MyApp.register(mc.address('signup'))   # "alice-signup@mailcapture.app"
email = mc.wait_for('signup', timeout: 15)

puts email.subject   # "Verify your account"
puts email.otp       # "123456" — extracted automatically
```

## Integration test pattern (RSpec)

```ruby
# spec/features/user_registration_spec.rb
require 'rails_helper'

RSpec.describe 'User registration email', :integration do
  let(:mc)    { MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY']) }
  let(:inbox) { mc.inbox('signup') }

  before(:all) { mc.ping }   # validates key, caches username
  before(:each) { inbox.clear }  # clean inbox before every test

  it 'sends a 6-digit OTP' do
    post '/users', params: { email: inbox.address }

    email = inbox.wait_for(timeout: 10)

    expect(email.subject).to eq('Verify your account')
    expect(email.otp).to match(/\A\d{6}\z/)
    expect(email.latency_ms).to be < 5000
  end
end
```

## Integration test pattern (Minitest / Rails)

```ruby
# test/integration/signup_test.rb
class SignupEmailTest < ActionDispatch::IntegrationTest
  setup do
    @mc    = MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY'], username: 'alice')
    @inbox = @mc.inbox('signup')
    @inbox.clear
  end

  test 'sends verification email with OTP' do
    post sign_up_path, params: { email: @inbox.address }

    email = @inbox.wait_for(timeout: 10)

    assert_equal 'Verify your account', email.subject
    assert_match(/\A\d{6}\z/, email.otp)
  end
end
```

## API reference

### `MailCapture.new(api_key:, ...)`

```ruby
# Minimal
mc = MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY'])

# All options
mc = MailCapture.new(
  api_key:  ENV['MAILCAPTURE_API_KEY'],
  base_url: 'http://localhost:3002',  # local dev
  timeout:  15,                       # default request timeout in seconds
  username: 'alice',                  # pre-set to skip ping
)
```

---

### `mc.ping` → `PingResult`

Validates your API key and returns your address template. Caches your username so `address` works without a network call.

```ruby
result = mc.ping
result.username          # => "alice"
result.address_template  # => "alice-{tag}@mailcapture.app"
result.example           # => "alice-signup@mailcapture.app"
```

---

### `mc.wait_for(tag, timeout:, poll_timeout:, after:)` → `Capture`

Long-polls the API and returns the first email captured for the given tag. The server holds the connection open — no busy-waiting.

```ruby
# Named arguments (recommended)
email = mc.wait_for('signup', timeout: 15)

# Full options
email = mc.wait_for('signup',
  timeout:      15,             # total seconds to wait (default 30)
  poll_timeout: 5,              # per-poll server timeout in seconds, max 30 (default 10)
  after:        Time.now - 30,  # only captures after this time
)
```

Raises `MailCapture::TimeoutError` if no email arrives in time.

---

### `mc.inbox(tag)` → `Inbox`

Returns a scoped `Inbox` for a tag. Keeps test code clean.

```ruby
inbox = mc.inbox('password-reset')

inbox.address               # => "alice-password-reset@mailcapture.app"
inbox.wait_for(timeout: 10) # => Capture
inbox.list(limit: 5)        # => CaptureList
inbox.clear                 # deletes all captures for this tag
```

---

### `mc.address(tag)` → `String`

Generates the capture email address synchronously. Requires `ping` first (or `username:` in the constructor).

```ruby
mc.ping
mc.address('signup')  # => "alice-signup@mailcapture.app"
```

---

### `mc.list(tag:, limit:, after:)` → `CaptureList`

Lists recent captures (newest first).

```ruby
result = mc.list(tag: 'signup', limit: 10)
result.items.each { |email| puts email.subject }
result.count  # => total count
```

---

### `mc.get(capture_id)` → `Capture`

Gets a single capture by ID. Raises `MailCapture::NotFoundError` if not found.

---

### `mc.delete(tag)` → `nil`

Deletes all captures for a tag. Use in `before(:each)` or `setup` for test isolation.

---

## The `Capture` object

```ruby
email.id          # String  — UUID
email.tag         # String  — e.g. "signup"
email.subject     # String  — email subject line
email.otp         # String? — extracted code, nil if none detected
email.body_text   # String? — plain-text body
email.body_html   # String? — HTML body
email.latency_ms  # Integer — send-to-capture time in ms
email.status      # String  — e.g. "captured"
email.received_at # String  — ISO 8601 timestamp
```

The `otp` field is extracted automatically. If your OTP is in the middle of a sentence, the service finds it for you.

---

## Exception handling

All exceptions extend `MailCapture::Error` and have a `code` attribute.

```ruby
begin
  email = mc.wait_for('signup', timeout: 10)
rescue MailCapture::TimeoutError => e
  puts "Waited #{e.waited_seconds}s for tag: #{e.tag}"
  puts 'Did the email actually send? Check your email service logs.'
rescue MailCapture::AuthError
  puts 'Check your MAILCAPTURE_API_KEY environment variable.'
rescue MailCapture::NetworkError => e
  puts "Network error: #{e.message}"
end
```

| Exception | `code` | When |
|---|---|---|
| `MailCapture::AuthError` | `UNAUTHORIZED` | Invalid or revoked API key |
| `MailCapture::TimeoutError` | `TIMEOUT` | `wait_for` exceeded its timeout |
| `MailCapture::NotFoundError` | `NOT_FOUND` | `get` — capture not found |
| `MailCapture::NetworkError` | `NETWORK_ERROR` | Could not reach the API |
| `MailCapture::ApiError` | varies | Unexpected API error |

---

## Parallel tests

Each tag is its own inbox — safe to run in parallel.

```ruby
# RSpec with parallel_tests gem:
describe 'signup email', :parallel do
  let(:inbox) { mc.inbox("signup-#{$$}") }  # per-process tag
  before { inbox.clear }

  it 'sends OTP' do
    email = inbox.wait_for(timeout: 10)
    expect(email.otp).to match(/\A\d{6}\z/)
  end
end
```

---

## Rails configuration

```ruby
# config/initializers/mailcapture.rb (test environment only)
if Rails.env.test?
  MAILCAPTURE = MailCapture.new(
    api_key: ENV.fetch('MAILCAPTURE_API_KEY'),
    username: ENV.fetch('MAILCAPTURE_USERNAME', nil),  # skip ping if known
  )
end
```

---

## Local development

```ruby
mc = MailCapture.new(api_key: key, base_url: 'http://localhost:3002')
```
