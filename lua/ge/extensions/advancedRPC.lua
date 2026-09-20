local M = {}
local model = require("advancedRPC/model")
local contextModule = require("advancedRPC/context")
local ipcModule = require("advancedRPC/ipc")
local config = model.defaults()
local revision, elapsed, nextSample, nextStatus, lastSend = 0, 0, 0, 0, -1000
local generationBase, generationEpoch = tostring({}) .. tostring(os.time()), 0
local generation = generationBase .. ":0"
local timeline = {sessionStart = os.time(), profileStart = os.time()}
local collector = contextModule.new()
local context, telemetry, preview, ipc, originals, wrappers = {}, nil, nil, nil, nil, nil
local activeTransport, lastSignature, lastLevel, activeProfile, saveError, loadError = nil, nil, nil, nil, "", ""
local nativeSent, lastTelemetryAt, alive, profileCounter = false, -100, false, 0
local urgent, contextSignature, sendError, retryAt = true, nil, "", 0
local sendTimes = {}
local path = "/settings/advanced_rpc.json"
local legacyPath = "/settings/custom_rpc.json"
local status = {state = "starting", message = "Starting AdvancedRPC", version = model.version}

local function gameAllowsPresence()
  return settings.getValue("richPresence") == true and settings.getValue("richPresenceDiscord") == true
end

local function save()
  local temp = path .. ".tmp"
  local ok, result = pcall(jsonWriteFile, temp, config, true)
  if ok and result ~= false then
    local verifyOk, contents = pcall(jsonReadFile, temp)
    if verifyOk and type(contents) == "table" and model.signature(contents) == model.signature(config) then
      local renamed, code = pcall(function() return FS:renameFile(temp, path) end)
      if renamed and code == 0 then saveError = "" return true end
    end
  end
  pcall(function() FS:removeFile(temp) end)
  saveError = "Applied for this session, but settings could not be saved. Retry saving."
  return false
end

local function snapshot()
  return {settings = model.copy(config), revision = revision, saved = saveError == "", error = saveError ~= "" and saveError or loadError}
end

function M.getSettings()
  local result = snapshot()
  result.variables, result.contexts, result.version = model.copy(model.variables), model.copy(model.contexts), model.version
  return result
end

local function announce()
  guihooks.trigger("AdvancedRPCSettings", snapshot())
end

local function commit(value)
  config, revision, loadError = value, revision + 1, ""
  lastSignature, nextSample, urgent, sendError, retryAt = nil, 0, true, "", 0
  save()
  announce()
  return snapshot()
end

local function checkRevision(request)
  if type(request) ~= "table" or request.revision ~= revision then
    local result = snapshot()
    result.conflict = true
    return result
  end
end

function M.setSettingsFromUI(request)
  local conflict = checkRevision(request)
  if conflict then return conflict end
  local ok, value, err = pcall(model.applyPatch, config, request.patch)
  if not ok or not value then return {error = ok and err or "Invalid settings patch.", revision = revision} end
  return commit(value)
end

local function newId()
  local id, exists
  repeat
    profileCounter = profileCounter + 1
    id, exists = "profile-" .. tostring(os.time()) .. "-" .. tostring(profileCounter), false
    for _, p in ipairs(config.profiles) do if p.id == id then exists = true break end end
  until not exists
  return id
end

