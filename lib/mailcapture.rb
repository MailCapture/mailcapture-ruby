require 'mailcapture/version'
require 'mailcapture/errors'
require 'mailcapture/models'
require 'mailcapture/inbox'
require 'mailcapture/client'

# MailCapture — real email capture for integration tests.
#
# @example Quick start
#   mc = MailCapture.new(api_key: ENV['MAILCAPTURE_API_KEY'])
#   mc.ping
#
#   mc.delete('signup')
#   MyApp.register(mc.address('signup'))   # "alice-signup@mailcapture.app"
#   email = mc.wait_for('signup', timeout: 15)
#   email.otp  # => "123456"
#
# @example With Inbox (recommended for test suites)
#   inbox = mc.inbox('signup')
#   inbox.clear
#   MyApp.register(inbox.address)
#   email = inbox.wait_for(timeout: 15)
module MailCapture
  # Convenience constructor — equivalent to MailCapture::Client.new.
  #
  # @return [Client]
  def self.new(**kwargs)
    Client.new(**kwargs)
  end
end
