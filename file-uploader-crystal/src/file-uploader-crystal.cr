require "http"
require "kemal"
require "yaml"
require "db"
require "sqlite3"
require "digest"

require "./logger"
require "./routing"
require "./utils"
require "./handling/**"
require "./config"
require "./jobs"
require "./lib/**"

CONFIG = Config.load
Kemal.config.port = CONFIG.port
Kemal.config.host_binding = CONFIG.host
Kemal.config.shutdown_message = false
Kemal.config.app_name = "file-uploader-crystal"
# https://github.com/iv-org/invidious/blob/90e94d4e6cc126a8b7a091d12d7a5556bfe369d5/src/invidious.cr#L136C1-L136C61
LOGGER = LogHandler.new(STDOUT, CONFIG.log_level, CONFIG.colorize_logs)
# Give me a 128 bit CPU
# MAX_FILES = 58**CONFIG.fileameLength
SQL = DB.open("sqlite3://#{CONFIG.db}")

# https://github.com/iv-org/invidious/blob/90e94d4e6cc126a8b7a091d12d7a5556bfe369d5/src/invidious.cr#L78
CURRENT_BRANCH  = {{ "#{`git branch | sed -n '/* /s///p'`.strip}" }}
CURRENT_COMMIT  = {{ "#{`git rev-list HEAD --max-count=1 --abbrev-commit`.strip}" }}
CURRENT_VERSION = {{ "#{`git log -1 --format=%ci | awk '{print $1}' | sed s/-/./g`.strip}" }}
CURRENT_TAG     = {{ "#{`git describe --long --abbrev=7 --tags | sed 's/([^-]*)-g.*/r\1/;s/-/./g'`.strip}" }}

Utils.check_dependencies
Utils.create_db
Utils.create_files_dir
Utils.create_thumbnails_dir
Routing.register_all

Utils.delete_socket
Jobs.run

{% if flag?(:release) || flag?(:production) %}
  Kemal.config.env = "production" if !ENV.has_key?("KEMAL_ENV")
{% end %}

if !CONFIG.unix_socket.nil?
  sleep 1.second
  LOGGER.info "Changing socket permissions to 777"
  begin
    File.chmod("#{CONFIG.unix_socket}", File::Permissions::All)
  rescue ex
    LOGGER.fatal "#{ex.message}"
    exit(1)
  end
end

sleep
