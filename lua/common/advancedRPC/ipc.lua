local M = {}

local function uint(value)
  local bytes = {}
  for i = 1, 4 do bytes[i] = string.char(value % 256) value = math.floor(value / 256) end
  return table.concat(bytes)
end

local function number(data, offset)
  local a, b, c, d = data:byte(offset, offset + 3)
  return a + b * 256 + c * 65536 + d * 16777216
end

function M.frame(opcode, data)
  return uint(opcode) .. uint(#data) .. data
end

function M.new(driver, encode, decode)
  local self = {
    state = "idle", error = "", attempts = 0, nextAttempt = 0, nonce = 0,
    lastAck = nil, lastAckSignature = nil, lastSentSignature = nil, rx = "", outbox = {}, now = 0, nextRequest = 0
  }

  function self:disconnect(reason)
    if self.channel then self.channel:close() self.channel = nil end
    self.rx, self.outbox, self.inFlight = "", {}, nil
    self.lastSentSignature = nil
    self.lastAck, self.lastAckSignature, self.lastAckActivity = nil, nil, nil
    self.state, self.error = "waiting", reason or "Waiting for Discord."
    self.attempts = self.attempts + 1
    self.nextAttempt = self.now + math.min(30, 2 ^ math.min(self.attempts - 1, 5))
  end

  function self:stop()
    if self.channel then self.channel:close() self.channel = nil end
    self.state, self.error, self.applicationId = "idle", "", nil
    self.rx, self.outbox, self.inFlight, self.pending = "", {}, nil, nil
    self.lastSentSignature, self.lastAckSignature, self.lastAck = nil, nil, nil
    self.lastAckActivity = nil
    self.nextRequest = 0
  end

  function self:start(id)
    if self.applicationId == id and self.state ~= "idle" then return end
    self:stop()
    self.applicationId, self.state, self.nextAttempt, self.attempts = id, "waiting", 0, 0
  end

  function self:request(activity, signature, refresh)
    self.pending = {activity = activity, signature = signature}
    if refresh and not self.inFlight then self.lastSentSignature = nil end
  end

  function self:retry()
    self.nextAttempt, self.attempts, self.lastSentSignature = 0, 0, nil
    if self.state == "error" then self.state = "ready" end
  end

  function self:update(now)
    self.now = now
    if self.state == "idle" then return end
    if not self.channel then
      if now < self.nextAttempt then return end
      local channel, err = driver.open()
      if not channel then self:disconnect(err) return end
      self.channel, self.state, self.error = channel, "connecting", ""
      self.deadline = now + 10
      self.nextHeartbeat = now + 5
      self.outbox = {M.frame(0, encode({v = 1, client_id = self.applicationId}))}
    end
    local chunk, err = self.channel:poll()
    if chunk == nil then self:disconnect(err) return end
    self.rx = self.rx .. chunk
    if #self.rx > 131088 then self:disconnect("Discord receive buffer exceeded its limit.") return end
    local frames = 0
    while #self.rx >= 8 and frames < 32 do
      local opcode, size = number(self.rx, 1), number(self.rx, 5)
      if size > 65536 then self:disconnect("Discord sent an oversized message.") return end
      if #self.rx < size + 8 then break end
      local data = self.rx:sub(9, 8 + size)
      self.rx = self.rx:sub(9 + size)
      frames = frames + 1
      if opcode == 3 then
        if #self.outbox < 32 then self.outbox[#self.outbox + 1] = M.frame(4, data) end
      elseif opcode == 1 or opcode == 2 then
        local ok, payload = pcall(decode, data)
        if not ok or type(payload) ~= "table" then self:disconnect("Discord sent invalid JSON.") return end
        if opcode == 2 then self:disconnect(tostring(payload.message or "Discord closed the connection.")) return end
        if payload.evt == "READY" then
          self.state, self.error, self.attempts, self.inFlight = "ready", "", 0, nil
          self.lastSentSignature = nil
        elseif payload.evt == "ERROR" then
          if self.inFlight and payload.nonce == self.inFlight.nonce then
            self.error = tostring(payload.data and payload.data.message or "Discord rejected the activity.")
            self.nextRequest = now + 20
            self.lastSentSignature, self.lastAckSignature, self.lastAckActivity = nil, nil, nil
            self.state, self.inFlight = "error", nil
          elseif self.state == "connecting" then
            self:disconnect(tostring(payload.data and payload.data.message or "Discord rejected the Application ID.")) return
          end
        elseif payload.cmd == "SET_ACTIVITY" and self.inFlight and payload.nonce == self.inFlight.nonce then
          self.lastAck, self.lastAckSignature = now, self.inFlight.signature
          self.lastAckActivity = payload.data
          self.inFlight, self.state, self.error = nil, "ready", ""
        end
      elseif opcode ~= 4 then self:disconnect("Discord sent an unsupported IPC opcode.") return end
    end
    if self.state == "connecting" and now >= self.deadline then self:disconnect("Discord handshake timed out.") return end
    if self.inFlight and now >= self.inFlight.deadline then self:disconnect("Discord did not acknowledge the activity.") return end
    if now >= self.nextHeartbeat and #self.outbox < 32 then
      self.outbox[#self.outbox + 1] = M.frame(3, "advancedrpc")
      self.nextHeartbeat = now + 5
    end
    if (self.state == "ready" or self.state == "error") and now >= self.nextRequest and not self.inFlight and self.pending and self.pending.signature ~= self.lastSentSignature then
      self.nonce = self.nonce + 1
      local nonce = "advancedrpc-" .. tostring(self.nonce)
      local data = '{"cmd":"SET_ACTIVITY","nonce":' .. encode(nonce) .. ',"args":{"pid":' .. tostring(self.channel.pid)
        .. ',"activity":' .. (self.pending.activity and encode(self.pending.activity) or "null") .. '}}'
      self.outbox[#self.outbox + 1] = M.frame(1, data)
      self.lastSentSignature = self.pending.signature
      self.inFlight = {nonce = nonce, signature = self.pending.signature, deadline = now + 10}
      self.state, self.error = "ready", ""
    end
    if #self.outbox > 0 then
      local accepted, writeError = self.channel:write(self.outbox[1])
      if accepted == nil then self:disconnect(writeError) return end
      if accepted then table.remove(self.outbox, 1) end
    end
  end
  return self
end

return M
