require "../http-errors"
require "http/client"
require "benchmark"

# require "../filters"

module Handling
  extend self

  def upload(env)
    env.response.content_type = "application/json"
    ip_address = Utils.ip_address(env)
    protocol = Utils.protocol(env)
    host = Utils.host(env)
    # filter = env.params.query["filter"]?
    # You can modify this if you want to allow files smaller than 1MiB.
    # This is generally a good way to check the filesize but there is a better way to do it
    # which is inspecting the file directly (If I'm not wrong).
    if CONFIG.size_limit > 0
      if env.request.headers["Content-Length"].to_i > 1048576*CONFIG.size_limit
        return http_error 413, "File is too big. The maximum size allowed is #{CONFIG.size_limit}MiB"
      end
    end
    filename = ""
    extension = ""
    original_filename = ""
    uploaded_at = ""
    checksum = ""
    if CONFIG.deleteKeyLength > 0
      delete_key = Random.base58(CONFIG.deleteKeyLength)
    end
    # TODO: Return the file that matches a checksum inside the database
    HTTP::FormData.parse(env.request) do |upload|
      if upload.filename.nil? || upload.filename.to_s.empty?
        LOGGER.debug "No file provided by the user"
        return http_error 403, "No file provided"
      end
      # TODO: upload.body is emptied when is copied or read
      # Utils.check_duplicate(upload.dup)
      extension = File.extname("#{upload.filename}")
      if CONFIG.blockedExtensions.includes?(extension.split(".")[1])
        return http_error 401, "Extension '#{extension}' is not allowed"
      end
      filename = Utils.generate_filename
      file_path = "#{CONFIG.files}/#{filename}#{extension}"
      File.open(file_path, "w") do |output|
        IO.copy(upload.body, output)
      end
      original_filename = upload.filename
      uploaded_at = Time.utc
      checksum = Utils.hash_file(file_path)
      # TODO: Apply filters
      # if filter
      #   Filters.apply_filter(file_path, filter)
      # end
    end
    # X-Forwarded-For if behind a reverse proxy and the header is set in the reverse
    # proxy configuration.
    begin
      spawn { Utils.generate_thumbnail(filename, extension) }
    rescue ex
      LOGGER.error "An error ocurred when trying to generate a thumbnail: #{ex.message}"
    end
    begin
      # Insert SQL data just before returning the upload information
      SQL.exec "INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        original_filename, filename, extension, uploaded_at, checksum, ip_address, delete_key, nil
      SQL.exec "INSERT OR IGNORE INTO ips (ip, date) VALUES (?, ?)", ip_address, Time.utc.to_unix
      # SQL.exec "INSERT OR IGNORE INTO ips (ip) VALUES ('#{ip_address}')"
      SQL.exec "UPDATE ips SET count = count + 1 WHERE ip = ('#{ip_address}')"
    rescue ex
      LOGGER.error "An error ocurred when trying to insert the data into the DB: #{ex.message}"
      return http_error 500, "An error ocurred when trying to insert the data into the DB"
    end
    json = JSON.build do |j|
      j.object do
        j.field "link", "#{protocol}://#{host}/#{filename}"
        j.field "linkExt", "#{protocol}://#{host}/#{filename}#{extension}"
        j.field "id", filename
        j.field "ext", extension
        j.field "name", original_filename
        j.field "checksum", checksum
        if CONFIG.deleteKeyLength > 0
          j.field "deleteKey", delete_key
          j.field "deleteLink", "#{protocol}://#{host}/delete?key=#{delete_key}"
        end
      end
    end
    json
  end

  # The most unoptimized and unstable feature lol
  def upload_url_bulk(env)
    env.response.content_type = "application/json"
    ip_address = Utils.ip_address(env)
    protocol = Utils.protocol(env)
    host = Utils.host(env)
    begin
      files = env.params.json["files"].as((Array(JSON::Any)))
    rescue ex : JSON::ParseException
      LOGGER.error "Body malformed: #{ex.message}"
      return http_error 400, "Body malformed: #{ex.message}"
    rescue ex
      LOGGER.error "Unknown error: #{ex.message}"
      return http_error 500, "Unknown error"
    end
    successfull_files = [] of NamedTuple(filename: String, extension: String, original_filename: String, checksum: String, delete_key: String | Nil)
    failed_files = [] of String
    # X-Forwarded-For if behind a reverse proxy and the header is set in the reverse
    # proxy configuration.
    files.each do |url|
      url = url.to_s
      filename = Utils.generate_filename
      original_filename = ""
      extension = ""
      checksum = ""
      uploaded_at = Time.utc
      extension = File.extname(URI.parse(url).path)
      if CONFIG.deleteKeyLength > 0
        delete_key = Random.base58(CONFIG.deleteKeyLength)
      end
      file_path = "#{CONFIG.files}/#{filename}#{extension}"
      File.open(file_path, "w") do |output|
        begin
          HTTP::Client.get(url) do |res|
            IO.copy(res.body_io, output)
          end
        rescue ex
          LOGGER.debug "Failed to download file '#{url}': #{ex.message}"
          return http_error 403, "Failed to download file '#{url}'"
          failed_files << url
        end
      end
      #   successfull_files << url
      # end
      if extension.empty?
        extension = Utils.detect_extension(file_path)
        File.rename(file_path, file_path + extension)
        file_path = "#{CONFIG.files}/#{filename}#{extension}"
      end
      # The second one is faster and it uses less memory
      # original_filename = URI.parse("https://ayaya.beauty/PqC").path.split("/").last
      original_filename = url.split("/").last
      checksum = Utils.hash_file(file_path)
      begin
        spawn { Utils.generate_thumbnail(filename, extension) }
      rescue ex
        LOGGER.error "An error ocurred when trying to generate a thumbnail: #{ex.message}"
      end
      begin
        # Insert SQL data just before returning the upload information
        SQL.exec("INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          original_filename, filename, extension, uploaded_at, checksum, ip_address, delete_key, nil)
        successfull_files << {filename:          filename,
                              original_filename: original_filename,
                              extension:         extension,
                              delete_key:        delete_key,
                              checksum:          checksum}
      rescue ex
        LOGGER.error "An error ocurred when trying to insert the data into the DB: #{ex.message}"
        return http_error 500, "An error ocurred when trying to insert the data into the DB"
      end
    end
    json = JSON.build do |j|
      j.array do
        successfull_files.each do |fileinfo|
          j.object do
            j.field "link", "#{protocol}://#{host}/#{fileinfo[:filename]}"
            j.field "linkExt", "#{protocol}://#{host}/#{fileinfo[:filename]}#{fileinfo[:extension]}"
            j.field "id", fileinfo[:filename]
            j.field "ext", fileinfo[:extension]
            j.field "name", fileinfo[:original_filename]
            j.field "checksum", fileinfo[:checksum]
            if CONFIG.deleteKeyLength > 0
              delete_key = Random.base58(CONFIG.deleteKeyLength)
              j.field "deleteKey", fileinfo[:delete_key]
              j.field "deleteLink", "#{protocol}://#{host}/delete?key=#{fileinfo[:delete_key]}"
            end
          end
        end
      end
    end
    json
  end

  def upload_url(env)
    env.response.content_type = "application/json"
    ip_address = Utils.ip_address(env)
    protocol = Utils.protocol(env)
    host = Utils.host(env)
    url = env.params.query["url"]
    successfull_files = [] of NamedTuple(filename: String, extension: String, original_filename: String, checksum: String, delete_key: String | Nil)
    failed_files = [] of String
    # X-Forwarded-For if behind a reverse proxy and the header is set in the reverse
    # proxy configuration.
    filename = Utils.generate_filename
    original_filename = ""
    extension = ""
    checksum = ""
    uploaded_at = Time.utc
    extension = File.extname(URI.parse(url).path)
    if CONFIG.deleteKeyLength > 0
      delete_key = Random.base58(CONFIG.deleteKeyLength)
    end
    file_path = "#{CONFIG.files}/#{filename}#{extension}"
    File.open(file_path, "w") do |output|
      begin
        # TODO: Connect timeout to prevent possible Denial of Service to the external website spamming requests
        # https://crystal-lang.org/api/1.13.2/HTTP/Client.html#connect_timeout
        HTTP::Client.get(url) do |res|
          IO.copy(res.body_io, output)
        end
      rescue ex
        LOGGER.debug "Failed to download file '#{url}': #{ex.message}"
        return http_error 403, "Failed to download file '#{url}': #{ex.message}"
        failed_files << url
      end
    end
    if extension.empty?
      extension = Utils.detect_extension(file_path)
      File.rename(file_path, file_path + extension)
      file_path = "#{CONFIG.files}/#{filename}#{extension}"
    end
    # The second one is faster and it uses less memory
    # original_filename = URI.parse("https://ayaya.beauty/PqC").path.split("/").last
    original_filename = url.split("/").last
    checksum = Utils.hash_file(file_path)
    begin
      spawn { Utils.generate_thumbnail(filename, extension) }
    rescue ex
      LOGGER.error "An error ocurred when trying to generate a thumbnail: #{ex.message}"
    end
    begin
      # Insert SQL data just before returning the upload information
      SQL.exec("INSERT INTO files VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        original_filename, filename, extension, uploaded_at, checksum, ip_address, delete_key, nil)
      successfull_files << {filename:          filename,
                            original_filename: original_filename,
                            extension:         extension,
                            delete_key:        delete_key,
                            checksum:          checksum}
    rescue ex
      LOGGER.error "An error ocurred when trying to insert the data into the DB: #{ex.message}"
      return http_error 500, "An error ocurred when trying to insert the data into the DB"
    end
    json = JSON.build do |j|
      j.array do
        successfull_files.each do |fileinfo|
          j.object do
            j.field "link", "#{protocol}://#{host}/#{fileinfo[:filename]}"
            j.field "linkExt", "#{protocol}://#{host}/#{fileinfo[:filename]}#{fileinfo[:extension]}"
            j.field "id", fileinfo[:filename]
            j.field "ext", fileinfo[:extension]
            j.field "name", fileinfo[:original_filename]
            j.field "checksum", fileinfo[:checksum]
            if CONFIG.deleteKeyLength > 0
              delete_key = Random.base58(CONFIG.deleteKeyLength)
              j.field "deleteKey", fileinfo[:delete_key]
              j.field "deleteLink", "#{protocol}://#{host}/delete?key=#{fileinfo[:delete_key]}"
            end
          end
        end
      end
    end
    json
  end

  def retrieve_file(env)
    protocol = Utils.protocol(env)
    host = Utils.host(env)
    begin
      fileinfo = SQL.query_one?("SELECT filename, original_filename, uploaded_at, extension, checksum, thumbnail
      FROM files
      WHERE filename = ?",
        env.params.url["filename"].split(".").first,
        as: {filename: String, ofilename: String, up_at: String, ext: String, checksum: String, thumbnail: String | Nil})
      if fileinfo.nil?
        # TODO: Switch this to 404, if I use 404, it will use the kemal error page (ANOYING!)
        return http_error 418, "File '#{env.params.url["filename"]}' does not exist"
      end
    rescue ex
      LOGGER.debug "Error when retrieving file '#{env.params.url["filename"]}': #{ex.message}"
      return http_error 500, "Error when retrieving file '#{env.params.url["filename"]}'"
    end
    env.response.headers["Content-Disposition"] = "inline; filename*=UTF-8''#{fileinfo[:ofilename]}"
    # env.response.headers["Last-Modified"] = "#{fileinfo[:up_at]}"
    env.response.headers["ETag"] = "#{fileinfo[:checksum]}"

    CONFIG.opengraphUseragents.each do |useragent|
      if env.request.headers.try &.["User-Agent"].includes?(useragent)
        env.response.content_type = "text/html"
        return %(
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta property="og:title" content="#{fileinfo[:ofilename]}">
    <meta property="og:url" content="#{protocol}://#{host}/#{fileinfo[:filename]}">
    #{if fileinfo[:thumbnail]
        %(<meta property="og:image" content="#{protocol}://#{host}/thumbnail/#{fileinfo[:filename]}.jpg">)
      end}
</head>
</html>
)
      end
    end
    send_file env, "#{CONFIG.files}/#{fileinfo[:filename]}#{fileinfo[:ext]}"
  end

  def retrieve_thumbnail(env)
    begin
      send_file env, "#{CONFIG.thumbnails}/#{env.params.url["thumbnail"]}"
    rescue ex
      LOGGER.debug "Thumbnail '#{env.params.url["thumbnail"]}' does not exist: #{ex.message}"
      return http_error 403, "Thumbnail '#{env.params.url["thumbnail"]}' does not exist"
    end
  end

  def stats(env)
    env.response.content_type = "application/json"
    begin
      json_data = JSON.build do |json|
        json.object do
          json.field "stats" do
            json.object do
              json.field "filesHosted", SQL.query_one? "SELECT COUNT (filename) FROM files", as: Int32
              json.field "maxUploadSize", CONFIG.size_limit
              json.field "thumbnailGeneration", CONFIG.generateThumbnails
              json.field "filenameLength", CONFIG.fileameLength
              json.field "alternativeDomains", CONFIG.alternativeDomains
            end
          end
        end
      end
    rescue ex
      LOGGER.error "Unknown error: #{ex.message}"
      return http_error 500, "Unknown error"
    end
    json_data
  end

  def delete_file(env)
    if SQL.query_one "SELECT EXISTS(SELECT 1 FROM files WHERE delete_key = ?)", env.params.query["key"], as: Bool
      begin
        fileinfo = SQL.query_all("SELECT filename, extension, thumbnail
        FROM files
        WHERE delete_key = ?",
          env.params.query["key"],
          as: {filename: String, extension: String, thumbnail: String | Nil})[0]

        # Delete file
        File.delete("#{CONFIG.files}/#{fileinfo[:filename]}#{fileinfo[:extension]}")
        if fileinfo[:thumbnail]
          # Delete thumbnail
          File.delete("#{CONFIG.thumbnails}/#{fileinfo[:thumbnail]}")
        end
        # Delete entry from db
        SQL.exec "DELETE FROM files WHERE delete_key = ?", env.params.query["key"]
        LOGGER.debug "File '#{fileinfo[:filename]}' was deleted using key '#{env.params.query["key"]}'}"
        return msg("File '#{fileinfo[:filename]}' deleted successfully")
      rescue ex
        LOGGER.error("Unknown error: #{ex.message}")
        return http_error 500, "Unknown error"
      end
    else
      LOGGER.debug "Key '#{env.params.query["key"]}' does not exist"
      return http_error 401, "Delete key '#{env.params.query["key"]}' does not exist. No files were deleted"
    end
  end

  def sharex_config(env)
    host = Utils.host(env)
    protocol = Utils.protocol(env)
    env.response.content_type = "application/json"
    # So it's able to download the file instead of displaying it
    env.response.headers["Content-Disposition"] = "attachment; filename=\"#{host}.sxcu\""
    return %({
  "Version": "14.0.1",
  "DestinationType": "ImageUploader, FileUploader",
  "RequestMethod": "POST",
  "RequestURL": "#{protocol}://#{host}/upload",
  "Body": "MultipartFormData",
  "FileFormName": "file",
  "URL": "{json:link}",
  "DeletionURL": "{json:deleteLink}",
  "ErrorMessage": "{json:error}"
})
  end

  def chatterino_config(env)
    host = Utils.host(env)
    protocol = Utils.protocol(env)
    env.response.content_type = "application/json"
    return %({
	"requestUrl": "#{protocol}://#{host}/upload",
	"formField": "data",
	"imageLink": "{link}",
	"deleteLink": "{deleteLink}"
  })
  end
end
