local M = {}

function M.sample(generation)
  local values = electrics and electrics.values or {}
  local result = {id = obj:getID()}
  local function number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge and value or nil
  end
  result.rpm = number(values.rpm)
  result.gear = values.gear
  if type(result.gear) ~= "string" and type(result.gear) ~= "number" then result.gear = nil end
  result.fuel = number(values.fuel)
  if result.fuel then result.fuel = math.min(1, math.max(0, result.fuel)) end
  if values.engineRunning ~= nil then result.running = values.engineRunning == true or values.engineRunning == 1
  elseif result.rpm then result.running = result.rpm > 0 end
  obj:queueGameEngineLua("if extensions.advancedRPC then extensions.advancedRPC.onTelemetry(" .. serialize(generation) .. "," .. serialize(result) .. ") end")
end

return M
