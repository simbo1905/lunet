-- Example 2: Routing with Pattern Parameters
-- Demonstrates: Route matching, URL parameter extraction
-- Pattern syntax: /api/messages/:id
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

local request_count = 0

local function json_response(status, body)
    return "HTTP/1.1 " .. status .. " OK\r\n" ..
           "Content-Type: application/json\r\n" ..
           "Content-Length: " .. #body .. "\r\n" ..
           "Connection: close\r\n\r\n" .. body
end

local function handle_messages(conn, params)
    local rows = mysql.query(conn, "SELECT id, text FROM messages ORDER BY id LIMIT 10")
    local messages = {}
    if rows then
        for i, row in ipairs(rows) do
            messages[i] = '{"id":' .. row.id .. ',"text":"' .. (row.text or "") .. '"}'
        end
    end
    return '{"messages":[' .. table.concat(messages, ",") .. ']}'
end

local function handle_message_by_id(conn, params)
    local id = tonumber(params.id) or 0
    local rows = mysql.query(conn, "SELECT id, text FROM messages WHERE id = " .. id .. " LIMIT 1")
    if rows and rows[1] then
        return '{"message":{"id":' .. rows[1].id .. ',"text":"' .. (rows[1].text or "") .. '"}}'
    end
    return '{"error":"not found"}'
end

local function handle_status(conn, params)
    return '{"status":"ok","version":"1.0"}'
end

local routes = {
    {method = "GET", pattern = "/api/messages", handler = handle_messages},
    {method = "GET", pattern = "/api/messages/:id", handler = handle_message_by_id},
    {method = "GET", pattern = "/api/status", handler = handle_status},
}

local function match_route(method, path)
    for _, route in ipairs(routes) do
        if route.method == method then
            local pattern_parts = {}
            for part in route.pattern:gmatch("[^/]+") do
                pattern_parts[#pattern_parts + 1] = part
            end

            local path_parts = {}
            for part in path:gmatch("[^/]+") do
                path_parts[#path_parts + 1] = part
            end

            if #pattern_parts == #path_parts then
                local params = {}
                local match = true
                for i, pp in ipairs(pattern_parts) do
                    if pp:sub(1, 1) == ":" then
                        params[pp:sub(2)] = path_parts[i]
                    elseif pp ~= path_parts[i] then
                        match = false
                        break
                    end
                end
                if match then
                    return route.handler, params
                end
            end
        end
    end
    return nil, nil
end

local function parse_request_line(data)
    local method, full_path = data:match("^(%S+)%s+(%S+)")
    local path = full_path and full_path:match("^([^?]+)") or full_path
    return method, path
end

local function handle_request(client, req_id)
    local data, err = socket.read(client)
    if not data then
        socket.close(client)
        return
    end

    local method, path = parse_request_line(data)
    print("[" .. req_id .. "] " .. (method or "?") .. " " .. (path or "?"))

    local handler, params = match_route(method, path)
    if not handler then
        socket.write(client, json_response(404, '{"error":"not found"}'))
        socket.close(client)
        return
    end

    local conn, db_err = mysql.open(db_config)
    if not conn then
        socket.write(client, json_response(500, '{"error":"database error"}'))
        socket.close(client)
        return
    end

    local body = handler(conn, params)
    mysql.close(conn)

    socket.write(client, json_response(200, body))
    socket.close(client)
end

lunet.spawn(function()
    local port = tonumber(os.getenv("PORT")) or 8888
    local listener, err = socket.listen("tcp", "0.0.0.0", port)
    if not listener then
        print("FATAL: Cannot listen: " .. (err or "unknown"))
        return
    end
    print("Example 2 (routing) running on http://0.0.0.0:" .. port)
    print("Routes:")
    print("  GET /api/messages")
    print("  GET /api/messages/:id")
    print("  GET /api/status")

    while true do
        local client = socket.accept(listener)
        if client then
            lunet.spawn(function()
                request_count = request_count + 1
                handle_request(client, request_count)
            end)
        end
    end
end)
