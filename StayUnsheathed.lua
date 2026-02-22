-- StayUnsheathed (standalone, no Ace3)

local ADDON_NAME = ...
local SU = CreateFrame("Frame")
_G.StayUnsheathed = SU -- optional global for debugging / compatibility

-- -----------------------------
-- SavedVariables (keeps old AceDB shape if present)
-- -----------------------------
local DEFAULTS = {
  EnabledState = true,
  Specs = {},
  CityUnsheathed = true,
  SheathStateCheckTimerInSeconds = 2,
}

local db -- points at either StayUnsheathedDB.char (old AceDB) or StayUnsheathedDB (new)

local function deepCopy(tbl)
  local out = {}
  for k, v in pairs(tbl) do
    out[k] = (type(v) == "table") and deepCopy(v) or v
  end
  return out
end

local function applyDefaults(target, defaults)
  for k, v in pairs(defaults) do
    if target[k] == nil then
      target[k] = (type(v) == "table") and deepCopy(v) or v
    elseif type(v) == "table" and type(target[k]) == "table" then
      applyDefaults(target[k], v)
    end
  end
end

local function initDB()
  StayUnsheathedDB = StayUnsheathedDB or {}

  -- If you previously used AceDB, it stored values in StayUnsheathedDB.char
  db = StayUnsheathedDB.char or StayUnsheathedDB
  applyDefaults(db, DEFAULTS)

  -- keep old structure intact; no flattening needed
end

-- -----------------------------
-- Specs
-- -----------------------------
local function initSpecsIfNeeded()
  if type(db.Specs) ~= "table" then db.Specs = {} end

  local n = GetNumSpecializations(false, false) or 0
  if n <= 0 then return end

  -- rebuild if empty or wrong size
  if #db.Specs ~= n then
    for i = 1, #db.Specs do db.Specs[i] = nil end
    for i = 1, n do
      local _, name, _, icon = GetSpecializationInfo(i)
      db.Specs[i] = {
        specName = name or ("Spec " .. i),
        specNumber = i,
        iconPath = icon,
        specEnabled = true,
      }
    end
    return
  end

  -- ensure fields exist
  for i = 1, n do
    local spec = db.Specs[i]
    if type(spec) ~= "table" then
      spec = {}
      db.Specs[i] = spec
    end
    local _, name, _, icon = GetSpecializationInfo(i)
    spec.specName = spec.specName or name or ("Spec " .. i)
    spec.specNumber = spec.specNumber or i
    spec.iconPath = spec.iconPath or icon
    if spec.specEnabled == nil then spec.specEnabled = true end
  end
end

local function currentSpecIndex()
  local idx = GetSpecialization()
  if not idx or idx < 1 then return nil end
  return idx
end

local function isSpecEnabled()
  if type(db.Specs) ~= "table" or #db.Specs == 0 then return true end
  local idx = currentSpecIndex()
  if not idx then return true end
  local spec = db.Specs[idx]
  if type(spec) ~= "table" then return true end
  return spec.specEnabled ~= false
end

local function getCurrentSpecName()
  local idx = currentSpecIndex()
  if not idx or type(db.Specs) ~= "table" or type(db.Specs[idx]) ~= "table" then
    return "Current Spec"
  end
  return db.Specs[idx].specName or "Current Spec"
end

-- -----------------------------
-- State helpers
-- -----------------------------
local function booleanToString(v)
  if v then
    return "|cFF00FF00Enabled|r"
  else
    return "|cFFFF0000Disabled|r"
  end
end

local function sheathStateToString(unsheathed)
  if unsheathed then
    return "|cFF00FF00Unsheathed|r"
  else
    return "|cFFFF0000Sheathed|r"
  end
end

local function stayUnsheathedIsEnabled()
  return db.EnabledState == true
end

local function isCityEnabled()
  if IsResting() then
    return db.CityUnsheathed == true
  end
  return true
end

local function isSheathed()
  return GetSheathState() == 1
end

local function inVehicle()
  return UnitInVehicle("player") == true
end

local function isSwimmingMoving()
  local speed = GetUnitSpeed("player") or 0
  return IsSwimming() and speed > 0
end

