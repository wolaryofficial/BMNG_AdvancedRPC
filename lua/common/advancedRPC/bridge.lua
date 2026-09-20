local M = {}
local socket = require("socket.socket")

function M.open()
  local client, err = socket.tcp()
  if not client then return nil, tostring(err) end
  client:settimeout(0)
  local connected, connectError = client:connect("127.0.0.1", 29734)
  if not connected and connectError ~= "timeout" then
    client:close()
    return nil, "Start AdvancedRPC Bridge.exe from the mod download."
  end
  local channel = {pid = 0, closed = false, client = client, connected = connected ~= nil}
  function channel:close()
    if self.closed then return end
    self.closed = true
    self.client:close()
    self.pending = nil
  end
  function channel:write(data)
    if self.closed then return nil, "AdvancedRPC Bridge connection is closed." end
    if self.pending then return false end
    if #data > 65544 then return nil, "Discord message exceeds the IPC limit." end
    self.pending, self.offset = data, 1
    return true
  end
  function channel:poll()
    if self.closed then return nil, "AdvancedRPC Bridge connection is closed." end
    if self.closeReason then return nil, self.closeReason end
    if not self.connected then
      local ok, reason = self.client:connect("127.0.0.1", 29734)
      if ok or reason == "already connected" then self.connected = true
      elseif reason == "timeout" or reason == "Operation already in progress" then return ""
      else return nil, "Start AdvancedRPC Bridge.exe from the mod download." end
    end
    if self.pending then
      local sent, reason, partial = self.client:send(self.pending, self.offset)
      self.offset = (sent or partial or self.offset - 1) + 1
      if self.offset > #self.pending then self.pending = nil end
      if not sent and reason ~= "timeout" then return nil, "AdvancedRPC Bridge disconnected during a write." end
    end
    local data, reason, partial = self.client:receive(65536)
    if reason and reason ~= "timeout" then
      self.closeReason = "AdvancedRPC Bridge disconnected. Start it again to reconnect."
      if not partial or partial == "" then return nil, self.closeReason end
    end
    return data or partial or ""
  end
  return channel
end

return M
