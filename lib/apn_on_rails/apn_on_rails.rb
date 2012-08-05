require 'socket'
require 'openssl'
require 'configatron'

rails_root = File.join(FileUtils.pwd, 'rails_root')
if defined?(Rails.root)
  rails_root = Rails.root.to_s
end

rails_env = 'development'
if defined?(Rails.env)
  rails_env = Rails.env
end

configatron.apn.set_default(:passphrase, '')
configatron.apn.set_default(:port, 2195)

configatron.apn.feedback.set_default(:passphrase, configatron.apn.passphrase)
configatron.apn.feedback.set_default(:port, 2196)

if rails_env == 'production'
  configatron.apn.set_default(:host, 'gateway.push.apple.com')
  configatron.apn.set_default(:cert, File.join(rails_root, 'config', 'apple_push_notification_production.pem'))

  configatron.apn.feedback.set_default(:host, 'feedback.push.apple.com')
  configatron.apn.feedback.set_default(:cert, configatron.apn.cert)
else
  configatron.apn.set_default(:host, 'gateway.sandbox.push.apple.com')
  configatron.apn.set_default(:cert, File.join(rails_root, 'config', 'apple_push_notification_development.pem'))

  configatron.apn.feedback.set_default(:host, 'feedback.sandbox.push.apple.com')
  configatron.apn.feedback.set_default(:cert, configatron.apn.cert)
end

module APN # :nodoc:

  module Errors # :nodoc:

    # Raised when a notification message to Apple is longer than 256 bytes.
    class ExceededMessageSizeError < StandardError

      def initialize(message) # :nodoc:
        super("The maximum size allowed for a notification payload is 256 bytes: '#{message}'")
      end

    end

    class MissingCertificateError < StandardError
      def initialize
        super("This app has no certificate")
      end
    end

  end # Errors

end # APN

base = File.join(File.dirname(__FILE__), 'app', 'models', 'apn', 'base.rb')
require base

Dir.glob(File.join(File.dirname(__FILE__), 'app', 'models', 'apn', '*.rb')).sort.each do |f|
  require f
end

%w{ models controllers helpers }.each do |dir|
  path = File.join(File.dirname(__FILE__), 'app', dir)
  $LOAD_PATH << path
  # puts "Adding #{path}"
  begin
    if ActiveSupport::Dependencies.respond_to? :autoload_paths
      ActiveSupport::Dependencies.autoload_paths << path
      ActiveSupport::Dependencies.autoload_once_paths.delete(path)
    else
      ActiveSupport::Dependencies.load_paths << path
      ActiveSupport::Dependencies.load_once_paths.delete(path)
    end
  rescue NameError
    Dependencies.load_paths << path
    Dependencies.load_once_paths.delete(path)
  end
end
