-- =============================================
-- Survive Overnight in a Mega Store
-- Loader v1.0.0
-- =============================================

local VERSION = "1.0.0"
local GAME_NAME = "Survive Overnight in a Mega Store"
local REQUIRED_PLACE_ID = 127380660530951
local SCRIPT_URL = "https://raw.githubusercontent.com/biggetsskidonearth/Survive-Overnight-in-an-Supermarket/main/main.lua"

--// Set Thread Identity (THIS IS THE FIX)
setthreadidentity(7)

--// Anti Env Logger
local _loadstring = clonefunction(loadstring)
local _HttpGet = clonefunction(game.HttpGet)
local _pcall = clonefunction(pcall)

--// Game Check
if game.PlaceId ~= REQUIRED_PLACE_ID then
    return warn("❌ Wrong Game! This script only works in '" .. GAME_NAME .. "'")
end

print("🚀 Loading " .. GAME_NAME .. " | Version " .. VERSION)

--// Loading Animation
for i = 1, 5 do
    print("[" .. VERSION .. "] Loading... (" .. (i * 20) .. "%)")
    task.wait(0.1)
end

--// Fetch Script
local success, response = _pcall(function()
    return _HttpGet(game, SCRIPT_URL, true)
end)

if not success or not response then
    return warn("❌ Failed to fetch script: " .. tostring(response))
end

--// Execute Script
setthreadidentity(7)
local func, err = _loadstring(response)

if not func then
    return warn("❌ Script Error: " .. tostring(err))
end

setthreadidentity(7)
print("✅ Successfully loaded " .. GAME_NAME .. " | Version " .. VERSION)
func()
