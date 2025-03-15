module Utils
  extend self

  def create_db
    if !SQL.query_one "SELECT EXISTS (SELECT 1 FROM sqlite_schema WHERE type='table' AND name='files')
		AND EXISTS (SELECT 1 FROM sqlite_schema WHERE type='table' AND name='ips');", as: Bool
      LOGGER.info "Creating sqlite3 database at '#{CONFIG.db}'"
      begin
        SQL.exec "CREATE TABLE IF NOT EXISTS files
		(original_filename text, filename text, extension text, uploaded_at text, checksum text, ip text, delete_key text, thumbnail text)"
        SQL.exec "CREATE TABLE IF NOT EXISTS ips
		(ip text UNIQUE, count integer DEFAULT 0, date integer)"
      rescue ex
        LOGGER.fatal "#{ex.message}"
        exit(1)
      end
    end
  end

  def create_files_dir
    if !Dir.exists?("#{CONFIG.files}")
      LOGGER.info "Creating files folder under '#{CONFIG.files}'"
      begin
        Dir.mkdir("#{CONFIG.files}")
      rescue ex
        LOGGER.fatal "#{ex.message}"
        exit(1)
      end
    end
  end

  def create_thumbnails_dir
    if CONFIG.thumbnails
      if !Dir.exists?("#{CONFIG.thumbnails}")
        LOGGER.info "Creating thumbnails folder under '#{CONFIG.thumbnails}'"
        begin
          Dir.mkdir("#{CONFIG.thumbnails}")
        rescue ex
          LOGGER.fatal "#{ex.message}"
          exit(1)
        end
      end
    end
  end

  def check_old_files
    LOGGER.info "Deleting old files"
    fileinfo = SQL.query_all("SELECT filename, extension, thumbnail
    FROM files
    WHERE uploaded_at < datetime('now', '-#{CONFIG.deleteFilesAfter} days')",
      as: {filename: String, extension: String, thumbnail: String | Nil})

    fileinfo.each do |file|
      LOGGER.debug "Deleting file '#{file[:filename]}#{file[:extension]}'"
      begin
        File.delete("#{CONFIG.files}/#{file[:filename]}#{file[:extension]}")
        if file[:thumbnail]
          File.delete("#{CONFIG.thumbnails}/#{file[:thumbnail]}")
        end
        SQL.exec "DELETE FROM files WHERE filename = ?", file[:filename]
      rescue ex
        LOGGER.error "#{ex.message}"
        # Also delete the file entry from the DB if it doesn't exist.
        SQL.exec "DELETE FROM files WHERE filename = ?", file[:filename]
      end
    end
  end

  def check_dependencies
    dependencies = ["ffmpeg"]
    dependencies.each do |dep|
      next if !CONFIG.generateThumbnails
      if !Process.find_executable(dep)
        LOGGER.fatal("'#{dep}' was not found.")
        exit(1)
      end
    end
  end

  # TODO:
  # def check_duplicate(upload)
  #   file_checksum = SQL.query_all("SELECT checksum FROM files WHERE original_filename = ?", upload.filename, as:String).try &.[0]?
  #   if file_checksum.nil?
  #     return
  #   else
  #     uploaded_file_checksum = hash_io(upload.body)
  #     pp file_checksum
  #     pp uploaded_file_checksum
  #     if file_checksum == uploaded_file_checksum
  #       puts "Dupl"
  #     end
  #   end
  # end

  def hash_file(file_path : String) : String
    Digest::SHA1.hexdigest &.file(file_path)
  end

  def hash_io(file_path : IO) : String
    Digest::SHA1.hexdigest &.update(file_path)
  end

  # TODO: Check if there are no other possibilities to get a random filename and exit
  def generate_filename
    filename = Random.base58(CONFIG.fileameLength)

    loop do
      if SQL.query_one("SELECT COUNT(filename) FROM files WHERE filename = ?", filename, as: Int32) == 0
        return filename
      else
        LOGGER.debug "Filename collision! Generating a new filename"
        filename = Random.base58(CONFIG.fileameLength)
      end
    end
  end

  def generate_thumbnail(filename, extension)
    exts = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp", ".heic", ".jxl", ".avif", ".crw", ".dng",
            ".mp4", ".mkv", ".webm", ".avi", ".wmv", ".flv", "m4v", ".mov", ".amv", ".3gp", ".mpg", ".mpeg", ".yuv"]
	# To prevent thumbnail generation on non image extensions
    return if exts.none? do |ext|
      extension.downcase.includes?(ext)
    end
    # Disable generation if false
    return if !CONFIG.generateThumbnails || !CONFIG.thumbnails
    LOGGER.debug "Generating thumbnail for #{filename + extension} in background"
    process = Process.run("ffmpeg",
      [
        "-hide_banner",
        "-i",
        "#{CONFIG.files}/#{filename + extension}",
        "-movflags", "faststart",
        "-f", "mjpeg",
        "-q:v", "2",
        "-vf", "scale='min(350,iw)':'min(350,ih)':force_original_aspect_ratio=decrease, thumbnail=100",
        "-frames:v", "1",
        "-update", "1",
        "#{CONFIG.thumbnails}/#{filename}.jpg",
      ])
    if process.exit_code == 0
      LOGGER.debug "Thumbnail for #{filename + extension} generated successfully"
      SQL.exec "UPDATE files SET thumbnail = ? WHERE filename = ?", filename + ".jpg", filename
    else
      # TODO: Add some sort of message when the thumbnail is not generated
    end
  end

  # Delete socket if the server has not been previously cleaned by the server
  # (Due to unclean exits, crashes, etc.)
  def delete_socket
    if File.exists?("#{CONFIG.unix_socket}")
      LOGGER.info "Deleting old unix socket"
      begin
        File.delete("#{CONFIG.unix_socket}")
      rescue ex
        LOGGER.fatal "#{ex.message}"
        exit(1)
      end
    end
  end

  def delete_file(env)
    fileinfo = SQL.query_all("SELECT filename, extension, thumbnail
        FROM #{CONFIG.dbTableName}
        WHERE delete_key = ?",
      env.params.query["key"],
      as: {filename: String, extension: String, thumbnail: String | Nil})[0]

    # Delete file
    File.delete("#{CONFIG.files}/#{fileinfo[:filename]}#{fileinfo[:extension]}")
    if fileinfo[:thumbnail]
      File.delete("#{CONFIG.thumbnails}/#{fileinfo[:thumbnail]}")
    end
    # Delete entry from db
    SQL.exec "DELETE FROM files WHERE delete_key = ?", env.params.query["key"]

    LOGGER.debug "File '#{fileinfo[:filename]}' was deleted using key '#{env.params.query["key"]}'}"
    msg("File '#{fileinfo[:filename]}' deleted successfully")
  end

  MAGIC_BYTES = {
    # Images
    ".png"  => "89504e470d0a1a0a",
    ".heic" => "6674797068656963",
    ".jpg"  => "ffd8ff",
    ".gif"  => "474946383",
    # Videos
    ".mp4"  => "66747970",
    ".webm" => "1a45dfa3",
    ".mov"  => "6d6f6f76",
    ".wmv"  => "󠀀3026b2758e66cf11",
    ".flv"  => "󠀀464c5601",
    ".mpeg" => "000001bx",
    # Audio
    ".mp3"  => "󠀀494433",
    ".aac"  => "󠀀fff1",
    ".wav"  => "󠀀57415645666d7420",
    ".flac" => "󠀀664c614300000022",
    ".ogg"  => "󠀀4f67675300020000000000000000",
    ".wma"  => "󠀀3026b2758e66cf11a6d900aa0062ce6c",
    ".aiff" => "󠀀464f524d00",
    # Whatever
    ".7z"  => "377abcaf271c",
    ".gz"  => "1f8b",
    ".iso" => "󠀀4344303031",
    # Documents
    "pdf"  => "󠀀25504446",
    "html" => "<!DOCTYPE html>",
  }

  def detect_extension(file) : String
    file = File.open(file)
    slice = Bytes.new(16)
    hex = IO::Hexdump.new(file)
    # Reads the first 16 bytes of the file in Heap
    hex.read(slice)
    MAGIC_BYTES.each do |ext, mb|
      if slice.hexstring.includes?(mb)
        return ext
      end
    end
    ""
  end

  def retrieve_tor_exit_nodes
    LOGGER.debug "Retrieving Tor exit nodes list"
    HTTP::Client.get(CONFIG.torExitNodesUrl) do |res|
      begin
        if res.success? && res.status_code == 200
          begin
            File.open(CONFIG.torExitNodesFile, "w") { |output| IO.copy(res.body_io, output) }
          rescue ex
            LOGGER.error "Failed to save exit nodes list: #{ex.message}"
          end
        else
          LOGGER.error "Failed to retrieve exit nodes list. Status Code: #{res.status_code}"
        end
      rescue ex : Socket::ConnectError
        LOGGER.error "Failed to connect to #{CONFIG.torExitNodesUrl}: #{ex.message}"
      rescue ex
        LOGGER.error "Unknown error: #{ex.message}"
      end
    end
  end

  def load_tor_exit_nodes
    exit_nodes = File.read_lines(CONFIG.torExitNodesFile)
    ips = [] of String
    exit_nodes.each do |line|
      if line.includes?("ExitAddress")
        ips << line.split(" ")[1]
      end
    end
    return ips
  end

  def ip_address(env) : String
    begin
      return env.request.headers.try &.["X-Forwarded-For"]
    rescue
      return env.request.remote_address.to_s.split(":").first
    end
  end

  def protocol(env) : String
    begin
      return env.request.headers.try &.["X-Forwarded-Proto"]
    rescue
      return "http"
    end
  end

  def host(env) : String
    begin
      return env.request.headers.try &.["X-Forwarded-Host"]
    rescue
      return env.request.headers["Host"]
    end
  end
end
