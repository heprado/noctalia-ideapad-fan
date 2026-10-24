--!nonstrict
-- IdeaPad Fan Mode -- [[service]] entry.
--
-- Owns every write to fan_mode, so several bar widgets (one per output) never
-- race. Widgets ask for a mode through the COMMAND state key; the service
-- writes it, remembers it in the plugin data dir and publishes SNAPSHOT.
-- On start it reapplies the saved mode, since the firmware resets the fan
-- mode on boot.

local modes = require("./lib/modes.luau")

local SNAPSHOT = "fan.snapshot"
local COMMAND = "fan.command"

local DRIVER_DIR = "/sys/bus/platform/drivers/ideapad_acpi"
local ATTR_NAME = "fan_mode"
local POLL_MS = 5000

local snapshot = {
  available = false, -- fan_mode exists
  mode = nil, -- last mode written (see lib/modes.luau on why not read back)
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

local function savedModePath()
  local dir = noctalia.pluginDataDir()
  return dir and (dir .. "/mode") or nil
end

local function loadSavedMode()
  local path = savedModePath()
  local contents = path and noctalia.readFile(path)
  local value = contents and tonumber(noctalia.string.trim(contents))
  return value and modes.find(value) and value or nil
end

local function saveMode(value)
  local path = savedModePath()
  if path then
    noctalia.writeFile(path, tostring(value))
  end
end

local function readTemp()
  local raw = tempPath and noctalia.readFile(tempPath)
  local milli = raw and tonumber(noctalia.string.trim(raw))
  snapshot.temp = milli and math.floor(milli / 1000 + 0.5) or nil
end

local function publish()
  noctalia.state.set(SNAPSHOT, {
    available = snapshot.available,
    mode = snapshot.mode,
    temp = snapshot.temp,
  })
end

local function applyMode(value, quiet)
  if not attrPath or not modes.find(value) then
    return false
  end
  local ok, err = noctalia.writeFile(attrPath, tostring(value))
  if not ok then
    noctalia.log("fan_mode write failed: " .. tostring(err))
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("error.write_failed", { path = attrPath }))
    return false
  end
  snapshot.mode = value
  saveMode(value)
  publish()
  if not quiet then
    noctalia.notify(noctalia.tr("title"), noctalia.tr("mode." .. modes.find(value).key))
  end
  return true
end

noctalia.state.watch(COMMAND, function(cmd)
  if type(cmd) ~= "table" or cmd.action ~= "set" then
    return
  end
  applyMode(tonumber(cmd.value))
end)

function update()
  readTemp()
  publish()
end

function onConfigChanged() end

snapshot.available = attrPath ~= nil
snapshot.mode = loadSavedMode()
readTemp()
publish()

if snapshot.mode and noctalia.getConfig("restore_on_start") ~= false then
  applyMode(snapshot.mode, true)
end

noctalia.setUpdateInterval(POLL_MS)
