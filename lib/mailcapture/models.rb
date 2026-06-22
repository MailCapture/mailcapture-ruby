module MailCapture
  # Result from {Client#generate}.
  GenerateResult = Struct.new(:tag, :email, keyword_init: true) do
    def to_s
      "#<MailCapture::GenerateResult tag=#{tag.inspect} email=#{email.inspect}>"
    end
    alias inspect to_s
  end

  # A captured email.
  #
  #   email = mc.wait_for('signup')
  #   email.otp        # => "123456"
  #   email.subject    # => "Verify your account"
  #   email.latency_ms # => 145
  class Capture
    # @return [String] unique capture ID
    attr_reader :id
    # @return [String] tag portion of the address, e.g. "signup"
    attr_reader :tag
    # @return [String] email subject line
    attr_reader :subject
    # @return [String, nil] extracted OTP/code, or nil if none detected
    attr_reader :otp
    # @return [String, nil] plain-text body, or nil if not present
    attr_reader :body_text
    # @return [String, nil] HTML body, or nil if not present
    attr_reader :body_html
    # @return [Integer] send-to-capture latency in milliseconds
    attr_reader :latency_ms
    # @return [String] delivery status, e.g. "captured"
    attr_reader :status
    # @return [String] ISO 8601 timestamp of when the email was received
    attr_reader :received_at

    def self.from_hash(data)
      new(data)
    end

    def initialize(data)
      @id          = data['id']
      @tag         = data['tag']
      @subject     = data['subject']
      @otp         = data['otp']
      @body_text   = data['body_text']
      @body_html   = data['body_html']
      @latency_ms  = data['latency_ms']
      @status      = data['status']
      @received_at = data['received_at']
    end

    def to_s
      "#<MailCapture::Capture id=#{id.inspect} tag=#{tag.inspect} subject=#{subject.inspect}>"
    end
    alias inspect to_s
  end

  # Response from +list+.
  class CaptureList
    # @return [Array<Capture>]
    attr_reader :items
    # @return [Integer]
    attr_reader :count

    def self.from_hash(data)
      new(data)
    end

    def initialize(data)
      @items = (data['items'] || []).map { |item| Capture.from_hash(item) }
      @count = data['count'].to_i
    end
  end

  # Response from +ping+.
  class PingResult
    # @return [String] your unique username
    attr_reader :username
    # @return [String] template string — replace {tag} with your desired tag
    attr_reader :address_template
    # @return [String] a concrete example address
    attr_reader :example
    # @return [String]
    attr_reader :status

    def self.from_hash(data)
      new(data)
    end

    def initialize(data)
      @status           = data['status']
      @username         = data['username']
      @address_template = data['address_template']
      @example          = data['example']
    end
  end
end
