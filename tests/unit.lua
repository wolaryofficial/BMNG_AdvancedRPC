return function(sources)
  local results = {}
  local function check(name, fn)
    local ok, err = pcall(fn)
    results[#results + 1] = {name = name, passed = ok, error = not ok and tostring(err) or nil}
  end
  local function load(suffix, env)
    for path, source in pairs(sources) do
      if path:sub(-#suffix) == suffix then
        local fn = assert(loadstring(source, suffix))
        if env then setfenv(fn, setmetatable(env, {__index = _G})) end
        return fn()
      end
    end
    error("Missing test source: " .. suffix)
  end
  local model = load("advancedRPC/model.lua")
  local protocol = load("advancedRPC/ipc.lua")
  local function rule(profile, context)
    return {id = "r1", enabled = true, profileId = profile, context = context or "any", map = "", vehicle = "", minSpeed = "", maxSpeed = "", paused = "any"}
  end
  local function build(config, ctx, now)
    return model.build(config or model.defaults(), ctx or {}, {sessionStart = 100, mapStart = 120, profileStart = 140}, now or 200)
  end
  check("default configuration is valid", function() assert(model.validate(model.defaults())) end)
  check("invalid schema is rejected", function() local c = model.defaults() c.schemaVersion = 2 assert(not model.validate(c)) end)
  check("Application ID stays a string", function() local c = model.defaults() c.applicationId = 123 assert(not model.validate(c)) c.applicationId = "123456789012345678" assert(model.validate(c)) end)
  check("invalid Application ID is rejected", function() local c = model.defaults() c.applicationId = "bad" assert(not model.validate(c)) end)
  check("one profile must remain", function() local c = model.defaults() c.profiles = {} assert(not model.validate(c)) end)
  check("duplicate profile IDs are rejected", function() local c = model.defaults() c.profiles[2].id = c.profiles[1].id assert(not model.validate(c)) end)
  check("unknown selected profile is rejected", function() local c = model.defaults() c.selectedProfileId = "missing" assert(not model.validate(c)) end)
  check("non-finite intervals are rejected", function() local c = model.defaults() c.updateInterval = 0/0 assert(not model.validate(c)) end)
  check("fast update intervals are validated", function() local c = model.defaults() assert(c.updateInterval == 5) c.updateInterval = 1 assert(model.validate(c)) c.updateInterval = 0.5 assert(not model.validate(c)) end)
  check("partial patches preserve unrelated values", function() local c = model.defaults() c.units = "imperial" local x = assert(model.applyPatch(c, {profiles = {automatic = {details = "Changed"}}})) assert(x.units == "imperial" and x.profiles[1].state == c.profiles[1].state and c.profiles[1].details ~= "Changed") end)
  check("unknown patch fields are rejected", function() assert(not model.applyPatch(model.defaults(), {general = {secret = "x"}})) end)
  check("template fallback handles missing data", function() assert(model.render("{map|Main menu} / {rpm}", {}) == "Main menu / N/A") end)
  check("template values are not recursively evaluated", function() assert(model.render("{map}", {map = "{rpm}"}) == "{rpm}") end)
  check("unknown variables generate warnings", function() local w = {} model.render("{unknown}", {}, w) assert(#w == 1) end)
  check("template control characters are removed", function() assert(model.render("a\nb\0c", {}) == "a b c") end)
  check("UTF-8 truncation preserves codepoints", function() assert(model.truncate("абвг", 5) == "аб") assert(model.truncate("🙂x", 3) == "") end)
  check("first matching rule wins", function() local c = model.defaults() c.rules = {rule("minimal"), rule("telemetry")} c.rules[2].id = "r2" assert(model.selectProfile(c, {}).id == "minimal") end)
  check("manual mode ignores automatic rules", function() local c = model.defaults() c.automatic = false c.rules = {rule("minimal")} assert(model.selectProfile(c, {}).id == "automatic") end)
  check("rule filters require all conditions", function() local c = model.defaults() local r = rule("telemetry", "beammp") r.map = "italy" r.minSpeed = 30 r.paused = "no" c.rules = {r} assert(model.selectProfile(c, {flags = {beammp = true}, map_id = "italy", speedKmh = 40, isPaused = false}).id == "telemetry") assert(model.selectProfile(c, {flags = {beammp = true}, map_id = "utah", speedKmh = 40}).id == "automatic") end)
  check("missing speed does not match speed rules", function() local c = model.defaults() local r = rule("telemetry") r.minSpeed = 0 c.rules = {r} assert(model.selectProfile(c, {}).id == "automatic") end)
  check("inverted speed bounds are rejected", function() local c = model.defaults() local r = rule("minimal") r.minSpeed, r.maxSpeed = 20, 10 c.rules = {r} assert(not model.validate(c)) end)
  check("unknown BeamMP data is omitted", function() local c = model.defaults() c.transport = "custom" assert(build(c).activity.party == nil) end)
  check("BeamMP counts become party size", function() local c = model.defaults() c.transport = "custom" local p = build(c, {playerCount = 3, playerLimit = 8}) assert(p.activity.party.size[1] == 3 and p.activity.party.size[2] == 8) end)
  check("invalid BeamMP limit does not publish a party", function() local c = model.defaults() c.transport = "custom" assert(build(c, {playerCount = 8, playerLimit = 3}).activity.party == nil) end)
  check("native mode omits advanced features", function() local c = model.defaults() local p = c.profiles[1] p.activityName = "Custom" p.buttons = {{enabled = true, label = "Site", url = "https://example.com"}} local a = build(c).activity assert(not a.name and not a.buttons and not a.timestamps) end)
  check("native external images pass through the BeamNG Discord API", function() local c = model.defaults() c.profiles[1].largeImage = "https://example.com/a.png" c.profiles[1].smallImage = "https://example.com/b.png" local p = build(c) assert(p.nativeActivity.asset_largeimg == "https://example.com/a.png" and p.nativeActivity.asset_smallimg == "https://example.com/b.png" and #p.warnings == 0) end)
  check("external HTTPS images work in custom mode", function() local c = model.defaults() c.transport = "custom" c.profiles[1].largeImage = "https://example.com/a.gif" assert(build(c).activity.assets.large_image == "https://example.com/a.gif") end)
  check("both image URLs and captions render independently", function() local c = model.defaults() c.transport = "custom" local p = c.profiles[1] p.largeImage, p.smallImage = "https://example.com/map.png", "https://example.com/car.webp" p.largeText, p.smallText = "Map: {map}", "Driving {vehicle}" local a = build(c, {map = "Italy", vehicle = "Gavril D-Series"}).activity.assets assert(a.large_image == p.largeImage and a.small_image == p.smallImage and a.large_text == "Map: Italy" and a.small_text == "Driving Gavril D-Series") end)
  check("empty captions are omitted", function() local c = model.defaults() c.transport = "custom" c.profiles[1].largeText, c.profiles[1].smallText = "", "" local a = build(c).activity.assets assert(not a.large_text and not a.small_text) end)
  check("image click destinations do not replace image sources", function() local c = model.defaults() c.transport = "custom" local p = c.profiles[1] p.largeImage, p.largeUrl = "https://example.com/a.png", "https://example.com/page" local a = build(c).activity.assets assert(a.large_image == p.largeImage and a.large_url == p.largeUrl) end)
  check("unsafe URLs are rejected", function() assert(not model.validUrl("javascript:alert(1)")) assert(not model.validUrl("file:///a")) assert(not model.validUrl("https://user@example.com")) end)
  check("map and vehicle image mappings apply", function() local c = model.defaults() c.profiles[1].mapImages = {{match = "italy", image = "italy_custom"}} c.profiles[1].vehicleImages = {{match = "pickup", image = "truck"}} local p = build(c, {map_id = "italy", vehicle_model = "pickup"}) assert(p.nativeActivity.asset_largeimg == "italy_custom" and p.nativeActivity.asset_smallimg == "truck") end)
  check("rotation follows a stable timeline", function() local c = model.defaults() local p = c.profiles[1] p.rotationEnabled = true p.rotationSeconds = 30 p.detailsVariants = {"First", "Second"} assert(build(c, {}, 140).activity.details == "First") assert(build(c, {}, 170).activity.details == "Second") assert(build(c, {}, 200).activity.details == "First") end)
  check("session timer is stable across refreshes", function() local c = model.defaults() c.transport = "custom" assert(build(c, {}, 200).activity.timestamps.start == 100 and build(c, {}, 240).activity.timestamps.start == 100) end)
  check("map timer is hidden when there is no map", function() local c = model.defaults() c.transport = "custom" c.profiles[1].timerMode = "map" local p = model.build(c, {}, {sessionStart = 100, profileStart = 100}, 150) assert(not p.activity.timestamps) end)
  check("countdown is based on profile activation", function() local c = model.defaults() c.transport = "custom" c.profiles[1].timerMode = "countdown" c.profiles[1].countdownSeconds = 60 assert(build(c).activity.timestamps['end'] == 200) end)
  check("incomplete buttons are not sent", function() local c = model.defaults() c.transport = "custom" c.profiles[1].buttons = {{enabled = true, label = "", url = ""}} assert(not build(c).activity.buttons) end)
  check("two custom buttons are supported", function() local c = model.defaults() c.transport = "custom" c.profiles[1].buttons = {{enabled = true, label = "One", url = "https://example.com/1"}, {enabled = true, label = "Two", url = "https://example.com/2"}} assert(#build(c).activity.buttons == 2) c.profiles[1].buttons[3] = c.profiles[1].buttons[1] assert(not model.validate(c)) end)
  check("payload signatures ignore table insertion order", function() assert(model.signature({a = 1, b = 2}) == model.signature({b = 2, a = 1})) end)

  local function controller()
    local saved
    return load("extensions/advancedRPC.lua", {
      require = function(name) if name == "advancedRPC/model" then return model elseif name == "advancedRPC/context" then return {new = function() return {} end} else return {} end end,
      jsonWriteFile = function(path, value) saved = model.copy(value) return true end,
      jsonReadFile = function() return saved end,
      FS = {renameFile = function() return 0 end, removeFile = function() end},
      guihooks = {trigger = function() end}, os = {time = function() return 1000 end}
    })
  end
  check("new profiles use defaults instead of cloning the selection", function() local m = controller() local s = m.setSettingsFromUI({revision = 0, patch = {profiles = {automatic = {details = "Edited"}}}}) local r = m.profileAction({revision = s.revision, id = "automatic", action = "create"}) local p = r.settings.profiles[4] assert(p.name == "New profile" and p.details == "{activity}" and r.saved) end)
  check("duplicated profiles keep appearance and receive unique IDs", function() local m = controller() local a = m.profileAction({revision = 0, id = "automatic", action = "duplicate"}) local b = m.profileAction({revision = a.revision, id = "automatic", action = "duplicate"}) assert(a.settings.profiles[4].id ~= b.settings.profiles[5].id and b.settings.profiles[5].name == "Automatic copy") end)
  check("stale UI revisions cannot overwrite newer settings", function() local m = controller() m.setSettingsFromUI({revision = 0, patch = {general = {units = "imperial"}}}) local r = m.setSettingsFromUI({revision = 0, patch = {general = {units = "metric"}}}) assert(r.conflict and r.settings.units == "imperial") end)
  check("deleting an active profile removes its rules and selects a fallback", function() local m = controller() local r = m.setSettingsFromUI({revision = 0, patch = {general = {selectedProfileId = "telemetry"}, rules = {rule("telemetry")}}}) r = m.profileAction({revision = r.revision, id = "telemetry", action = "delete"}) assert(r.settings.selectedProfileId == "automatic" and #r.settings.rules == 0 and #r.settings.profiles == 2) end)

  local function runtimeHarness(files)
    local f = {files = model.copy(files or {}), time = 0, working = true, submitted = {}, ctx = {flags = {menu = true}, activity = "Main menu", location = "Main menu"}}
    local api = {
      isWorking = function() return f.working end,
      setEnabled = function() end,
      clearActivity = function() end,
      setActivity = function(value) f.staged = model.copy(value) end,
      updateActivity = function()
        if f.fail then return false end
        f.submitted[#f.submitted + 1] = {time = f.time, payload = f.staged}
      end
    }
    local originalSet, originalUpdate = api.setActivity, api.updateActivity
    local m = load("extensions/advancedRPC.lua", {
      require = function(name)
        if name == "advancedRPC/model" then return model end
        if name == "advancedRPC/context" then return {new = function() return {sample = function() return model.copy(f.ctx) end, detachBeamMP = function() end} end} end
        return protocol
      end,
      settings = {getValue = function() return true end}, Discord = api,
      jsonReadFile = function(path) return model.copy(f.files[path]) end,
      jsonWriteFile = function(path, value) f.files[path] = model.copy(value) return true end,
      FS = {
        renameFile = function(_, from, to) f.files[to], f.files[from] = f.files[from], nil return 0 end,
        removeFile = function(_, path) f.files[path] = nil end,
        fileExists = function(_, path) return f.files[path] ~= nil end
      },
      guihooks = {trigger = function() end}, os = {time = function() return 1000 + math.floor(f.time) end},
      setExtensionUnloadMode = function() end, getPlayerVehicle = function() end,
      log = function() end, util_richPresence = {}, core_gamestate = {state = {}}
    })
    m.onExtensionLoaded()
    function f.step(dt) f.time = f.time + dt m.onUpdate(dt) end
    function f.edit(patch) return m.setSettingsFromUI({revision = m.getSettings().revision, patch = patch}) end
    return m, f, api, originalSet, originalUpdate
  end
  check("legacy settings migrate without losing profiles or application ID", function() local c = model.defaults() c.applicationId = "1284130104884334693" c.profiles[1].details = "Preserved" c.units = "imperial" local m, f = runtimeHarness({["/settings/custom_rpc.json"] = c}) assert(model.signature(m.getSettings().settings) == model.signature(c) and model.signature(f.files["/settings/advanced_rpc.json"]) == model.signature(c) and f.files["/settings/custom_rpc.json"]) end)
  check("renamed settings take precedence over legacy settings", function() local old, current = model.defaults(), model.defaults() old.units, current.units = "imperial", "metric" local m = runtimeHarness({["/settings/custom_rpc.json"] = old, ["/settings/advanced_rpc.json"] = current}) assert(m.getSettings().settings.units == "metric") end)
  check("invalid legacy settings are preserved and not migrated", function() local bad = {schemaVersion = -1} local m, f = runtimeHarness({["/settings/custom_rpc.json"] = bad}) assert(not m.getSettings().settings.enabled and m.getSettings().error ~= "" and not f.files["/settings/advanced_rpc.json"] and f.files["/settings/custom_rpc.json"].schemaVersion == -1) end)
  check("invalid renamed settings never fall back to stale legacy settings", function() local m, f = runtimeHarness({["/settings/custom_rpc.json"] = model.defaults(), ["/settings/advanced_rpc.json"] = {schemaVersion = -1}}) assert(not m.getSettings().settings.enabled and m.getSettings().error ~= "" and f.files["/settings/advanced_rpc.json"].schemaVersion == -1) end)
  check("native activities are submitted and the native update pump remains available", function() local m, f, api, originalSet, originalUpdate = runtimeHarness() f.step(0.25) assert(#f.submitted == 1 and f.submitted[1].payload.details == "Main menu" and api.updateActivity == originalUpdate) m.onExtensionUnloaded() assert(api.setActivity == originalSet and api.updateActivity == originalUpdate) end)
  check("native text follows changing live data at the selected interval", function() local m, f = runtimeHarness() f.step(0.25) f.ctx.activity = "Driving" f.step(4) assert(#f.submitted == 1) f.step(1) assert(#f.submitted == 2 and f.submitted[2].payload.details == "Driving") end)
  check("career transitions and settings edits bypass a long telemetry interval", function() local m, f = runtimeHarness() f.edit({general = {updateInterval = 60}}) f.step(0.25) f.ctx.flags, f.ctx.activity, f.ctx.career_activity = {career = true}, "Career | Delivering cargo", "Delivering cargo" m.onCareerActive() f.step(1) assert(#f.submitted == 2 and f.submitted[2].payload.details == "Career | Delivering cargo") f.edit({profiles = {automatic = {details = "New text"}}}) f.step(1) assert(f.submitted[3].payload.details == "New text") end)
  check("native heartbeat republishes unchanged activity", function() local m, f = runtimeHarness() f.step(0.25) f.step(29) assert(#f.submitted == 1) f.step(1) assert(#f.submitted == 2) end)
  check("native connection recovery resubmits the current activity", function() local m, f = runtimeHarness() f.step(0.25) f.working = false f.step(1) assert(m.getStatus().state == "waiting") f.working = true f.step(1) assert(#f.submitted == 2 and m.getStatus().state == "native") end)
  check("failed native submissions retry without claiming success", function() local m, f = runtimeHarness() f.fail = true f.step(0.25) assert(#f.submitted == 0 and m.getStatus().state == "error" and not m.getStatus().lastSentAt) f.fail = false f.step(1) assert(#f.submitted == 0) f.step(4) assert(#f.submitted == 1) end)
  check("rapid edits coalesce within the Discord update budget", function() local m, f = runtimeHarness() for i = 1, 60 do f.edit({profiles = {automatic = {details = "Edit " .. i}}}) f.step(0.25) end assert(#f.submitted == 5) f.step(6) assert(#f.submitted == 6 and f.submitted[6].payload.details == "Edit 60") end)

  local function contextHarness()
    local fixture = {level = ""}
    local env = {
      extensions = {}, settings = {getValue = function() return "metric" end},
      getCurrentLevelIdentifier = function() return fixture.level end,
      getPlayerVehicle = function() return fixture.vehicle end,
      jsonReadFile = function(path) if path:find("/levels/", 1, true) then return {title = "Test map"} end return {Brand = "Modded", Name = "Car"} end,
      core_locales = {translate = function(value) return value end},
      core_vehicles = {getCurrentVehicleDetails = function() return {configs = {Configuration = "Special"}} end},
      core_gamestate = {getLoadingStatus = function() return fixture.loading end},
      simTimeAuthority = {getPause = function() return fixture.paused end},
      core_environment = {getTimeOfDay = function() return {time = 0.25} end},
      career_career = {}, career_modules_tutorial = {}, career_modules_delivery_general = {}, career_modules_partShopping = {}, career_modules_playerAttributes = {}, career_saveSystem = {}, gameplay_garageMode = {}, editor = {}, ui_pause_photomode = {}, core_replay = {}, gameplay_walk = {}, gameplay_missions_missionManager = {}, gameplay_missions_missions = {}, scenario_scenarios = {}
    }
    return load("advancedRPC/context.lua", env).new(), fixture, env
  end
  check("main menu does not invent map or vehicle data", function() local c = contextHarness() local ctx = c:sample(model.defaults()) assert(ctx.flags.menu and ctx.mode == "Main menu" and not ctx.vehicle and not ctx.map_id) end)
  check("modded vehicle metadata and telemetry are collected", function() local c, f = contextHarness() f.level = "custom_map" f.vehicle = {getID = function() return 42 end, getJBeamFilename = function() return "custom_car" end, getVelocity = function() return {length = function() return 10 end} end} local ctx = c:sample(model.defaults(), {id = 42, rpm = 900, gear = "N", fuel = 0.5, running = true}) assert(ctx.vehicle == "Modded Car" and ctx.vehicle_config == "Special" and ctx.speed == "36 km/h" and ctx.rpm == "900" and ctx.time_of_day == "18:00") assert(not c:sample(model.defaults(), {id = 99, rpm = 8000}).rpm) end)
  check("loading and pause contexts change the description", function() local c, f = contextHarness() f.level, f.loading, f.paused = "smallgrid", true, true local ctx = c:sample(model.defaults()) assert(ctx.flags.loading and ctx.isPaused and ctx.activity == "Paused | Loading") end)
  check("walking mode does not reuse car telemetry", function() local c, f = contextHarness() f.level = "smallgrid" f.vehicle = {getID = function() return 42 end, getJBeamFilename = function() return "unicycle" end} local ctx = c:sample(model.defaults(), {id = 42, rpm = 8000}) assert(ctx.mode == "Walking" and not ctx.rpm and not ctx.vehicle) end)
  check("career activities and progress use the current career APIs", function() local c, f, env = contextHarness() f.level = "west_coast_usa" env.career_career = {isActive = function() return true end, getBeamXPLevel = function() return 3 end} env.career_modules_delivery_general.isDeliveryModeActive = function() return true end env.career_modules_playerAttributes.getAttributeValue = function(key) return key == "money" and 12345.5 or 350 end env.career_saveSystem.getCurrentDisplayName = function() return "My career" end local ctx = c:sample(model.defaults()) assert(ctx.mode == "Career" and ctx.flags.career_delivery and ctx.activity == "Career | Delivering cargo" and ctx.career_money == "12345" and ctx.career_beamxp == "350" and ctx.career_level == "3" and ctx.career_profile == "My career") end)
  check("career walking keeps career context and matches specific rules", function() local c, f, env = contextHarness() f.level = "west_coast_usa" env.career_career.isActive = function() return true end env.gameplay_walk.isWalking = function() return true end local ctx = c:sample(model.defaults()) local config = model.defaults() config.rules = {rule("telemetry", "career_walking")} assert(ctx.mode == "Career" and ctx.career_activity == "Walking" and ctx.flags.career and ctx.flags.walking and not ctx.flags.freeroam and model.selectProfile(config, ctx).id == "telemetry") end)
  check("career missions, shopping and tutorials update independently", function() local c, f, env = contextHarness() f.level = "west_coast_usa" env.career_career.isActive = function() return true end env.gameplay_missions_missionManager.getForegroundMissionId = function() return "delivery01" end env.gameplay_missions_missions.getMissionById = function() return {name = "Cargo run"} end assert(c:sample(model.defaults()).career_activity == "Mission: Cargo run") env.gameplay_missions_missionManager.getForegroundMissionId = nil env.career_modules_partShopping.isShoppingSessionActive = function() return true end assert(c:sample(model.defaults()).career_activity == "Shopping for parts") env.career_modules_tutorial.isActive = function() return true end assert(c:sample(model.defaults()).career_activity == "Tutorial") end)
  check("career data clears on exit and missing optional APIs are harmless", function() local c, f, env = contextHarness() f.level = "west_coast_usa" local active = true env.career_career.isActive = function() return active end assert(c:sample(model.defaults()).career_activity == "Exploring") active = false local ctx = c:sample(model.defaults()) assert(ctx.mode == "Free roam" and not ctx.career_activity and not ctx.career_money and not ctx.career_profile) end)
  check("BeamMP counters retain the original callback and clear after leaving", function() local c, f, env = contextHarness() f.level = "italy" local joined, called = true, false local original = function() called = true end env.extensions.UI = {setPlayerCount = original} env.extensions.MPCoreNetwork = {isMPSession = function() return joined end, getCurrentServer = function() return {name = "^2My server"} end} env.extensions.MPVehicleGE = {getPlayers = function() return {a = {}, b = {}} end} c:sample(model.defaults()) env.extensions.UI.setPlayerCount("2/8") local ctx = c:sample(model.defaults()) assert(called and ctx.server == "My server" and ctx.playerCount == 2 and ctx.playerLimit == 8) joined = false assert(not c:sample(model.defaults()).server and not c.playerLimit) c:detachBeamMP() assert(env.extensions.UI.setPlayerCount == original) end)

  local function harness()
    local channel = {pid = 123, incoming = {}, writes = {}, closed = false}
    function channel:write(data) self.writes[#self.writes + 1] = data return true end
    function channel:poll() if self.closed then return nil, "closed" end return table.remove(self.incoming, 1) or "" end
    function channel:close() self.closed = true end
    local driver = {open = function() channel.closed = false return channel end}
    local client = protocol.new(driver, jsonEncode, jsonDecode)
    client:start("123456789012345678")
    client:update(0)
    local function receive(data, time) channel.incoming[#channel.incoming + 1] = data client:update(time or 1) end
    local function ready() receive(protocol.frame(1, jsonEncode({evt = "READY"}))) end
    return client, channel, receive, ready
  end
  check("IPC starts with an application handshake", function() local c, io = harness() assert(io.writes[1]:byte(1) == 0 and io.writes[1]:find('123456789012345678', 1, true)) assert(c.state == "connecting") end)
  check("IPC handles fragmented headers and payloads", function() local c, io, receive = harness() local f = protocol.frame(1, jsonEncode({evt = "READY"})) receive(f:sub(1, 5)) assert(c.state == "connecting") receive(f:sub(6), 2) assert(c.state == "ready") end)
  check("IPC does not send activity before READY", function() local c, io = harness() c:request({details = "Test"}, "test") c:update(1) assert(#io.writes == 1) end)
  check("IPC matches activity acknowledgements by nonce", function() local c, io, receive, ready = harness() ready() c:request({details = "Test"}, "test") c:update(2) local data = jsonDecode(io.writes[#io.writes]:sub(9)) receive(protocol.frame(1, jsonEncode({cmd = "SET_ACTIVITY", nonce = "wrong"})), 3) assert(not c.lastAck) receive(protocol.frame(1, jsonEncode({cmd = "SET_ACTIVITY", nonce = data.nonce})), 4) assert(c.lastAckSignature == "test") end)
  check("IPC answers PING without decoding its body", function() local c, io, receive, ready = harness() ready() receive(protocol.frame(3, "ping"), 2) assert(io.writes[#io.writes] == protocol.frame(4, "ping")) end)
  check("IPC handshake timeout closes the handle", function() local c, io = harness() c:update(11) assert(c.state == "waiting" and io.closed) end)
  check("IPC rejects oversized frames", function() local c, io, receive = harness() receive(protocol.frame(1, string.rep("x", 65537)):sub(1, 8)) assert(c.state == "waiting" and io.closed) end)
  check("IPC reports Discord errors without claiming success", function() local c, io, receive, ready = harness() ready() c:request({details = "Test"}, "test") c:update(2) local data = jsonDecode(io.writes[#io.writes]:sub(9)) receive(protocol.frame(1, jsonEncode({evt = "ERROR", nonce = data.nonce, data = {message = "Invalid assets"}})), 3) assert(c.state == "error" and c.error == "Invalid assets" and not c.lastAck) end)
  check("IPC disconnect clears pending acknowledgements", function() local c, io, receive, ready = harness() ready() c:request({details = "Test"}, "test") c:update(2) receive(protocol.frame(2, jsonEncode({message = "Closed"})), 3) assert(c.state == "waiting" and not c.inFlight and io.closed) end)
  check("IPC disconnect invalidates the accepted activity", function() local c, io, receive, ready = harness() ready() c:request({details = "Test"}, "test") c:update(2) local data = jsonDecode(io.writes[#io.writes]:sub(9)) receive(protocol.frame(1, jsonEncode({cmd = "SET_ACTIVITY", nonce = data.nonce, data = {details = "Test"}})), 3) assert(c.lastAckActivity.details == "Test") c:disconnect("Closed") assert(not c.lastAckSignature and not c.lastAckActivity) end)
  check("IPC keeps the bridge alive without changing activity", function() local c, io, receive, ready = harness() ready() c:update(5) assert(io.writes[#io.writes] == protocol.frame(3, "advancedrpc")) end)
  check("IPC retries an unchanged rejected activity after backoff", function() local c, io, receive, ready = harness() ready() c:request({details = "Test"}, "test") c:update(2) local data = jsonDecode(io.writes[#io.writes]:sub(9)) receive(protocol.frame(1, jsonEncode({evt = "ERROR", nonce = data.nonce, data = {message = "Rate limited"}})), 3) c:update(22) assert(not c.inFlight) c:update(23) assert(c.inFlight and c.inFlight.nonce ~= data.nonce) end)
  check("IPC reconnect republishes the latest pending activity", function() local c, io, receive, ready = harness() ready() c:request({details = "Old"}, "old") c:update(2) c:request({details = "Latest"}, "latest") c:disconnect("Connection lost") c:update(4) receive(protocol.frame(1, jsonEncode({evt = "READY"})), 5) assert(c.inFlight and c.inFlight.signature == "latest") end)
  check("IPC heartbeat can refresh an acknowledged activity", function() local c, io, receive, ready = harness() ready() c:request({details = "Test"}, "test") c:update(2) local nonce = c.inFlight.nonce receive(protocol.frame(1, jsonEncode({cmd = "SET_ACTIVITY", nonce = nonce})), 3) c:request({details = "Test"}, "test", true) c:update(4) assert(c.inFlight and c.inFlight.nonce ~= nonce) end)
  check("IPC stop releases the connection", function() local c, io = harness() c:stop() assert(io.closed and c.state == "idle" and not c.applicationId) end)
  check("IPC driver unavailability backs off", function() local opens = 0 local c = protocol.new({open = function() opens = opens + 1 return nil, "Not running" end}, jsonEncode, jsonDecode) c:start("123456789012345678") c:update(0) c:update(0.5) assert(opens == 1) c:update(1) assert(opens == 2 and c.nextAttempt == 3) end)
  return results
end
