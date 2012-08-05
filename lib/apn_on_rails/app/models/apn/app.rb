class APN::App < APN::Base

  has_many :groups, :class_name => 'APN::Group', :dependent => :destroy
  has_many :devices, :class_name => 'APN::Device', :dependent => :destroy
  has_many :notifications, :through => :devices, :dependent => :destroy
  has_many :unsent_notifications, :through => :devices
  has_many :group_notifications, :through => :groups
  has_many :unsent_group_notifications, :through => :groups
  #has_many :unsent_apple_group_notifications, :through => :groups, :class_name => 'APN::Group', :conditions => {:name => "APPLE"}
  #has_many :unsent_android_group_notifications, :through => :groups, :class_name => 'APN::Group', :conditions => {:name => "ANDROID"}
  
  def cert
    (ENV['RAILS_ENV'] == 'production' ? apn_prod_cert : apn_dev_cert)
  end

  # Opens a connection to the Apple APN server and attempts to batch deliver
  # an Array of group notifications.
  #
  #
  # As each APN::GroupNotification is sent the <tt>sent_at</tt> column will be timestamped,
  # so as to not be sent again.
  #
  def send_notifications
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    APN::App.send_notifications_for_cert(self.cert, self.id)
  end

  def self.send_notifications
    apps = APN::App.all
    apps.each do |app|
      app.send_notifications
    end
    if !configatron.apn.cert.blank?
      global_cert = File.read(configatron.apn.cert)
      send_notifications_for_cert(global_cert, nil)
    end
  end

  def self.send_notifications_for_cert(the_cert, app_id)
    # unless self.unsent_notifications.nil? || self.unsent_notifications.empty?
      if (app_id == nil)
        conditions = "app_id is null"
      else
        conditions = ["app_id = ?", app_id]
      end
      begin
        APN::Connection.open_for_delivery({:cert => the_cert}) do |conn, sock|
          APN::Device.find_each(:conditions => conditions) do |dev|
            dev.unsent_notifications.each do |noty|
              conn.write(noty.message_for_sending)
              noty.sent_at = Time.now
              noty.save
            end
          end
        end
      rescue Exception => e
        log_connection_exception(e)
      end
    # end
  end
  
  # def reprocess_apps(start)
  #    send_daily_apple_group_notification_limit(start)
  #  end
  
  def send_daily_apple_group_notification(loops,batch_size=90)
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    begin
      group = APN::Group.find_by_name("APPLE")
      d = nil
      i = nil
      unless group.unsent_group_notifications.blank?
        gnoty = unsent_group_notifications.first
        devices = gnoty.devices.sort
        d_size = devices.size
        x = 1
        
        #outer loop to run in batches of 90
        while x < (loops + 1) 
          start = (x*batch_size) - batch_size
          puts "start is #{start}"
          finish = d_size < (x * batch_size) ? d_size : ((x * batch_size) - 1)
          puts "finish is #{finish}"
          APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock| 
            devices[start..finish].each do |device|
               begin
                 puts "pushing to device #{device.id}"
                 d = device.id
                 conn.write(gnoty.message_for_sending(device))
               rescue Exception => e
                 puts "destroying id #{d}"
                 dev = APN::Device.find_by_id(d)
                 dev.destroy if dev
               end
             end
          end
          x += 1
        end
        gnoty.sent_at = Time.now
        puts "about to save time of notification"
        gnoty.save
      end
    rescue Exception => e
      puts "error in outer block #{e.message}"
    end
  end
  
  def send_daily_apple_group_notification_limit(limit)
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    start = limit - 90
    begin
      group = APN::Group.find_by_name("APPLE")
      unless group.unsent_group_notifications.blank?
        APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
          gnoty = unsent_group_notifications.first
          gnoty.devices[start..limit-1].each do |device|
            puts "pushing to device #{device.id}"
            #return if index.to_i >= limit.to_i
            conn.write(gnoty.message_for_sending(device))
          end
          gnoty.sent_at = Time.now
          gnoty.save
        end
      end
    rescue Exception => e
      puts "before ssl read #{e.message}"
       puts "device error on id #{d}"
       d = APN::Device.find_by_id(d)
       d.destroy
       reprocess_apps
    end
  end

  def send_group_notifications
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    unless self.unsent_group_notifications.nil? || self.unsent_group_notifications.empty?
      APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
        unsent_group_notifications.each do |gnoty|
          puts "inside unsent g notif"
          gnoty.devices.find_each do |device|
            puts "device sending for #{device}"
            conn.write(gnoty.message_for_sending(device))
          end
          gnoty.sent_at = Time.now
          gnoty.save
        end
      end
    end
  end

  def send_group_notification(gnoty)
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    unless gnoty.nil?
      APN::Connection.open_for_delivery({:cert => self.cert}) do |conn, sock|
        gnoty.devices.find_each do |device|
          conn.write(gnoty.message_for_sending(device))
        end
        gnoty.sent_at = Time.now
        gnoty.save
      end
    end
  end

  def self.send_group_notifications
    apps = APN::App.all
    apps.each do |app|
      app.send_group_notifications
    end
  end

  # Retrieves a list of APN::Device instnces from Apple using
  # the <tt>devices</tt> method. It then checks to see if the
  # <tt>last_registered_at</tt> date of each APN::Device is
  # before the date that Apple says the device is no longer
  # accepting notifications then the device is deleted. Otherwise
  # it is assumed that the application has been re-installed
  # and is available for notifications.
  #
  # This can be run from the following Rake task:
  #   $ rake apn:feedback:process
  def process_devices
    if self.cert.nil?
      raise APN::Errors::MissingCertificateError.new
      return
    end
    APN::App.process_devices_for_cert(self.cert)
  end # process_devices

  def self.process_devices
    apps = APN::App.all
    apps.each do |app|
      app.process_devices
    end
    if !configatron.apn.cert.blank?
      global_cert = File.read(configatron.apn.cert)
      APN::App.process_devices_for_cert(global_cert)
    end
  end

  def self.process_devices_for_cert(the_cert)
    APN::Feedback.devices(the_cert).each do |device|
      if device.last_registered_at < device.feedback_at
        puts "device #{device.id} -> #{device.last_registered_at} < #{device.feedback_at}"
        device.destroy
      else
        puts "device #{device.id} -> #{device.last_registered_at} not < #{device.feedback_at}"
      end
    end
  end

  protected

  def self.log_connection_exception(ex)
    STDERR.puts ex.message
    raise ex
  end

end
