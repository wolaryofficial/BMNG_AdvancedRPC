local M = {version = "1.0.0", schemaVersion = 1}

M.variables = {
  activity = "Context-aware activity description", location = "Map or menu description",
  map = "Map name", map_id = "Map identifier", map_asset = "BeamNG map asset key",
  vehicle = "Vehicle brand and name", vehicle_model = "Vehicle model identifier",
  vehicle_config = "Vehicle configuration", mode = "Game mode", mission = "Mission or scenario",
  speed = "Speed with selected units", speed_kmh = "Speed in km/h", speed_mph = "Speed in mph",
  rpm = "Engine RPM", gear = "Gear", fuel = "Fuel percentage", engine = "Engine state",
  time_of_day = "In-game time", session_time = "Session duration", map_time = "Time on this map",
  server = "BeamMP server name", players = "Connected players", max_players = "Server player limit",
  paused = "Simulation pause state", career_activity = "Current career activity",
  career_money = "Career balance", career_beamxp = "Career BeamXP", career_level = "Career BeamXP level",
  career_profile = "Career profile name"
}
M.contexts = {"any", "menu", "loading", "freeroam", "career", "career_delivery", "career_mission", "career_shopping", "career_tutorial", "career_walking", "career_garage", "mission", "scenario", "editor", "photo", "replay", "walking", "beammp"}
local profileFields = {
  name = true, details = true, state = true, activityName = true, activityType = true, statusDisplay = true,
  largeImage = true, largeText = true, smallImage = true, smallText = true,
  detailsUrl = true, stateUrl = true, largeUrl = true, smallUrl = true,
  timerMode = true, countdownSeconds = true, rotationEnabled = true, rotationSeconds = true,
  detailsVariants = true, stateVariants = true, mapImages = true, vehicleImages = true, buttons = true
}
M.generalFields = {enabled = true, transport = true, applicationId = true, updateInterval = true, units = true, automatic = true, selectedProfileId = true}

function M.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, item in pairs(value) do result[key] = M.copy(item) end
  return result
end

function M.profile(id, name)
  return {
    id = id, name = name or "New profile", details = "{activity}", state = "{location}",
    activityName = "", activityType = 0, statusDisplay = 0,
    largeImage = "{map_asset}", largeText = "{map|BeamNG.drive}", smallImage = "", smallText = "{vehicle|BeamNG.drive}",
    detailsUrl = "", stateUrl = "", largeUrl = "", smallUrl = "",
    timerMode = "session", countdownSeconds = 3600, rotationEnabled = false, rotationSeconds = 30,
    detailsVariants = {}, stateVariants = {}, mapImages = {}, vehicleImages = {}, buttons = {}
  }
end

function M.defaults()
  local a = M.profile("automatic", "Automatic")
  local b = M.profile("minimal", "Minimal")
  b.details, b.state, b.smallText, b.timerMode = "{mode}", "{map|Main menu}", "", "hidden"
  local c = M.profile("telemetry", "Telemetry")
  c.details, c.state = "{vehicle|Exploring BeamNG.drive}", "{speed} | {rpm} RPM | Gear {gear}"
  return {
    schemaVersion = 1, enabled = true, transport = "native", applicationId = "", updateInterval = 5,
    units = "game", automatic = true, selectedProfileId = "automatic", profiles = {a, b, c}, rules = {}
  }
end

local function enum(value, choices)
  for _, choice in ipairs(choices) do if value == choice then return true end end
  return false
end

local function finite(value)
  return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function array(value, limit)
  if type(value) ~= "table" or #value > limit then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #value then return false end
    count = count + 1
  end
  return count == #value
end

function M.validUrl(value, template)
  if value == "" then return true end
  if type(value) ~= "string" or #value > 512 or value:find("[%s%z\1-\31\127]") then return false end
  if template and value:find("{[%w_]+[^}]*}") then return value:match("^https://") ~= nil end
  local host = value:match("^https://([^/%?#]+)")
  return host ~= nil and not host:find("@", 1, true) and not host:find("\\", 1, true)
end