-- -----------------------------
-- Pseudo-vehicle detection (safe vs "secret" indices)
-- -----------------------------
local PSEUDO_VEHICLES = {
  [196768] = true, [109076] = true, [294384] = true, [294383] = true,
  [278499] = true, [186530] = true, [148773] = true, [125883] = true,
  [221883] = true, [254471] = true, [254472] = true, [254473] = true,
  [254474] = true, [221887] = true, [363608] = true, [276111] = true,
  [276112] = true, [453804] = true, [221886] = true, [221885] = true,
  [444347] = true, [445163] = true, [121183] = true, [318452] = true,
  [172027] = true, [172052] = true, [172047] = true, [172049] = true,
  [172053] = true, [455494] = true, [50493] = true, [196783] = true,
  [1214519] = true, [346012] = true, [128150] = true, [399041] = true,
  [392700] = true,
}

local function inPseudoVehicle()
  -- Prefer C_UnitAuras (Retail), fallback to UnitAura if needed
  if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    local i = 1
    while true do
      local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
      if not aura then break end

      -- keep spellId read + table index inside pcall (spellId can be "secret")
      local ok, isPseudo = pcall(function()
        local sid = aura.spellId
        return sid and PSEUDO_VEHICLES[sid] == true
      end)

      if ok and isPseudo then
        return true
      end

      i = i + 1
    end
    return false
  end

  -- Fallback path (older clients)
  local i = 1
  while true do
    local name, _, _, _, _, _, _, _, _, spellId = UnitAura("player", i, "HELPFUL")
    if not name then break end
    local ok, isPseudo = pcall(function()
      return spellId and PSEUDO_VEHICLES[spellId] == true
    end)
    if ok and isPseudo then return true end
    i = i + 1
  end
  return false
end

-- -----------------------------
-- Core logic (never accidentally sheath)
-- -----------------------------
local function sheathConditionsAreMet()
  return stayUnsheathedIsEnabled()
    and isSpecEnabled()
    and isCityEnabled()
    and not InCombatLockdown()
    and not inVehicle()
    and not inPseudoVehicle()
    and not isSwimmingMoving()
end

local function tryUnsheath()
  if not isSheathed() then return end
  if not sheathConditionsAreMet() then return end
  ToggleSheath()
end

-- -----------------------------
-- Timers (C_Timer)
-- -----------------------------
local ticker
local function stopTicker()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

local function startTicker()
  stopTicker()

  local interval = tonumber(db.SheathStateCheckTimerInSeconds) or 2
  if interval < 1 then interval = 1; db.SheathStateCheckTimerInSeconds = 1 end

  ticker = C_Timer.NewTicker(interval, function()
    tryUnsheath()
  end)
end

-- -----------------------------
-- Mount/dismount handling
-- -----------------------------
local alreadyUnsheathedAfterDismount = false

local function onMountDisplayChanged()
  if IsMounted() then
    alreadyUnsheathedAfterDismount = false
    return
  end

  -- first dismount tick only
  if not alreadyUnsheathedAfterDismount then
    tryUnsheath()
    alreadyUnsheathedAfterDismount = true
  end
end

-- -----------------------------
-- Slash commands
-- -----------------------------
local function printHowToShowOptions()
  print('Use "/su help" to show options.')
end

local function printOptionMenu()
  print("---------------------------------------------")
  print("StayUnsheathed options menu.")
  print("Available options")
  print("/su help (Shows this menu)")
  print("/su info or /su status (Prints current settings)")
  print("/su enable (Enables the addon)")
  print("/su disable (Disables the addon)")
  print("/su toggle (Toggles the addon)")
  print("/su togglespec (Disables/Enables unsheathing in your current spec)")
  print("/su togglecity or /su togglecities (Toggles staying unsheathed in cities)")
  print("/su setchecktimer X (Checks every X seconds; minimum 1)")
  print("---------------------------------------------")
end

local function printStatus()
  print("StayUnsheathed is: " .. booleanToString(stayUnsheathedIsEnabled()))

  if type(db.Specs) == "table" then
    for i = 1, #db.Specs do
      local s = db.Specs[i]
      if type(s) == "table" then
        local icon = s.iconPath and ("|T" .. s.iconPath .. ":16|t ") or ""
        local name = s.specName or ("Spec " .. i)
        print(icon .. name .. " is: " .. booleanToString(s.specEnabled ~= false))
      end
    end
  end

  print("You are staying " .. sheathStateToString(db.CityUnsheathed == true) .. " in cities.")
  print("Checking sheath state every " .. tostring(db.SheathStateCheckTimerInSeconds) .. " seconds.")
end

local function toggleEnable()
  db.EnabledState = not stayUnsheathedIsEnabled()
  if stayUnsheathedIsEnabled() then
    startTicker()
    tryUnsheath()
  else
    stopTicker()
  end
  print("StayUnsheathed is now " .. booleanToString(stayUnsheathedIsEnabled()) .. ".")
end

