# Pretty cool way to write background jobs! :)
module Jobs
  def self.check_old_files
    if CONFIG.deleteFilesCheck <= 0
      LOGGER.info "File deletion is disabled"
      return
    end
    spawn do
      loop do
        Utils.check_old_files
        sleep CONFIG.deleteFilesCheck.seconds
      end
    end
  end

  def self.retrieve_tor_exit_nodes
    if !CONFIG.blockTorAddresses
      return
    end
    LOGGER.info("Blocking Tor exit nodes")
    spawn do
      loop do
        Utils.retrieve_tor_exit_nodes
        # Updates the @@exit_nodes array instantly
        Routing.reload_exit_nodes
        sleep CONFIG.torExitNodesCheck.seconds
      end
    end
  end

  def self.kemal
    spawn do
      if !CONFIG.unix_socket.nil?
        Kemal.run &.server.not_nil!.bind_unix "#{CONFIG.unix_socket}"
      else
        Kemal.run
      end
    end
  end

  def self.run
    check_old_files
    retrieve_tor_exit_nodes
    kemal
  end
end
