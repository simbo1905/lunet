-- Example: JSON Encoding with MySQL
-- Demonstrates: Pure Lua JSON encoding, structured API responses
--
-- Setup:
--   CREATE DATABASE IF NOT EXISTS hello;
--   USE hello;
--   CREATE TABLE messages (id INT AUTO_INCREMENT PRIMARY KEY, text VARCHAR(255));
--   INSERT INTO messages (text) VALUES ('Hello, World!'), ('Welcome to lunet');

local lunet = require("lunet")
local socket = require("lunet.socket")
local mysql = require("lunet.mysql")

local db_config = {
    host = os.getenv("DB_HOST") or "127.0.0.1",
    port = tonumber(os.getenv("DB_PORT")) or 3306,
    user = os.getenv("DB_USER") or "root",
    password = os.getenv("DB_PASSWORD") or "root",
    database = os.getenv("DB_NAME") or "hello",
    charset = "utf8mb4",
}

local function escape_string(s)
    local escapes = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
        ['\r'] = '\\r', ['\t'] = '\\t',
    }
    return s:gsub('["\\\n\r\t]', escapes)
end

local function json_encode(val)
    local t = type(val)
    if t == "nil" then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        return tostring(val)
    elseif t == "string" then
        return '"' .. escape_string(val) .. '"'
    elseif t == "table" then
        local is_array = #val > 0 or next(val) == nil
        local parts = {}
        if is_array then
            for i, v in ipairs(val) do
                parts[i] = json_encode(v)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            for k, v in pairs(val) do
                parts[#parts + 1] = '"' .. escape_string(tostring(k)) .. '":' .. json_encode(v)
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function json_response(status, data)
    local body = json_encode(data)
    return "HTTP/1.1 " .. status .. "\r\n" ..
           "Content-Type: application/json; charset=utf-8\r\n" ..
           "Content-Length: " .. #body .. "\r\n" ..
           "Connection: close\r\n\r\n" .. body
end

local function parse_request_line(data)
    local method, path = data:match("^(%S+)%s+(%S+)")
    path = path and path:match("^([^?]+)") or path
    return method, path
end

local request_count = 0

lunet.spawn(function()
    local port = tonumber(os.getenv("PORT")) or 8888
    local listener, err = socket.listen("tcp", "0.0.0.0", port)
    if not listener then
        print("FATAL: Cannot listen: " .. (err or "unknown"))
        return
    end
    print("JSON example running on http://0.0.0.0:" .. port)
    print("Routes:")
    print("  GET /messages -> list all messages as JSON")
    print("  GET /         -> hello world")

    while true do
        local client = socket.accept(listener)
        if client then
            lunet.spawn(function()
                request_count = request_count + 1

                local data = socket.read(client)
                if not data then
                    socket.close(client)
                    return
                end

                local method, path = parse_request_line(data)

                if method == "GET" and path == "/" then
                    socket.write(client, json_response("200 OK", {message = "Hello, World!"}))
                    socket.close(client)
                    return
                end

                if method == "GET" and path == "/messages" then
                    local conn = mysql.open(db_config)
                    if not conn then
                        socket.write(client, json_response("500 Internal Server Error", {error = "database error"}))
                        socket.close(client)
                        return
                    end

                    local rows = mysql.query(conn, "SELECT id, text FROM messages ORDER BY id")
                    mysql.close(conn)

                    local messages = {}
                    if rows then
                        for _, row in ipairs(rows) do
                            messages[#messages + 1] = {id = row.id, text = row.text}
                        end
                    end

                    socket.write(client, json_response("200 OK", {messages = messages, count = #messages}))
                    socket.close(client)
                    return
                end

                socket.write(client, json_response("404 Not Found", {error = "not found"}))
                socket.close(client)
            end)
        end
    end
end)