function M.profileAction(request)
  local conflict = checkRevision(request)
  if conflict then return conflict end
  local nextConfig = model.copy(config)
  local index
  for i, p in ipairs(nextConfig.profiles) do if p.id == request.id then index = i break end end
  local selected
  if request.action == "create" or request.action == "duplicate" then
    if #nextConfig.profiles >= 50 then return {error = "The 50-profile limit has been reached."} end
    if request.action == "duplicate" and not index then return {error = "The profile no longer exists."} end
    local p = request.action == "duplicate" and model.copy(nextConfig.profiles[index]) or model.profile("new", "New profile")
    p.id = newId()
    if request.action == "duplicate" then p.name = model.truncate(p.name, 70) .. " copy" end
    nextConfig.profiles[#nextConfig.profiles + 1] = p
    selected = p.id
  elseif request.action == "delete" then
    if not index then return {error = "The profile no longer exists."} end
    if #nextConfig.profiles == 1 then return {error = "Keep at least one profile."} end
    table.remove(nextConfig.profiles, index)
    if nextConfig.selectedProfileId == request.id then nextConfig.selectedProfileId = nextConfig.profiles[1].id end
    local rules = {}
    for _, r in ipairs(nextConfig.rules) do if r.profileId ~= request.id then rules[#rules + 1] = r end end
    nextConfig.rules = rules
    selected = nextConfig.profiles[1].id
  elseif request.action == "reset" then
    if not index then return {error = "The profile no longer exists."} end
    nextConfig.profiles[index] = model.profile(request.id, nextConfig.profiles[index].name)
  elseif request.action == "move" then
    if not index or (request.direction ~= -1 and request.direction ~= 1) then return {error = "Invalid profile move."} end
    local target = math.max(1, math.min(#nextConfig.profiles, index + request.direction))
    nextConfig.profiles[index], nextConfig.profiles[target] = nextConfig.profiles[target], nextConfig.profiles[index]
  else return {error = "Unknown profile action."} end
  local valid, err = model.validate(nextConfig)
  if not valid then return {error = err} end
  local result = commit(nextConfig)
  result.selectedId = selected
  return result
end

function M.exportProfile(request)
  for _, p in ipairs(config.profiles) do
    if type(request) == "table" and p.id == request.id then return {json = jsonEncode({schemaVersion = 1, profile = p})} end
  end
  return {error = "The profile no longer exists."}
end

function M.importProfile(request)
  local conflict = checkRevision(request)
  if conflict then return conflict end
  if type(request.json) ~= "string" or #request.json > 262144 then return {error = "Import a profile JSON smaller than 256 KB."} end
  local ok, data = pcall(jsonDecode, request.json)
  if not ok or type(data) ~= "table" or data.schemaVersion ~= 1 or type(data.profile) ~= "table" then return {error = "This is not a AdvancedRPC 1.0 profile export."} end
  local nextConfig = model.copy(config)
  local p = model.copy(data.profile)
  p.id = newId()
  nextConfig.profiles[#nextConfig.profiles + 1] = p
  local valid, err = model.validate(nextConfig)
  if not valid then return {error = err} end
  local result = commit(nextConfig)
  result.selectedId = p.id
  return result
end

function M.resetDefaults(request)
  local conflict = checkRevision(request)
  if conflict then return conflict end
  return commit(model.defaults())
end

function M.retrySave()
  save()
  announce()
  return snapshot()
end

function M.onTelemetry(token, values)
  if token ~= generation or type(values) ~= "table" or values.id ~= context.vehicleId then return end
  telemetry, lastTelemetryAt, nextSample = values, elapsed, math.min(nextSample, elapsed + 0.05)
end

local function releaseTransport()
  if ipc then ipc:stop() end
  if originals and (nativeSent or activeTransport == "custom") then pcall(originals.clearActivity) end
  activeTransport, nativeSent, lastSignature, urgent, sendError, sendTimes = nil, false, nil, true, "", {}
end

local function restoreNative()
  if not originals then return end
  pcall(originals.setEnabled, gameAllowsPresence())
  if gameAllowsPresence() and util_richPresence and util_richPresence.onGameStateUpdate then pcall(util_richPresence.onGameStateUpdate, core_gamestate.state) end
end

local function intercept()
  if originals or not Discord then return end
  originals, wrappers = {}, {}
  for _, key in ipairs({"setActivity", "updateActivity", "clearActivity", "setEnabled"}) do originals[key] = Discord[key] end
  for _, key in ipairs({"setActivity", "clearActivity"}) do
    local name = key
    local original = originals[name]
    wrappers[name] = function(...)
      if not alive or not config.enabled or not gameAllowsPresence() then return original(...) end
    end
    Discord[name] = wrappers[name]
  end
  local originalEnabled = originals.setEnabled
  wrappers.setEnabled = function(enabled)
    if alive and config.enabled and config.transport == "custom" then return originalEnabled(false) end
    return originalEnabled(enabled)
  end
  Discord.setEnabled = wrappers.setEnabled
end

local function restoreHooks()
  if not originals then return end
  for name, wrapper in pairs(wrappers) do if Discord[name] == wrapper then Discord[name] = originals[name] end end
  restoreNative()
  originals, wrappers = nil, nil
end

local function connection()
  if not originals then return nil, "Discord API is not available in this game build." end
  for name, wrapper in pairs(wrappers) do
    if Discord[name] ~= wrapper then return nil, "Another extension replaced the Discord API. Disable the conflicting presence mod and reload Lua." end
  end
  if not config.enabled then return nil, "AdvancedRPC is disabled. BeamNG controls your activity." end
  if not gameAllowsPresence() then return nil, "Enable Rich Presence and Discord Rich Presence in BeamNG settings." end
  if config.transport == "custom" and config.applicationId == "" then return nil, "Enter your Discord Application ID to connect." end
  return config.transport
end

local function updateTransport()
  local desired, reason = connection()
  if desired ~= activeTransport then
    local previous = activeTransport
    releaseTransport()
    if desired then
      activeTransport = desired
      pcall(originals.clearActivity)
      pcall(originals.setEnabled, desired == "native")
      lastSend = -1000
    elseif previous then restoreNative() end
  end
  if not desired then
    status.state = config.enabled and "waiting" or "disabled"
    status.message = reason
    return
  end
  if desired == "custom" then
    if not ipc then
      local ok, driver = pcall(require, "advancedRPC/bridge")
      if not ok then status.state, status.message = "error", "AdvancedRPC Bridge could not be initialized: " .. tostring(driver) return end
      ipc = ipcModule.new(driver, jsonEncode, jsonDecode)
    end
    ipc:start(config.applicationId)
    ipc:update(elapsed)
    status.state, status.message = ipc.state, ipc.error ~= "" and ipc.error or (ipc.state == "connecting" and "Connecting to Discord..." or "Connected to Discord")
    status.acknowledged = ipc.lastAckSignature ~= nil and ipc.lastAckSignature == lastSignature
    status.lastAcknowledgedAt = ipc.lastAck and (os.time() - math.floor(elapsed - ipc.lastAck)) or nil
  else
    status.state = Discord.isWorking() and "native" or "waiting"
    if status.state == "waiting" then lastSignature, urgent = nil, true end
    status.message = status.state == "native" and "BeamNG Discord connection is available" or "Waiting for the BeamNG Discord connection"
    if sendError ~= "" then status.state, status.message = "error", sendError end
    status.acknowledged, status.lastAcknowledgedAt = false, nil
  end
end

local function sample()
  local currentTelemetry = elapsed - lastTelemetryAt < 4 and telemetry or nil
  context = collector:sample(config, currentTelemetry)
  if context.map_id ~= lastLevel then
    lastLevel, timeline.mapStart = context.map_id, context.map_id and os.time() or nil
    telemetry, lastTelemetryAt = nil, -100
  end
  local p = model.selectProfile(config, context)
  if activeProfile ~= p.id then activeProfile, timeline.profileStart = p.id, os.time() end
  local signature = model.signature({map = context.map_id, vehicle = context.vehicleId, profile = p.id, flags = context.flags, mission = context.mission, paused = context.isPaused, career = context.career_activity})
  if signature ~= contextSignature then urgent, contextSignature = true, signature end
  preview = model.build(config, context, timeline, os.time(), p)
end

function M.getPreview(request)
  if not preview then sample() end
  if type(request) == "table" and request.profileId then
    for _, p in ipairs(config.profiles) do
      if p.id == request.profileId then return model.build(config, context, timeline, os.time(), p) end
    end
  end
  return model.copy(preview)
end

function M.getStatus()
  local result = model.copy(status)
  result.transport, result.profileId, result.profileName = config.transport, preview and preview.profileId, preview and preview.profileName
  result.lastSentAt, result.saveError, result.loadError = lastSend > -1000 and os.time() - math.floor(elapsed - lastSend) or nil, saveError, loadError
  result.preview = model.copy(preview)
  result.acceptedActivity = ipc and model.copy(ipc.lastAckActivity) or nil
  return result
end

function M.reconnect()
  releaseTransport()
  if ipc then ipc = nil end
  lastSend, nextSample, retryAt = -1000, 0, 0
  return M.getStatus()
end

local nextTelemetry = 0
local function update(dtReal)
  if not alive then return end
  elapsed = elapsed + math.max(0, dtReal or 0)
  updateTransport()
  if elapsed >= nextSample then sample() nextSample = elapsed + 0.25 end
  if config.enabled and context.vehicleId and context.vehicle_model ~= "unicycle" and elapsed >= nextTelemetry then
    local vehicle = getPlayerVehicle(0)
    if vehicle and vehicle:getID() == context.vehicleId then
      vehicle:queueLuaCommand("extensions.load('advancedRPCTelemetry'); extensions.advancedRPCTelemetry.sample(" .. serialize(generation) .. ")")
    end
    nextTelemetry = elapsed + 0.25
  end
  while sendTimes[1] and elapsed - sendTimes[1] >= 20 do table.remove(sendTimes, 1) end
  local delay = urgent and 1 or config.updateInterval
  if activeTransport and preview and elapsed >= retryAt and #sendTimes < 5 and (not sendTimes[#sendTimes] or elapsed - sendTimes[#sendTimes] >= 1) and elapsed - lastSend >= delay then
    local payload = activeTransport == "native" and preview.nativeActivity or preview.activity
    local signature = model.signature(payload)
    if signature ~= lastSignature or elapsed - lastSend >= 30 then
      if activeTransport == "native" and Discord.isWorking() then
        local ok, err = pcall(function()
          if originals.setActivity(payload) == false then error("BeamNG could not set the Discord activity.") end
          if originals.updateActivity() == false then error("BeamNG could not submit the Discord activity.") end
        end)
        if ok then
          nativeSent, lastSend, lastSignature, urgent, sendError = true, elapsed, signature, false, ""
          sendTimes[#sendTimes + 1] = elapsed
        else
          sendError, retryAt = tostring(err), elapsed + 5
          status.state, status.message = "error", sendError
        end
      elseif activeTransport == "custom" and ipc then
        ipc:request(payload, signature, signature == lastSignature)
        lastSend, lastSignature, urgent = elapsed, signature, false
        sendTimes[#sendTimes + 1] = elapsed
      end
    end
  end
  if elapsed >= nextStatus then
    guihooks.trigger("AdvancedRPCStatus", M.getStatus())
    nextStatus = elapsed + 1
  end
end

function M.onUpdate(dtReal)
  local ok, err = pcall(update, dtReal)
  if not ok then
    local message = tostring(err)
    if status.message ~= message then log("E", "AdvancedRPC", message) end
    status.state, status.message = "error", message
  end
end

function M.onExtensionLoaded()
  local readPath = not FS:fileExists(path) and FS:fileExists(legacyPath) and legacyPath or path
  local ok, saved = pcall(jsonReadFile, readPath)
  if ok and saved ~= nil then
    local valid, err = model.validate(saved)
    if valid then
      config = saved
      if readPath ~= path then save() end
    else config.enabled = false loadError = "Saved settings were not loaded: " .. tostring(err) end
  elseif FS:fileExists(readPath) then config.enabled = false loadError = "Saved settings could not be read. Your file has been preserved." end
  alive = true
  intercept()
  sample()
  setExtensionUnloadMode(M, "manual")
end

function M.onExtensionUnloaded()
  alive = false
  releaseTransport()
  collector:detachBeamMP()
  restoreHooks()
  local vehicle = getPlayerVehicle(0)
  if vehicle then vehicle:queueLuaCommand("extensions.unload('advancedRPCTelemetry')") end
end

function M.onSerialize()
  return {timeline = timeline, config = config, revision = revision, activeProfile = activeProfile, lastLevel = lastLevel}
end

function M.onDeserialized(data)
  if type(data) ~= "table" then return end
  if type(data.timeline) == "table" and type(data.timeline.sessionStart) == "number" and type(data.timeline.profileStart) == "number" then timeline = data.timeline end
  if model.validate(data.config) then config = data.config revision = tonumber(data.revision) or revision end
  activeProfile, lastLevel, nextSample = data.activeProfile, data.lastLevel, 0
end

function M.onSettingsChanged() nextSample = 0 end
function M.onVehicleSwitched()
  generationEpoch = generationEpoch + 1
  generation = generationBase .. ":" .. tostring(generationEpoch)
  telemetry, lastTelemetryAt, nextSample, nextTelemetry = nil, -100, 0, 0
end
function M.onVehicleResetted()
  generationEpoch = generationEpoch + 1
  generation = generationBase .. ":" .. tostring(generationEpoch)
  collector.details, telemetry, nextSample = nil, nil, 0
end
function M.onClientStartMission() nextSample = 0 end
function M.onClientEndMission() telemetry, nextSample = nil, 0 end
function M.onGameStateUpdate() nextSample = 0 end
function M.onCareerActive() nextSample, urgent = 0, true end
M.onDeliveryModeStarted = M.onCareerActive
M.onDeliveryModeStopped = M.onCareerActive
M.onPartShoppingStarted = M.onCareerActive
M.onPartShoppingTransactionComplete = M.onCareerActive
M.onPartShoppingCancelled = M.onCareerActive
M.onAnyMissionChanged = M.onCareerActive
M.onScenarioChange = M.onCareerActive
M.onWorldReadyState = M.onCareerActive
function M.onBeamMPServerLeave() collector.playerCount, collector.playerLimit, nextSample = nil, nil, 0 end
function M.onModDeactivated(name)
  if type(name) == "table" then name = name.modname or name.name or name.filename end
  if type(name) == "string" and name:lower():find("advanced_rpc", 1, true) then extensions.unload("advancedRPC") end
end

return M
