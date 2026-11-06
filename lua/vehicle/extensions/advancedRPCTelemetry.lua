local M = {}

function M.sample(generation, fields)
  fields = type(fields) == "table" and fields or {rpm = true, gear = true, fuel = true, engine = true}
  local values = electrics and electrics.values or {}
  local result = {id = obj:getID()}
  local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value or nil
  end
  if fields.rpm then result.rpm = number(values.rpm) end
  if fields.gear then result.gear = values.gear end
  if type(result.gear) ~= "string" and type(result.gear) ~= "number" then result.gear = nil end
  if fields.fuel then result.fuel = number(values.fuel) end
  if result.fuel then result.fuel = math.min(1, math.max(0, result.fuel)) end
  if fields.engine then
    if values.engineRunning ~= nil then result.running = values.engineRunning == true or values.engineRunning == 1
    elseif number(values.rpm) then result.running = values.rpm > 0 end
  end
  obj:queueGameEngineLua("local m=rawget(extensions,'advancedRPC') if m then m.onTelemetry(" .. serialize(generation) .. "," .. serialize(result) .. ") end")
end

return M