local function enableStayUnsheathed()
  db.EnabledState = true
  startTicker()
  tryUnsheath()
  print("StayUnsheathed is now " .. booleanToString(true) .. ".")
end

local function disableStayUnsheathed()
  db.EnabledState = false
  stopTicker()
  print("StayUnsheathed is now " .. booleanToString(false) .. ".")
end

local function toggleSpec()
  initSpecsIfNeeded()
  local idx = currentSpecIndex()
  if not idx or type(db.Specs) ~= "table" or type(db.Specs[idx]) ~= "table" then
    print("No specialization detected yet.")
    return
  end

  db.Specs[idx].specEnabled = not (db.Specs[idx].specEnabled ~= false)
  print("StayUnsheathed is now " .. booleanToString(isSpecEnabled()) .. " for " .. getCurrentSpecName() .. ".")
end

local function toggleCity()
  db.CityUnsheathed = not (db.CityUnsheathed == true)
  print("You are now staying " .. sheathStateToString(db.CityUnsheathed == true) .. " in cities.")
end

local function setCheckTimer(arg)
  local newWaitTime = tonumber(arg)
  local minimumWaitTime = 1

  if not newWaitTime then
    print("Usage: /su setchecktimer X (X must be a number >= 1)")
    return
  end

  if newWaitTime >= minimumWaitTime then
    db.SheathStateCheckTimerInSeconds = newWaitTime
    if stayUnsheathedIsEnabled() then startTicker() end
    print("CheckTimer set to " .. tostring(db.SheathStateCheckTimerInSeconds) .. " seconds.")
  else
    print("CheckTimer requires a number >= " .. minimumWaitTime .. " second.")
  end
end

local function handleSlash(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")

  if msg == "" then
    printHowToShowOptions()
    return
  end

  local cmd, rest = msg:match("^(%S+)%s*(.-)$")
  cmd = cmd or msg
  rest = rest or ""

  if cmd == "help" or cmd == "options" then
    printOptionMenu()
  elseif cmd == "enable" then
    enableStayUnsheathed()
  elseif cmd == "disable" then
    disableStayUnsheathed()
  elseif cmd == "toggle" then
    toggleEnable()
  elseif cmd == "togglespec" then
    toggleSpec()
  elseif cmd == "togglecity" or cmd == "togglecities" then
    toggleCity()
  elseif cmd == "info" or cmd == "status" then
    printStatus()
  elseif cmd == "setchecktimer" then
    setCheckTimer(rest)
  else
    print('Command not found. Try "/su help" for usage.')
  end
end

SLASH_STAYUNSHEATHED1 = "/stayunsheathed"
SLASH_STAYUNSHEATHED2 = "/su"
SlashCmdList["STAYUNSHEATHED"] = handleSlash

-- -----------------------------
-- Events
-- -----------------------------
local EVENTS = {
  "ADDON_LOADED",
  "PLAYER_LOGIN",
  "PLAYER_REGEN_ENABLED",
  "LOOT_CLOSED",
  "AUCTION_HOUSE_CLOSED",
  "UNIT_EXITED_VEHICLE",
  "BARBER_SHOP_CLOSE",
  "PLAYER_ENTERING_WORLD",
  "UNIT_AURA",
  "QUEST_ACCEPTED",
  "QUEST_FINISHED",
  "MERCHANT_CLOSED",
  "PLAYER_MOUNT_DISPLAY_CHANGED",
}

for _, ev in ipairs(EVENTS) do
  SU:RegisterEvent(ev)
end

SU:SetScript("OnEvent", function(_, event, a1)
  if event == "ADDON_LOADED" then
    if a1 ~= ADDON_NAME then return end
    initDB()
    return
  end

  if not db then return end

  if event == "PLAYER_LOGIN" then
    initSpecsIfNeeded()

    -- mute sheath/unsheath sounds (as in your current code):contentReference[oaicite:1]{index=1}
    for _, soundID in ipairs({ 567473, 567498, 567456, 567430 }) do
      MuteSoundFile(soundID)
    end

    alreadyUnsheathedAfterDismount = false

    if stayUnsheathedIsEnabled() then
      startTicker()
      tryUnsheath()
    end
    return
  end

  if event == "PLAYER_MOUNT_DISPLAY_CHANGED" then
    onMountDisplayChanged()
    return
  end

  if event == "UNIT_AURA" then
    -- only react to player's auras (a1 == unit)
    if a1 == "player" then
      tryUnsheath()
    end
    return
  end

  -- all other events: attempt unsheath safely (won't sheath by accident)
  tryUnsheath()
end)