module MailCapture
  # A scoped handle for a single capture inbox (tag).
  # Create one with +Client#inbox+.
  #
  # Keeps test code clean by binding the tag once:
  #
  #   inbox = mc.inbox('signup')
  #   inbox.clear
  #   MyApp.register(inbox.address)
  #   email = inbox.wait_for(timeout: 15)
  #   expect(email.otp).to match(/\A\d{6}\z/)
  class Inbox
    # @return [String] the tag this inbox is scoped to
    attr_reader :tag

    def initialize(client, tag)
      @client = client
      @tag    = tag
    end

    # The full capture email address for this inbox,
    # e.g. "alice-signup@mailcapture.app".
    #
    # Requires +ping+ to have been called first, or +:username+ set in the constructor.
    #
    # @raise [RuntimeError] if the username is not yet known
    def address
      @client.address(tag)
    end

    # Wait for an email to arrive. See {Client#wait_for}.
    def wait_for(timeout: 30, poll_timeout: 10, after: nil)
      @client.wait_for(tag, timeout: timeout, poll_timeout: poll_timeout, after: after)
    end

    # List recent captures. See {Client#list}.
    def list(limit: nil, after: nil)
      @client.list(tag: tag, limit: limit, after: after)
    end

    # Delete all captures. Call before each test for a clean starting state.
    #
    #   before(:each) { inbox.clear }
    def clear
      @client.delete(tag)
    end

    def to_s
      "#<MailCapture::Inbox tag=#{tag.inspect}>"
    end
    alias inspect to_s
  end
end
