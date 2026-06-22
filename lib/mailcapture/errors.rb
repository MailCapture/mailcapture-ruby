module MailCapture
  # Base class for all MailCapture errors.
  # Check +code+ for a machine-readable error type.
  class Error < StandardError
    attr_reader :code

    def initialize(message, code:)
      super(message)
      @code = code
    end
  end

  # Raised when authentication fails — the API key is invalid, expired, or revoked.
  #
  #   rescue MailCapture::AuthError
  #     # Check your MAILCAPTURE_API_KEY environment variable.
  #   end
  class AuthError < Error
    def initialize(detail = nil)
      hint = detail ? "Server said: #{detail.inspect}." : 'Your API key was rejected.'
      super(
        "Authentication failed. #{hint} " \
        'Make sure your key is valid and has not been revoked. ' \
        'Keys look like: mc_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx. ' \
        'Find your keys at https://mailcapture.app/admin/api-keys',
        code: 'UNAUTHORIZED'
      )
    end
  end

  # Raised by +wait_for+ when no email arrives before the timeout.
  #
  #   rescue MailCapture::TimeoutError => e
  #     puts "Waited #{e.waited_seconds}s for tag: #{e.tag}"
  #   end
  class TimeoutError < Error
    # @return [String] the tag that was being waited on
    attr_reader :tag
    # @return [Numeric] seconds elapsed before giving up
    attr_reader :waited_seconds

    def initialize(tag:, waited_seconds:, hint: nil)
      @tag = tag
      @waited_seconds = waited_seconds
      message = "No email arrived for tag #{tag.inspect} within #{waited_seconds.to_i}s."
      message += " #{hint}" if hint
      super(message, code: 'TIMEOUT')
    end
  end

  # Raised when a capture is not found by ID.
  class NotFoundError < Error
    def initialize(detail = nil)
      super(
        detail || 'Capture not found. It may have expired, been deleted, or the ID is incorrect.',
        code: 'NOT_FOUND'
      )
    end
  end

  # Raised when the SDK cannot reach the MailCapture API.
  # The original exception is available via +cause+ (Ruby's built-in +cause+ on exceptions).
  class NetworkError < Error
    def initialize(base_url, original_error = nil)
      @original_error = original_error
      super(
        "Could not reach the MailCapture API at #{base_url}. " \
        'Check your network connection and firewall settings.',
        code: 'NETWORK_ERROR'
      )
    end
  end

  # Raised when the API returns an unexpected status code.
  class ApiError < Error
    # @return [Integer] HTTP status code
    attr_reader :status_code
    # @return [String, nil] human-readable detail from the server
    attr_reader :detail

    def initialize(detail, status_code:, code: 'UNKNOWN_ERROR')
      @status_code = status_code
      @detail = detail
      super("API error (#{status_code}): #{detail || code}", code: code)
    end
  end
end
