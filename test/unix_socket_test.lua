local unix = require("lunet.unix")
local lunet = require("lunet")
local fs = require("lunet.fs")

local cwd = io.popen("pwd"):read("*l")
local SOCKET_PATH = cwd .. "/.tmp/lunet_test.sock"

lunet.spawn(function()
  -- Clean up previous socket if exists
  os.remove(SOCKET_PATH)

  print("Testing Unix socket listen on " .. SOCKET_PATH)
  local listener, err = unix.listen(SOCKET_PATH)
  if not listener then
    print("FAIL: Failed to listen on Unix socket: " .. (err or "unknown"))
    os.exit(1)
  end
  print("PASS: Listening on Unix socket")

  -- Test connection
  lunet.spawn(function()
    print("Testing Unix socket connect...")
    print("About to connect to " .. SOCKET_PATH)
    local client, err = unix.connect(SOCKET_PATH)
    print("Connect returned: ", client, err)
    
    if not client then
      print("FAIL: Failed to connect: " .. (err or "unknown"))
      unix.close(listener)
      os.exit(1)
    end
    print("PASS: Connected to Unix socket")
    
    local werr = unix.write(client, "ping")
    if werr then
        print("FAIL: Write failed: " .. (werr or "unknown"))
        os.exit(1)
    end
    local data, rerr = unix.read(client)
    if not data then
        print("FAIL: Read failed: " .. (rerr or "unknown"))
        os.exit(1)
    end

    if data ~= "pong" then
       print("FAIL: Expected 'pong', got " .. tostring(data))
       os.exit(1)
    end
    print("PASS: Read/Write verified")
    
    unix.close(client)
    unix.close(listener)
    print("All Unix socket tests passed!")
  end)

  -- Accept loop
  while true do
    local client, err = unix.accept(listener)
    if client then
      lunet.spawn(function()
        local data = unix.read(client)
        if data == "ping" then
          unix.write(client, "pong")
        end
        unix.close(client)
      end)
    else
        break
    end
  end
end)
