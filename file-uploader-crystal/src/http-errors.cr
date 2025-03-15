macro http_error(status_code, message)
  env.response.content_type = "application/json"
  env.response.status_code = {{status_code}}
  error_message = {"error" => {{message}}}.to_json
  error_message
end

macro msg(message)
  env.response.content_type = "application/json"
  msg = {"message" => {{message}}}.to_json
  msg
end
