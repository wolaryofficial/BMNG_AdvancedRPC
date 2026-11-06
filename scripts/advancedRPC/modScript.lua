if rawget(extensions, "customRPC") then extensions.unload("customRPC") end
setExtensionUnloadMode("advancedRPC", "manual")
extensions.load("advancedRPC")
