require 'json'
require 'net/http'
require 'uri'

module MailCapture
  # MailCapture API client. Create one with {MailCapture.new} or
  # {MailCapture::Client.new} and reuse it across your test suite.
  #
  # @example Basic usage
  #   mc = MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY'])
  #   mc.ping
  #
  #   mc.delete('signup')
  #   MyApp.register(mc.address('signup'))   # "alice-signup@mailcapture.app"
  #   email = mc.wait_for('signup', timeout: 15)
  #   expect(email.otp).to eq('123456')
  #
  # @example With Inbox (recommended)
  #   inbox = mc.inbox('signup')
  #   inbox.clear
  #   MyApp.register(inbox.address)
  #   email = inbox.wait_for(timeout: 15)
  class Client
    MAX_POLL_SECONDS   = 30
    SERVER_POLL_BUFFER = 5

    ADJECTIVES = %w[
      angry bold brave calm cold cool dark dizzy dusty eager fierce fluffy
      funky fuzzy glad gloomy grumpy hasty hungry icy itchy jolly jumpy
      keen lazy lucky mad mean moody muddy noisy odd pale peppy proud quick
      quiet rowdy rusty silly sleepy sneaky spooky swift tiny tough vivid
      weird wild young
    ].freeze

    ANIMALS = %w[
      ant bear boar cat crab crow deer dove duck eel elk finch fox frog
      goat hawk hare ibis jay kiwi lamb lark lion lynx mink mole moth mule
      newt owl panda pig puma ram rat rook seal slug snail swan toad vole
      wasp wolf wren yak zebra bat bee carp
    ].freeze

    # @param api_key [String]     your MailCapture API key (+mc_...+)
    # @param base_url [String]    API base URL (override for local dev)
    # @param timeout [Numeric]    default request timeout in seconds
    # @param username [String, nil] pre-set username to skip +ping+
    def initialize(api_key:, base_url: 'https://mailcapture.app', timeout: 10, username: nil)
      raise ArgumentError,
        "MailCapture: api_key is required.\n" \
        "  MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY'])" if api_key.to_s.empty?

      unless api_key.start_with?('mc_')
        warn '[mailcapture] API key does not start with "mc_". Are you sure you copied the full key? ' \
             'Make sure you copied the full key from https://mailcapture.app/admin/api-keys'
      end

      @api_key  = api_key
      @base_url = base_url.chomp('/')
      @timeout  = timeout
      @username = username
    end

    # -------------------------------------------------------------------------
    # Public API

    # Validate your API key and return your capture address template.
    # Also caches your username so {#address} works without a network call.
    #
    # @return [PingResult]
    # @raise [AuthError] if the API key is invalid
    def ping
      data = request(:get, '/v1/ping')
      result = PingResult.from_hash(data)
      @username = result.username
      result
    end

    # Wait for an email to arrive at the given tag and return it.
    #
    # Long-polls the API — the server holds the connection open and responds
    # the instant an email arrives. No busy-waiting.
    #
    # The +after+ cursor defaults to 60 seconds ago so recent emails are
    # included but stale ones from previous runs are ignored.
    # For maximum isolation, call +delete(tag)+ before triggering the email.
    #
    # @param tag [String]
    # @param timeout [Numeric]     total seconds to wait (default 60)
    # @param poll_timeout [Integer] per-poll server timeout, max 30 (default 10)
    # @param after [Time, nil]     only captures received after this time
    # @return [Capture]
    # @raise [TimeoutError]  if no email arrives before +timeout+
    # @raise [AuthError]     if the API key is invalid
    #
    # @example
    #   email = mc.wait_for('signup', timeout: 15)
    #   expect(email.otp).to match(/\A\d{6}\z/)
    def wait_for(tag, timeout: 60, poll_timeout: 10, after: nil)
      poll_timeout = [[poll_timeout.to_i, 1].max, MAX_POLL_SECONDS].min
      deadline     = Time.now + timeout
      after      ||= Time.now - 60

      loop do
        remaining = deadline - Time.now
        break if remaining <= 0

        effective_poll = [poll_timeout, [1, remaining.ceil].max].min

        result = poll_latest(tag, effective_poll, after)
        if result
          return result[:items].first unless result[:items].empty?

          after = Time.parse(result[:next_after])
        end
        # result nil => server-side 408, loop again
      end

      hint = if @username
               "Make sure you're sending to #{@username}-#{tag}@mailcapture.app."
             else
               'Check that you\'re sending to the right address (call ping first to get your username).'
             end
      raise TimeoutError.new(tag: tag, waited_seconds: timeout, hint: hint)
    end

    # List recent captures (newest first).
    #
    # @param tag [String, nil]
    # @param limit [Integer, nil]  max results (1-100, default 25)
    # @param after [Time, nil]     only captures received after this time
    # @return [CaptureList]
    #
    # @example
    #   result = mc.list(tag: 'signup', limit: 10)
    #   result.items.each { |e| puts e.subject }
    def list(tag: nil, limit: nil, after: nil)
      params = {}
      params[:tag]   = tag                                     if tag
      params[:limit] = limit.to_s                             if limit
      params[:after] = after.utc.strftime('%Y-%m-%dT%H:%M:%SZ') if after

      CaptureList.from_hash(request(:get, '/v1/captures', params: params))
    end

    # Get a single capture by ID.
    #
    # @param capture_id [String]
    # @return [Capture]
    # @raise [NotFoundError] if the capture does not exist
    def get(capture_id)
      raise ArgumentError, 'capture_id is required' if capture_id.to_s.empty?

      Capture.from_hash(request(:get, "/v1/captures/#{encode(capture_id)}"))
    end

    # Delete all captures for a tag.
    # Call before each test to start with a clean inbox.
    #
    # @param tag [String]
    #
    # @example
    #   before(:each) { mc.delete('signup') }
    def delete(tag)
      raise ArgumentError, 'tag is required' if tag.to_s.empty?

      request(:delete, "/v1/captures/#{encode(tag)}")
      nil
    end

    # Return a scoped {Inbox} for a specific tag.
    #
    # @param tag [String]
    # @return [Inbox]
    #
    # @example
    #   inbox = mc.inbox('password-reset')
    #   inbox.clear
    #   MyApp.request_password_reset(inbox.address)
    #   email = inbox.wait_for(timeout: 10)
    def inbox(tag)
      raise ArgumentError, 'tag is required' if tag.to_s.empty?

      Inbox.new(self, tag)
    end

    # Return the capture email address for a tag.
    #
    # Requires {#ping} to have been called first, or +:username+ set in the constructor.
    #
    # @param tag [String]
    # @return [String] e.g. "alice-signup@mailcapture.app"
    # @raise [RuntimeError] if username is not yet known
    def address(tag)
      raise 'MailCapture: username is not known. Call ping first or pass username: to the constructor.' \
        unless @username

      "#{@username}-#{tag}@mailcapture.app"
    end

    # Your cached username, set after {#ping} or via the constructor.
    # @return [String, nil]
    def username
      @username
    end

    # Generate a unique, human-readable tag such as +"funky-otter-a3f2b8"+.
    # Format: +{adjective}-{animal}-{6 hex digits}+.
    # ~42 billion combinations — collision probability < 0.1% across 10 000 tags.
    # No client or network call needed.
    #
    # @return [String]
    #
    # @example
    #   tag = MailCapture::Client.generate_tag   # "funky-otter-a3f2b8"
    def self.generate_tag
      adj    = ADJECTIVES.sample
      animal = ANIMALS.sample
      suffix = format('%06x', rand(0x1000000))
      "#{adj}-#{animal}-#{suffix}"
    end

    # Instance-level shortcut so you can call +mc.generate_tag+ too.
    # @return [String]
    def generate_tag
      self.class.generate_tag
    end

    # Generate a unique tag and its capture email address.
    # Requires {#ping} to have been called first (same contract as {#address}).
    #
    # @return [GenerateResult] with +tag+ and +email+ attributes
    #
    # @example
    #   mc.ping
    #   result = mc.generate
    #   # result.tag   => "funky-otter-a3f2b8"
    #   # result.email => "alice-funky-otter-a3f2b8@mailcapture.app"
    #   MyApp.register(result.email)
    #   email = mc.wait_for(result.tag, timeout: 15)
    def generate
      tag = generate_tag
      GenerateResult.new(tag: tag, email: address(tag))
    end

    private

    # -------------------------------------------------------------------------
    # Internals

    # Long-poll /v1/latest/:tag once.
    # Returns nil on a server-side 408 (no emails yet — caller loops again).
    def poll_latest(tag, poll_timeout, after)
      params = {
        timeout: poll_timeout.to_i,
        after:   after.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      }
      path = "/v1/latest/#{encode(tag)}"

      response = send_http(:get, path, params: params,
                                        read_timeout: poll_timeout + SERVER_POLL_BUFFER)

      return nil if response.code.to_i == 408

      raise_for_status(response)

      data = JSON.parse(response.body)
      {
        items:      (data['items'] || []).map { |item| Capture.from_hash(item) },
        next_after: data['next_after']
      }
    rescue JSON::ParserError
      raise ApiError.new('Invalid JSON from API', status_code: 200, code: 'INVALID_RESPONSE')
    end

    def request(method, path, params: {})
      response = send_http(method, path, params: params, read_timeout: @timeout)
      return {} if response.code.to_i == 204

      raise_for_status(response)
      JSON.parse(response.body)
    rescue JSON::ParserError
      raise ApiError.new('Invalid JSON from API', status_code: 200, code: 'INVALID_RESPONSE')
    end

    def send_http(method, path, params: {}, read_timeout: @timeout)
      uri = URI("#{@base_url}#{path}")
      uri.query = URI.encode_www_form(params) unless params.empty?

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                          open_timeout: 10,
                                          read_timeout: read_timeout) do |http|
        req = case method
              when :get    then Net::HTTP::Get.new(uri)
              when :delete then Net::HTTP::Delete.new(uri)
              end
        req['X-API-Key'] = @api_key
        req['Accept']    = 'application/json'
        http.request(req)
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH,
           Net::OpenTimeout, SocketError => e
      raise NetworkError.new(@base_url, e)
    end

    def raise_for_status(response)
      return if response.code.to_i.between?(200, 299)

      body = parse_error_body(response.body)
      case response.code.to_i
      when 401 then raise AuthError.new(body[:detail])
      when 404 then raise NotFoundError.new(body[:detail])
      else
        raise ApiError.new(body[:detail] || body[:code],
                           status_code: response.code.to_i,
                           code: body[:code])
      end
    end

    def parse_error_body(raw)
      data = JSON.parse(raw)
      { code: data['message'], detail: data['detail'] }
    rescue JSON::ParserError
      { code: 'UNKNOWN_ERROR', detail: nil }
    end

    def encode(str)
      URI.encode_uri_component(str)
    end
  end
end
