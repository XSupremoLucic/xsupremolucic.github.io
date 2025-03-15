require "../http-errors"

module Handling::Admin
  extend self

  #   private macro json_fill(named_tuple, field_name)
  #     j.field {{field_name}}, {{named_tuple}}[:{{field_name}}]
  #   end

  # /api/admin/delete
  # curl -X POST -H "Content-Type: application/json" -H "X-Api-Key: asd" http://localhost:8080/api/admin/delete -d '{"files": ["j63"]}' | jq
  def delete_file(env)
    files = env.params.json["files"].as((Array(JSON::Any)))
    successfull_files = [] of String
    failed_files = [] of String
    files.each do |file|
      file = file.to_s
      begin
        fileinfo = SQL.query_one("SELECT filename, extension, thumbnail
        FROM files
        WHERE filename = ?",
          file,
          as: {filename: String, extension: String, thumbnail: String | Nil})

        # Delete file
        File.delete("#{CONFIG.files}/#{fileinfo[:filename]}#{fileinfo[:extension]}")
        if fileinfo[:thumbnail]
          # Delete thumbnail
          File.delete("#{CONFIG.thumbnails}/#{fileinfo[:thumbnail]}")
        end
        # Delete entry from db
        SQL.exec "DELETE FROM files WHERE filename = ?", file
        LOGGER.debug "File '#{fileinfo[:filename]}' was deleted"
        successfull_files << file
      rescue ex : DB::NoResultsError
        LOGGER.error("File '#{file}' doesn't exist or is not registered in the database: #{ex.message}")
        failed_files << file
      rescue ex
        LOGGER.error "Unknown error: #{ex.message}"
        http_error 500,"Unknown error: #{ex.message}"
      end
    end
    json = JSON.build do |j|
      j.object do
        j.field "successfull", successfull_files.size
        j.field "failed", failed_files.size
        j.field "successfullFiles", successfull_files
        j.field "failedFiles", failed_files
      end
    end
  end

  # /api/admin/deleteiplimit
  # curl -X POST -H "Content-Type: application/json" -H "X-Api-Key: asd" http://localhost:8080/api/admin/deleteiplimit -d '{"ips": ["127.0.0.1"]}' | jq

  def delete_ip_limit(env)
    data = env.params.json["ips"].as((Array(JSON::Any)))
    successfull = [] of String
    failed = [] of String
    data.each do |item|
      item = item.to_s
      begin
        # Delete entry from db
        SQL.exec "DELETE FROM ips WHERE ip = ?", item
        LOGGER.debug "Rate limit for '#{item}' was deleted"
        successfull << item
      rescue ex : DB::NoResultsError
        LOGGER.error("Rate limit for '#{item}' doesn't exist or is not registered in the database: #{ex.message}")
        failed << item
      rescue ex
        LOGGER.error "Unknown error: #{ex.message}"
        http_error 500, "Unknown error: #{ex.message}"
      end
    end
    json = JSON.build do |j|
      j.object do
        j.field "successfull", successfull.size
        j.field "failed", failed.size
        j.field "successfullUnbans", successfull
        j.field "failedUnbans", failed
      end
    end
  end

  # /api/admin/fileinfo
  # curl -X POST -H "Content-Type: application/json" -H "X-Api-Key: asd" http://localhost:8080/api/admin/fileinfo -d '{"files": ["j63"]}' | jq
  def retrieve_file_info(env)
    data = env.params.json["files"].as((Array(JSON::Any)))
    successfull = [] of NamedTuple(original_filename: String, filename: String, extension: String,
      uploaded_at: String, checksum: String, ip: String, delete_key: String,
      thumbnail: String | Nil)
    failed = [] of String
    data.each do |item|
      item = item.to_s
      begin
        fileinfo = SQL.query_one("SELECT original_filename, filename, extension,
	  uploaded_at, checksum, ip, delete_key, thumbnail
	  FROM files
	  WHERE filename = ?",
          item,
          as: {original_filename: String, filename: String, extension: String,
               uploaded_at: String, checksum: String, ip: String, delete_key: String,
               thumbnail: String | Nil})
        successfull << fileinfo
      rescue ex : DB::NoResultsError
        LOGGER.error("File '#{item}' is not registered in the database: #{ex.message}")
        failed << item
      rescue ex
        LOGGER.error "Unknown error: #{ex.message}"
        http_error 500,"Unknown error: #{ex.message}"
      end
    end
    json = JSON.build do |j|
      j.object do
        j.field "files" do
          j.array do
            successfull.each do |fileinfo|
              j.object do
                j.field fileinfo[:filename] do
                  j.object do
                    j.field "original_filename", fileinfo[:original_filename]
                    j.field "filename", fileinfo[:filename]
                    j.field "extension", fileinfo[:extension]
                    j.field "uploaded_at", fileinfo[:uploaded_at]
                    j.field "checksum", fileinfo[:checksum]
                    j.field "ip", fileinfo[:ip]
                    j.field "delete_key", fileinfo[:delete_key]
                    j.field "thumbnail", fileinfo[:thumbnail]
                  end
                end
              end
            end
          end
        end
        j.field "successfull", successfull.size
        j.field "failed", failed.size
        # j.field "successfullFiles"
        j.field "failedFiles", failed
      end
    end
  end

  # /api/admin/torexitnodes
  # curl -X GET -H "X-Api-Key: asd" http://localhost:8080/api/admin/torexitnodes | jq
  def retrieve_tor_exit_nodes(env, nodes)
    json = JSON.build do |j|
      j.object do
        j.field "ips", nodes
      end
    end
  end

  # /api/admin/whitelist
  # curl -X GET -H "X-Api-Key: asd" http://localhost:8080/api/admin/torexitnodes | jq
  #   def add_ip_to_whitelist(env, nodes)
  #     json = JSON.build do |j|
  #       j.object do
  #         j.field "ips", nodes
  #       end
  #     end
  #   end

  # /api/admin/blacklist
  # curl -X GET -H "X-Api-Key: asd" http://localhost:8080/api/admin/torexitnodes | jq
  def add_ip_to_blacklist(env, nodes)
    json = JSON.build do |j|
      j.object do
        j.field "ips", nodes
      end
    end
  end

  # MODULE END
end