local function validImage(value)
  if value == "" then return true end
  if type(value) ~= "string" or #value > 512 then return false end
  if value:match("^https://") then return M.validUrl(value, true) end
  return not value:find("[%s%z\1-\31\127]") and not value:find(":", 1, true)
end

function M.validate(config)
  if type(config) ~= "table" or config.schemaVersion ~= 1 then return false, "Unsupported settings format." end
  for _, key in ipairs({"enabled", "automatic"}) do if type(config[key]) ~= "boolean" then return false, "Invalid " .. key .. "." end end
  if not enum(config.transport, {"native", "custom"}) then return false, "Invalid connection mode." end
  if not enum(config.units, {"game", "metric", "imperial"}) then return false, "Invalid units." end
  if type(config.applicationId) ~= "string" or (config.applicationId ~= "" and (not config.applicationId:match("^%d+$") or #config.applicationId < 17 or #config.applicationId > 20)) then
    return false, "Application ID must contain 17 to 20 digits."
  end
  if not finite(config.updateInterval) or config.updateInterval < 1 or config.updateInterval > 60 then return false, "Update interval must be 1 to 60 seconds." end
  if not array(config.profiles, 50) or #config.profiles == 0 then return false, "Keep between 1 and 50 profiles." end
  local ids = {}
  for _, p in ipairs(config.profiles) do
    if type(p) ~= "table" or type(p.id) ~= "string" or not p.id:match("^[%w_-]+$") or #p.id > 64 or ids[p.id] then return false, "Invalid or duplicate profile ID." end
    ids[p.id] = true
    if type(p.name) ~= "string" or #p.name < 1 or #p.name > 80 then return false, "Profile names must contain 1 to 80 bytes." end
    for _, key in ipairs({"details", "state", "activityName", "largeImage", "smallImage", "largeText", "smallText", "detailsUrl", "stateUrl", "largeUrl", "smallUrl"}) do
      if type(p[key]) ~= "string" or #p[key] > 512 then return false, "Profile text is limited to 512 bytes per field." end
    end
    for _, key in ipairs({"detailsUrl", "stateUrl", "largeUrl", "smallUrl"}) do if not M.validUrl(p[key], true) then return false, key .. " must be a valid HTTPS URL." end end
    if not validImage(p.largeImage) or not validImage(p.smallImage) then return false, "Images require an asset key or HTTPS URL." end
    if not enum(p.activityType, {0, 2, 3, 5}) or not enum(p.statusDisplay, {0, 1, 2}) then return false, "Invalid activity type or status display." end
    if not enum(p.timerMode, {"hidden", "session", "map", "profile", "countdown"}) then return false, "Invalid timer mode." end
    if not finite(p.countdownSeconds) or p.countdownSeconds < 1 or p.countdownSeconds > 604800 then return false, "Countdown must be 1 second to 7 days." end
    if type(p.rotationEnabled) ~= "boolean" or not finite(p.rotationSeconds) or p.rotationSeconds < 15 or p.rotationSeconds > 300 then return false, "Rotation interval must be 15 to 300 seconds." end
    for _, key in ipairs({"detailsVariants", "stateVariants"}) do
      if not array(p[key], 30) then return false, "Use up to 30 rotation lines." end
      for _, text in ipairs(p[key]) do if type(text) ~= "string" or #text > 512 then return false, "Invalid rotation line." end end
    end
    for _, key in ipairs({"mapImages", "vehicleImages"}) do
      if not array(p[key], 100) then return false, "Use up to 100 image mappings." end
      for _, row in ipairs(p[key]) do
        if type(row) ~= "table" or type(row.match) ~= "string" or #row.match > 128 or type(row.image) ~= "string" or not validImage(row.image) then return false, "Invalid image mapping." end
      end
    end
    if not array(p.buttons, 2) then return false, "Discord supports up to two buttons." end
    for _, b in ipairs(p.buttons) do
      if type(b) ~= "table" or type(b.enabled) ~= "boolean" or type(b.label) ~= "string" or #b.label > 128 or not M.validUrl(b.url, true) then return false, "Invalid button label or HTTPS URL." end
    end
  end
  if not ids[config.selectedProfileId] then return false, "Select an existing fallback profile." end
  if not array(config.rules, 100) then return false, "Use up to 100 automatic rules." end
  local ruleIds = {}
  for _, r in ipairs(config.rules) do
    if type(r) ~= "table" or type(r.id) ~= "string" or #r.id > 64 or not r.id:match("^[%w_-]+$") or ruleIds[r.id] then return false, "Invalid rule ID." end
    ruleIds[r.id] = true
    if type(r.enabled) ~= "boolean" or not ids[r.profileId] or not enum(r.context, M.contexts) or not enum(r.paused, {"any", "yes", "no"}) then return false, "Invalid automatic rule." end
    if type(r.map) ~= "string" or #r.map > 128 or type(r.vehicle) ~= "string" or #r.vehicle > 128 then return false, "Invalid rule filter." end
    for _, key in ipairs({"minSpeed", "maxSpeed"}) do
      if r[key] ~= "" and (not finite(r[key]) or r[key] < 0 or r[key] > 100000) then return false, "Speed limits must be positive numbers or empty." end
    end
    if r.minSpeed ~= "" and r.maxSpeed ~= "" and r.minSpeed > r.maxSpeed then return false, "Minimum speed must not exceed maximum speed." end
  end
  return true
end

function M.applyPatch(config, patch)
  if type(patch) ~= "table" then return nil, "Invalid settings patch." end
  local result = M.copy(config)
  for key, value in pairs(patch.general or {}) do
    if not M.generalFields[key] then return nil, "Unknown setting: " .. tostring(key) end
    result[key] = M.copy(value)
  end
  for id, updates in pairs(patch.profiles or {}) do
    local found
    for _, p in ipairs(result.profiles) do if p.id == id then found = p end end
    if not found or type(updates) ~= "table" then return nil, "The profile no longer exists." end
    for key, value in pairs(updates) do
      if not profileFields[key] then return nil, "Unknown profile field: " .. tostring(key) end
      found[key] = M.copy(value)
    end
  end
  if patch.rules ~= nil then result.rules = M.copy(patch.rules) end
  local ok, err = M.validate(result)
  if not ok then return nil, err end
  return result
end

function M.selectProfile(config, context)
  local selected = config.selectedProfileId
  if config.automatic then
    for _, r in ipairs(config.rules) do
      local speed = context.speedKmh
      if r.enabled and (r.context == "any" or (context.flags or {})[r.context])
        and (r.map == "" or r.map:lower() == tostring(context.map_id or ""):lower())
        and (r.vehicle == "" or r.vehicle:lower() == tostring(context.vehicle_model or ""):lower())
        and (r.paused == "any" or (r.paused == "yes") == (context.isPaused == true))
        and (r.minSpeed == "" or (finite(speed) and speed >= r.minSpeed))
        and (r.maxSpeed == "" or (finite(speed) and speed <= r.maxSpeed)) then selected = r.profileId break end
    end
  end
  for _, p in ipairs(config.profiles) do if p.id == selected then return p end end
  return config.profiles[1]
end

function M.truncate(text, maxBytes)
  if #text <= maxBytes then return text end
  local last = maxBytes
  while last > 0 and text:byte(last + 1) >= 128 and text:byte(last + 1) < 192 do last = last - 1 end
  return text:sub(1, last)
end

function M.render(text, context, warnings)
  return (text:gsub("{([%w_]+)([^}]*)}", function(key, suffix)
    if not M.variables[key] then if warnings then warnings[#warnings + 1] = "Unknown variable: " .. key end end
    local value = context[key]
    if value == nil or value == "" then return suffix:sub(1, 1) == "|" and suffix:sub(2) or "N/A" end
    return tostring(value)
  end):gsub("[%z\1-\31\127]", " "))
end

function M.duration(seconds)
  seconds = math.max(0, math.floor(seconds))
  local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
  return h > 0 and string.format("%d:%02d:%02d", h, m, s) or string.format("%02d:%02d", m, s)
end

function M.build(config, context, timeline, now, selected)
  local p = selected or M.selectProfile(config, context)
  local warnings, activity = {}, {type = p.activityType, status_display_type = p.statusDisplay}
  local native = config.transport == "native"
  local maxText = native and 127 or 128
  local ctx = M.copy(context)
  ctx.session_time = M.duration(now - timeline.sessionStart)
  if timeline.mapStart then ctx.map_time = M.duration(now - timeline.mapStart) end
  local function text(value, field, limit, minimum)
    local rendered = M.render(value, ctx, warnings)
    if #rendered > limit then warnings[#warnings + 1] = field .. " was shortened to fit Discord." end
    rendered = M.truncate(rendered, limit)
    if #rendered < (minimum or 2) then return nil end
    return rendered
  end
  local function url(value, field)
    if value == "" then return nil end
    local rendered = M.render(value, ctx, warnings)
    if not M.validUrl(rendered, false) then warnings[#warnings + 1] = field .. " is not a valid HTTPS URL." return nil end
    return rendered
  end
  local index = math.floor(math.max(0, now - timeline.profileStart) / p.rotationSeconds)
  local function rotating(key)
    local choices = p[key .. "Variants"]
    if p.rotationEnabled and #choices > 0 then return choices[index % #choices + 1] end
    return p[key]
  end
  activity.details = text(rotating("details"), "Details", maxText)
  activity.state = text(rotating("state"), "State", maxText)
  if not native then activity.name = text(p.activityName, "Activity name", 128) end
  local largeImage, smallImage = p.largeImage, p.smallImage
  for _, row in ipairs(p.mapImages) do if row.match:lower() == tostring(ctx.map_id or ""):lower() then largeImage = row.image break end end
  for _, row in ipairs(p.vehicleImages) do if row.match:lower() == tostring(ctx.vehicle_model or ""):lower() then smallImage = row.image break end end
  local function image(value, field)
    if value == "" then return nil end
    local rendered = M.render(value, ctx, warnings)
    if not validImage(rendered) or #rendered > (native and 127 or 512) then warnings[#warnings + 1] = field .. " is invalid or too long." return nil end
    return rendered
  end
  local assets = {
    large_image = image(largeImage, "Large image"), small_image = image(smallImage, "Small image"),
    large_text = text(p.largeText, "Large image tooltip", maxText), small_text = text(p.smallText, "Small image tooltip", maxText)
  }
  if not native then
    activity.details_url, activity.state_url = url(p.detailsUrl, "Details link"), url(p.stateUrl, "State link")
    assets.large_url, assets.small_url = url(p.largeUrl, "Large image link"), url(p.smallUrl, "Small image link")
    if p.timerMode == "countdown" then activity.timestamps = {['end'] = timeline.profileStart + p.countdownSeconds}
    elseif p.timerMode ~= "hidden" then
      local start = p.timerMode == "session" and timeline.sessionStart or p.timerMode == "map" and timeline.mapStart or p.timerMode == "profile" and timeline.profileStart
      if start then activity.timestamps = {start = start} end
    end
    local buttons = {}
    for _, b in ipairs(p.buttons) do
      if b.enabled then
        local label, link = text(b.label, "Button label", 32, 1), url(b.url, "Button URL")
        if label and link then buttons[#buttons + 1] = {label = label, url = link} else warnings[#warnings + 1] = "An incomplete button was omitted." end
      end
    end
    if #buttons > 0 then activity.buttons = buttons end
    if context.playerCount and context.playerLimit and context.playerCount >= 1 and context.playerLimit >= context.playerCount then
      activity.party = {size = {context.playerCount, context.playerLimit}}
    end
  end
  if assets.large_image or assets.small_image then activity.assets = assets end
  local nativeActivity = {
    state = activity.state or "", details = activity.details or "",
    asset_largeimg = assets.large_image or "", asset_largetxt = assets.large_text or "",
    asset_smallimg = assets.small_image or "", asset_smalltxt = assets.small_text or ""
  }
  return {profileId = p.id, profileName = p.name, activity = activity, nativeActivity = nativeActivity, warnings = warnings, variables = ctx}
end

function M.signature(value)
  if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. M.signature(value[key]) end
  return "{" .. table.concat(parts, "\0") .. "}"
end

return M
