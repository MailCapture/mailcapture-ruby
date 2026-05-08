require 'spec_helper'

RSpec.describe MailCapture::Client do
  # ─── Constructor ────────────────────────────────────────────────────────────

  describe '.new' do
    it 'raises ArgumentError when api_key is empty' do
      expect { MailCapture.new(api_key: '') }.to raise_error(ArgumentError, /api_key is required/)
    end

    it 'warns when api_key does not start with mc_' do
      expect { MailCapture.new(api_key: 'bad_key') }.to output(/mc_/).to_stderr
    end

    it 'does not warn for mc_ keys' do
      expect { MailCapture.new(api_key: 'mc_abckey') }.not_to output.to_stderr
    end

    it 'does not warn for mc_test_ keys' do
      expect { MailCapture.new(api_key: 'mc_test_abc') }.not_to output.to_stderr
    end

    it 'sets a pre-supplied username' do
      mc = MailCapture.new(api_key: 'mc_testkey', username: 'alice')
      expect(mc.username).to eq('alice')
    end
  end

  # ─── ping ───────────────────────────────────────────────────────────────────

  describe '#ping' do
    it 'returns a PingResult with the correct username' do
      stub_json(:get, '/v1/ping', status: 200, body: ping_body('alice'))
      mc     = new_client
      result = mc.ping

      expect(result).to be_a(MailCapture::PingResult)
      expect(result.username).to eq('alice')
      expect(result.address_template).to eq('alice-{tag}@mailcapture.app')
    end

    it 'caches the username after a successful ping' do
      stub_json(:get, '/v1/ping', status: 200, body: ping_body('bob'))
      mc = new_client
      expect(mc.username).to be_nil

      mc.ping
      expect(mc.username).to eq('bob')
    end

    it 'sends the X-API-Key header' do
      stub_json(:get, '/v1/ping', status: 200, body: ping_body)
      new_client.ping
      expect(a_request(:get, "#{BASE}/v1/ping")
        .with(headers: { 'X-API-Key' => 'mc_testkey' })).to have_been_made
    end

    it 'raises AuthError on 401' do
      stub_json(:get, '/v1/ping', status: 401, body: error_body('UNAUTHORIZED', 'Invalid API key'))
      expect { new_client.ping }
        .to raise_error(MailCapture::AuthError) do |err|
          expect(err.code).to eq('UNAUTHORIZED')
          expect(err.message).to include('Authentication failed')
          expect(err.message).to include("mailcapture.app")
        end
    end
  end

  # ─── address ────────────────────────────────────────────────────────────────

  describe '#address' do
    it 'raises before ping is called' do
      mc = new_client
      expect { mc.address('signup') }.to raise_error(RuntimeError, /ping/)
    end

    it 'returns the correct email after ping' do
      stub_json(:get, '/v1/ping', status: 200, body: ping_body('carol'))
      mc = new_client
      mc.ping

      expect(mc.address('signup')).to eq('carol-signup@mailcapture.app')
      expect(mc.address('password-reset')).to eq('carol-password-reset@mailcapture.app')
    end

    it 'works without a ping call when username is pre-set' do
      mc = new_client(username: 'dave')
      expect(mc.address('invite')).to eq('dave-invite@mailcapture.app')
    end
  end

  # ─── wait_for ───────────────────────────────────────────────────────────────

  describe '#wait_for' do
    it 'returns the first capture when email arrives immediately' do
      cap = capture_body(id: 'cap-1', otp: '999999')
      stub_request(:get, %r{#{BASE}/v1/latest/signup})
        .to_return(status: 200, body: latest_body(cap).to_json,
                   headers: { 'Content-Type' => 'application/json' })

      email = new_client.wait_for('signup', timeout: 5)

      expect(email).to be_a(MailCapture::Capture)
      expect(email.id).to eq('cap-1')
      expect(email.otp).to eq('999999')
    end

    it 'loops on 408 and returns capture on the next poll' do
      cap = capture_body(id: 'cap-2', otp: '654321')
      stub_request(:get, %r{/v1/latest/signup})
        .to_return(
          { status: 408, body: timeout_body.to_json, headers: { 'Content-Type' => 'application/json' } },
          { status: 200, body: latest_body(cap).to_json, headers: { 'Content-Type' => 'application/json' } }
        )

      email = new_client.wait_for('signup', timeout: 30, poll_timeout: 1)

      expect(email.id).to eq('cap-2')
      expect(email.otp).to eq('654321')
      expect(WebMock).to have_requested(:get, %r{/v1/latest/signup}).twice
    end

    it 'raises TimeoutError when deadline passes' do
      stub_request(:get, %r{/v1/latest/signup})
        .to_return(status: 408, body: '{}', headers: { 'Content-Type' => 'application/json' })

      expect { new_client.wait_for('signup', timeout: 0.1, poll_timeout: 1) }
        .to raise_error(MailCapture::TimeoutError) do |err|
          expect(err.code).to eq('TIMEOUT')
          expect(err.tag).to eq('signup')
          expect(err.waited_seconds).to eq(0.1)
        end
    end

    it 'includes the capture address in the timeout hint after ping' do
      stub_json(:get, '/v1/ping', status: 200, body: ping_body('alice'))
      stub_request(:get, %r{/v1/latest/signup})
        .to_return(status: 408, body: '{}', headers: { 'Content-Type' => 'application/json' })

      mc = new_client
      mc.ping

      expect { mc.wait_for('signup', timeout: 0.1, poll_timeout: 1) }
        .to raise_error(MailCapture::TimeoutError, /alice-signup@mailcapture\.app/)
    end

    it 'handles nil OTP and body fields' do
      cap = capture_body(otp: nil).merge('body_text' => nil, 'body_html' => nil)
      stub_request(:get, %r{#{BASE}/v1/latest/signup})
        .to_return(status: 200, body: latest_body(cap).to_json,
                   headers: { 'Content-Type' => 'application/json' })

      email = new_client.wait_for('signup', timeout: 5)

      expect(email.otp).to be_nil
      expect(email.body_text).to be_nil
      expect(email.body_html).to be_nil
    end

    it 'accepts an :after parameter and passes it in the query string' do
      after = Time.utc(2024, 6, 1)
      cap   = capture_body
      stub_request(:get, %r{/v1/latest/signup})
        .with(query: hash_including('after' => '2024-06-01T00:00:00Z'))
        .to_return(status: 200, body: latest_body(cap).to_json,
                   headers: { 'Content-Type' => 'application/json' })

      email = new_client.wait_for('signup', timeout: 5, after: after)
      expect(email.id).to eq('cap-1')
    end
  end

  # ─── list ───────────────────────────────────────────────────────────────────

  describe '#list' do
    it 'returns a CaptureList' do
      stub_json(:get, '/v1/captures', status: 200,
                body: { items: [capture_body], count: 1 })

      result = new_client.list
      expect(result).to be_a(MailCapture::CaptureList)
      expect(result.count).to eq(1)
      expect(result.items.first.subject).to eq('Test Email')
    end

    it 'sends tag and limit as query parameters' do
      stub = stub_request(:get, "#{BASE}/v1/captures")
               .with(query: { 'tag' => 'signup', 'limit' => '10' })
               .to_return(status: 200, body: { items: [], count: 0 }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

      new_client.list(tag: 'signup', limit: 10)
      expect(stub).to have_been_requested
    end
  end

  # ─── get ────────────────────────────────────────────────────────────────────

  describe '#get' do
    it 'raises ArgumentError when capture_id is empty' do
      expect { new_client.get('') }.to raise_error(ArgumentError, /capture_id/)
    end

    it 'returns a Capture' do
      stub_json(:get, '/v1/captures/cap-xyz', status: 200, body: capture_body(id: 'cap-xyz'))
      result = new_client.get('cap-xyz')
      expect(result.id).to eq('cap-xyz')
    end

    it 'raises NotFoundError on 404' do
      stub_json(:get, '/v1/captures/missing', status: 404,
                body: error_body('NOT_FOUND', 'Resource not found'))

      expect { new_client.get('missing') }
        .to raise_error(MailCapture::NotFoundError) do |err|
          expect(err.code).to eq('NOT_FOUND')
        end
    end
  end

  # ─── delete ─────────────────────────────────────────────────────────────────

  describe '#delete' do
    it 'raises ArgumentError when tag is empty' do
      expect { new_client.delete('') }.to raise_error(ArgumentError, /tag/)
    end

    it 'sends a DELETE request and returns nil' do
      stub = stub_request(:delete, "#{BASE}/v1/captures/signup")
               .to_return(status: 204)

      result = new_client.delete('signup')
      expect(result).to be_nil
      expect(stub).to have_been_requested
    end
  end

  # ─── inbox ──────────────────────────────────────────────────────────────────

  describe '#inbox' do
    it 'raises ArgumentError when tag is empty' do
      expect { new_client.inbox('') }.to raise_error(ArgumentError, /tag/)
    end

    it 'returns an Inbox with the correct tag' do
      inbox = new_client.inbox('signup')
      expect(inbox).to be_a(MailCapture::Inbox)
      expect(inbox.tag).to eq('signup')
    end

    it 'inbox#address raises before ping' do
      inbox = new_client.inbox('signup')
      expect { inbox.address }.to raise_error(RuntimeError, /ping/)
    end

    it 'inbox#clear sends DELETE' do
      stub = stub_request(:delete, "#{BASE}/v1/captures/signup")
               .to_return(status: 204)

      new_client.inbox('signup').clear
      expect(stub).to have_been_requested
    end

    it 'inbox#wait_for delegates with the correct tag' do
      cap = capture_body(tag: 'invite')
      stub_request(:get, %r{#{BASE}/v1/latest/invite})
        .to_return(status: 200, body: latest_body(cap).to_json,
                   headers: { 'Content-Type' => 'application/json' })

      email = new_client.inbox('invite').wait_for(timeout: 5)
      expect(email.tag).to eq('invite')
    end

    it 'inbox#list filters by the inbox tag' do
      stub = stub_request(:get, "#{BASE}/v1/captures")
               .with(query: { 'tag' => 'signup' })
               .to_return(status: 200, body: { items: [], count: 0 }.to_json,
                          headers: { 'Content-Type' => 'application/json' })

      new_client.inbox('signup').list
      expect(stub).to have_been_requested
    end
  end

  # ─── Network errors ──────────────────────────────────────────────────────────

  describe 'network errors' do
    it 'raises NetworkError when the server is unreachable' do
      stub_request(:get, "#{BASE}/v1/ping").to_raise(Errno::ECONNREFUSED)

      expect { new_client.ping }
        .to raise_error(MailCapture::NetworkError) do |err|
          expect(err.code).to eq('NETWORK_ERROR')
          expect(err.message).to include('mailcapture.app')
        end
    end

    it 'raises NetworkError on SocketError (bad hostname)' do
      stub_request(:get, "#{BASE}/v1/ping").to_raise(SocketError)

      expect { new_client.ping }.to raise_error(MailCapture::NetworkError)
    end
  end

  # ─── ApiError ────────────────────────────────────────────────────────────────

  describe 'unexpected API errors' do
    it 'raises ApiError on 500' do
      stub_json(:get, '/v1/ping', status: 500,
                body: { message: 'INTERNAL_ERROR', detail: 'Oops' })

      expect { new_client.ping }
        .to raise_error(MailCapture::ApiError) do |err|
          expect(err.status_code).to eq(500)
          expect(err.code).to eq('INTERNAL_ERROR')
        end
    end
  end
end
