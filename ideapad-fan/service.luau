--!nonstrict
-- IdeaPad Fan Mode -- [[service]] entry.
--
-- Owns every change, so several bar widgets (one per output) never race.
-- Widgets ask for a preset through the COMMAND state key; the service writes
-- fan_mode, sets the power profile, remembers the preset in the plugin data
-- dir and publishes SNAPSHOT. On start it reapplies the saved preset, since
-- the firmware resets the fan mode on boot.

local presets = require("./lib/presets.luau")

local SNAPSHOT = "fan.snapshot"
local COMMAND = "fan.command"

local DRIVER_DIR = "/sys/bus/platform/drivers/ideapad_acpi"
local ATTR_NAME = "fan_mode"
local POLL_MS = 5000

-- Installed by the NixOS module's fullSpeed option; polkit lets the
-- ideapad-fan group start and stop it.
local FULL_SPEED_UNIT = "ideapad-fan-full-speed.service"
local UNIT_DIRS = { "/etc/systemd/system", "/run/systemd/system", "/usr/lib/systemd/system", "/lib/systemd/system" }

local snapshot = {
  available = false, -- fan_mode exists
  preset = nil, -- last preset applied (see lib/presets.luau on why not read back)
  profile = nil, -- current power-profiles-daemon profile, nil if unknown
  temp = nil, -- CPU package temperature, °C
}

-- The ACPI instance name (e.g. "VPC2004:00") is discovered, not hardcoded.
local function findAttr()
  local entries = noctalia.listDir(DRIVER_DIR)
  if not entries then
    return nil
  end
  for _, name in ipairs(entries) do
    local path = DRIVER_DIR .. "/" .. name .. "/" .. ATTR_NAME
    if noctalia.fileExists(path) then
      return path
    end
  end
  return nil
end

local function findCpuTempPath()
  local base = "/sys/class/thermal"
  local zones = noctalia.listDir(base)
  if not zones then
    return nil
  end
  for _, zone in ipairs(zones) do
    local kind = noctalia.readFile(base .. "/" .. zone .. "/type")
    if kind and noctalia.string.trim(kind) == "x86_pkg_temp" then
      return base .. "/" .. zone .. "/temp"
    end
  end
  return nil
end

local attrPath = findAttr()
local tempPath = findCpuTempPath()

local function manageProfile()
  return noctalia.getConfig("manage_power_profile") ~= false and noctalia.commandExists("powerprofilesctl")
end

local function fullSpeedUnitExists()
  for _, dir in ipairs(UNIT_DIRS) do
    if noctalia.fileExists(dir .. "/" .. FULL_SPEED_UNIT) then
      return true
    end
  end
  return false
end

local hasFullSpeedUnit = fullSpeedUnitExists()

local function manageFullSpeed()
  return hasFullSpeedUnit and noctalia.getConfig("full_speed_in_game") ~= false and noctalia.commandExists("systemctl")
end

-- restart rather than start: if the EC dropped full speed (boot, resume)
-- while the unit stayed active, start would be a no-op.
local function setFullSpeed(on)
  local verb = on and "restart" or "stop"
  noctalia.runAsync({ "systemctl", "--no-ask-password", verb, FULL_SPEED_UNIT }, function(res)
    if res.exitCode ~= 0 then
      noctalia.log("systemctl " .. verb .. " " .. FULL_SPEED_UNIT .. " failed: " .. (res.stderr or ""))
      noctalia.notifyError(noctalia.tr("title"), noctalia.tr("error.full_speed_failed"))
    end
  end)
end

local function savedPresetPath()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/preset") or nil
end

local function loadSavedPreset()
  local path = savedPresetPath()
  local contents = path and noctalia.readFile(path)
  local key = contents and noctalia.string.trim(contents)
  return key and presets.find(key) and key or nil
end

local function savePreset(key)
  local path = savedPresetPath()
  if path then
    noctalia.writeFile(path, key)
  end
end

local function publish()
  noctalia.state.set(SNAPSHOT, {
    available = snapshot.available,
    preset = snapshot.preset,
    profile = snapshot.profile,
    managesProfile = manageProfile(),
    fullSpeed = manageFullSpeed(),
    temp = snapshot.temp,
  })
end

local function readTemp()
  local raw = tempPath and noctalia.readFile(tempPath)
  local milli = raw and tonumber(noctalia.string.trim(raw))
  snapshot.temp = milli and math.floor(milli / 1000 + 0.5) or nil
end

local readingProfile = false
-- Bumped on every preset change: a read started before it reports the old
-- profile, so its result is dropped.
local profileGen = 0

-- The profile can also change from outside (Noctalia's own power profile
-- widget, powerprofilesctl), so it's polled; the widget then shows when it
-- no longer matches the preset.
local function readProfile()
  if readingProfile or not manageProfile() then
    return
  end
  readingProfile = true
  local gen = profileGen
  local launched = noctalia.runAsync({ "powerprofilesctl", "get" }, function(res)
    readingProfile = false
    if gen ~= profileGen then
      return
    end
    local out = res.exitCode == 0 and noctalia.string.trim(res.stdout or "") or ""
    snapshot.profile = out ~= "" and out or nil
    publish()
  end)
  if not launched then
    readingProfile = false
  end
end

local function applyPreset(key, quiet)
  local p = presets.find(key)
  if not attrPath or not p then
    return
  end

  -- Any fan_mode write puts the EC (15IMH05) into ~2 minutes of dipping the
  -- fans every ~11 s, even with SetFanCooling on, so a full-speed preset
  -- leaves fan_mode alone.
  local fullSpeed = manageFullSpeed() and p.fullSpeed == true
  if not fullSpeed then
    local ok, err = noctalia.writeFile(attrPath, tostring(p.fan))
    if not ok then
      noctalia.log("fan_mode write failed: " .. tostring(err))
      noctalia.notifyError(noctalia.tr("title"), noctalia.tr("error.write_failed", { path = attrPath }))
      return
    end
  end
  snapshot.preset = key
  savePreset(key)

  if manageFullSpeed() then
    setFullSpeed(fullSpeed)
  end

  if manageProfile() then
    snapshot.profile = p.profile -- optimistic; confirmed by the next read
    profileGen += 1
    noctalia.runAsync({ "powerprofilesctl", "set", p.profile }, function(res)
      if res.exitCode ~= 0 then
        noctalia.log("powerprofilesctl set failed: " .. (res.stderr or ""))
        noctalia.notifyError(noctalia.tr("title"), noctalia.tr("error.profile_failed", { profile = p.profile }))
      end
      readProfile()
    end)
  end

  publish()
  if not quiet then
    noctalia.notify(noctalia.tr("title"), noctalia.tr("preset." .. key))
  end
end

noctalia.state.watch(COMMAND, function(cmd)
  if type(cmd) ~= "table" or cmd.action ~= "set" then
    return
  end
  applyPreset(cmd.preset)
end)

function update()
  readTemp()
  readProfile()
  publish()
end

function onConfigChanged()
  readProfile()
  publish()
end

snapshot.available = attrPath ~= nil
snapshot.preset = loadSavedPreset()
readTemp()
publish()

if snapshot.preset and noctalia.getConfig("restore_on_start") ~= false then
  applyPreset(snapshot.preset, true)
else
  readProfile()
end

noctalia.setUpdateInterval(POLL_MS)
