local M = {}
local assets = {}
for _, key in ipairs({"automation_test_track", "cliff", "derby", "driver_training", "east_coast_usa", "glow_city", "gridmap", "hirochi_raceway", "industrial", "italy", "jungle_rock_island", "small_island", "smallgrid", "utah", "west_coast_usa"}) do assets[key] = true end

local function call(module, name, ...)
  if type(module) ~= "table" or type(module[name]) ~= "function" then return nil end
  local ok, value = pcall(module[name], ...)
  return ok and value or nil
end

local function translated(value)
  if type(value) ~= "string" or value == "" then return nil end
  local ok, text = pcall(function() return core_locales.translate(value, value) end)
  return ok and text or value
end

local function numberText(value)
  if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
  return string.format("%.0f", math.floor(value))
end

function M.new()
  local self = {maps = {}, vehicles = {}, playerCount = nil, playerLimit = nil, vehicleId = nil}

  function self:observePlayerCount(value)
    local current, maximum = tostring(value):match("(%d+)%s*/%s*(%d+)")
    self.playerCount, self.playerLimit = tonumber(current), tonumber(maximum)
  end

  function self:attachBeamMP()
    local module = extensions.UI
    if self.mpModule == module and module and module.setPlayerCount == self.mpWrapper then return end
    self:detachBeamMP()
    if not module or type(module.setPlayerCount) ~= "function" then return end
    self.mpModule, self.mpOriginal = module, module.setPlayerCount
    local original = self.mpOriginal
    self.mpWrapper = function(value, ...)
      self:observePlayerCount(value)
      return original(value, ...)
    end
    module.setPlayerCount = self.mpWrapper
  end

  function self:detachBeamMP()
    if self.mpModule and self.mpModule.setPlayerCount == self.mpWrapper then self.mpModule.setPlayerCount = self.mpOriginal end
    self.mpModule, self.mpOriginal, self.mpWrapper = nil, nil, nil
  end

  function self:sample(config, telemetry)
    self:attachBeamMP()
    local ctx = {flags = {}, map_asset = "missingnormaltexture"}
    local level = getCurrentLevelIdentifier() or ""
    if level ~= "" then
      ctx.map_id = level
      if not self.maps[level] then
        local data = jsonReadFile("/levels/" .. level .. "/info.json") or {}
        self.maps[level] = translated(data.title or data.name) or level:gsub("_", " "):gsub("^%l", string.upper)
      end
      ctx.map = self.maps[level]
      if assets[level] then ctx.map_asset = "lvl_" .. level end
    end
    local vehicle = getPlayerVehicle(0)
    local vehicleId = vehicle and vehicle:getID() or nil
    if vehicleId ~= self.vehicleId then self.vehicleId = vehicleId self.details = nil end
    if vehicle then
      local key = vehicle:getJBeamFilename()
      ctx.vehicle_model = key
      if key ~= "unicycle" then
        if not self.vehicles[key] then
          local info = jsonReadFile("/vehicles/" .. key .. "/info.json") or {}
          local brand = translated(info.Brand) or ""
          local name = translated(info.Name) or key
          self.vehicles[key] = (brand ~= "" and brand .. " " or "") .. name
        end
        ctx.vehicle = self.vehicles[key]
        if not self.details then self.details = call(core_vehicles, "getCurrentVehicleDetails") or {} end
        local details = self.details
        ctx.vehicle_config = translated(details.configs and (details.configs.Configuration or details.configs.Name))
          or (details.current and details.current.config_key)
        local velocity = vehicle:getVelocity()
        local speed = velocity:length()
        ctx.speedKmh = math.max(0, speed * 3.6)
        ctx.speed_kmh, ctx.speed_mph = tostring(math.floor(ctx.speedKmh + 0.5)), tostring(math.floor(speed * 2.2369363 + 0.5))
        local imperial = config.units == "imperial" or (config.units == "game" and settings.getValue("uiUnitLength") == "imperial")
        ctx.speed = imperial and ctx.speed_mph .. " mph" or ctx.speed_kmh .. " km/h"
        if telemetry and telemetry.id == vehicleId then
          if telemetry.rpm then ctx.rpm = tostring(math.floor(telemetry.rpm + 0.5)) end
          if telemetry.gear then ctx.gear = tostring(telemetry.gear) end
          if telemetry.fuel then ctx.fuel = tostring(math.floor(telemetry.fuel * 100 + 0.5)) .. "%" end
          if telemetry.running ~= nil then ctx.engine = telemetry.running and "Running" or "Off" end
        end
      end
    end
    ctx.vehicleId = vehicleId
    local flags = ctx.flags
    flags.menu = level == ""
    flags.loading = call(core_gamestate, "getLoadingStatus", "levels") == true
    flags.career = not flags.menu and call(career_career, "isActive") == true
    flags.editor = call(editor, "isEditorActive") == true
    flags.photo = call(ui_pause_photomode, "isPhotomodeSessionActive") == true
    local replay = call(core_replay, "getState")
    flags.replay = type(replay) == "string" and replay ~= "inactive" and replay ~= "idle"
    flags.walking = call(gameplay_walk, "isWalking") == true or ctx.vehicle_model == "unicycle"
    local missionId = call(gameplay_missions_missionManager, "getForegroundMissionId")
    if missionId then
      flags.mission = true
      local mission = call(gameplay_missions_missions, "getMissionById", missionId)
      ctx.mission = translated(mission and mission.name) or missionId
    end
    local scenario = call(scenario_scenarios, "getScenario")
    if scenario then flags.scenario = true ctx.mission = ctx.mission or translated(scenario.name) end
    if flags.career then
      flags.career_tutorial = call(career_modules_tutorial, "isActive") == true
      flags.career_mission = flags.mission == true
      flags.career_delivery = call(career_modules_delivery_general, "isDeliveryModeActive") == true
      flags.career_shopping = call(career_modules_partShopping, "isShoppingSessionActive") == true
      flags.career_walking = flags.walking
      flags.career_garage = call(gameplay_garageMode, "isActive") == true
      ctx.career_activity = "Exploring"
      for _, item in ipairs({{"career_tutorial", "Tutorial"}, {"career_mission", ctx.mission and "Mission: " .. ctx.mission or "Mission"}, {"career_shopping", "Shopping for parts"}, {"career_delivery", "Delivering cargo"}, {"career_garage", "In garage"}, {"career_walking", "Walking"}}) do
        if flags[item[1]] then ctx.career_activity = item[2] break end
      end
      ctx.career_money = numberText(call(career_modules_playerAttributes, "getAttributeValue", "money"))
      local xp = call(career_modules_playerAttributes, "getAttributeValue", "beamXP")
      ctx.career_beamxp = numberText(xp)
      if ctx.career_beamxp then ctx.career_level = numberText(call(career_career, "getBeamXPLevel", xp)) end
      ctx.career_profile = call(career_saveSystem, "getCurrentDisplayName") or call(career_saveSystem, "getCurrentProfile")
      if type(ctx.career_profile) ~= "string" then ctx.career_profile = nil end
    end
    flags.beammp = call(extensions.MPCoreNetwork, "isMPSession") == true
    if flags.beammp then
      local server = call(extensions.MPCoreNetwork, "getCurrentServer")
      ctx.server = server and server.name and server.name:gsub("%^%w", "") or nil
      local players = call(extensions.MPVehicleGE, "getPlayers")
      if type(players) == "table" then
        local count = 0
        for _ in pairs(players) do count = count + 1 end
        ctx.playerCount = count > 0 and count or self.playerCount
      else ctx.playerCount = self.playerCount end
      ctx.playerLimit = self.playerLimit
      if ctx.playerCount then ctx.players = tostring(ctx.playerCount) end
      if ctx.playerLimit then ctx.max_players = tostring(ctx.playerLimit) end
    else self.playerCount, self.playerLimit = nil, nil end
    flags.freeroam = not flags.menu and not flags.career and not flags.scenario and not flags.mission
    ctx.isPaused = call(simTimeAuthority, "getPause") == true
    ctx.paused = ctx.isPaused and "Paused" or "Playing"
    local mode = "Free roam"
    for _, item in ipairs({{"loading", "Loading"}, {"menu", "Main menu"}, {"editor", "World editor"}, {"photo", "Photo mode"}, {"replay", "Replay"}, {"career", "Career"}, {"walking", "Walking"}, {"mission", "Mission"}, {"scenario", "Scenario"}, {"beammp", "BeamMP"}}) do
      if flags[item[1]] then mode = item[2] break end
    end
    ctx.mode = mode
    ctx.activity = mode .. (mode == "Career" and " | " .. ctx.career_activity or "") .. (ctx.vehicle and not flags.menu and not flags.loading and " | " .. ctx.vehicle or "")
    ctx.location = flags.beammp and (ctx.server or "Multiplayer") or ctx.map or "Main menu"
    if ctx.isPaused and not flags.menu then ctx.activity = "Paused | " .. ctx.activity end
    local tod = level ~= "" and call(core_environment, "getTimeOfDay")
    if tod and type(tod.time) == "number" then
      local minutes = math.floor(((tod.time + 0.5) % 1) * 1440)
      ctx.time_of_day = string.format("%02d:%02d", math.floor(minutes / 60), minutes % 60)
    end
    return ctx
  end
  return self
end

return M
