--!nonstrict
-- IdeaPad Fan Mode -- [[widget]] entry (bar).
--
-- Shows the current preset; click steps to the next one (normal -> game ->
-- quiet), right click steps back. The changes happen in service.luau.

local presets = require("./lib/presets.luau")

local SNAPSHOT = "fan.snapshot"
local COMMAND = "fan.command"

local snap = noctalia.state.get(SNAPSHOT) or { available = false }

-- A preset whose power profile was changed from elsewhere is "custom".
local function isCustom(p)
  return p ~= nil and snap.managesProfile and snap.profile ~= nil and snap.profile ~= p.profile
end

local function presetLabel(p)
  if not p then
    return noctalia.tr("preset.unknown")
  end
  if isCustom(p) then
    return noctalia.tr("preset.custom")
  end
  return noctalia.tr("preset." .. p.key)
end

local function render()
  local p = presets.find(snap.preset)
  local color = "on_surface"
  if not snap.available then
    color = "on_surface_variant"
  elseif p and p.key == "game" and not isCustom(p) then
    color = "primary"
  end

  local glyph = "car-fan"
  if p and not isCustom(p) then
    glyph = p.glyph
  elseif p then
    glyph = "adjustments"
  end

  local children = { ui.glyph({ name = glyph, color = color }) }
  if snap.available and noctalia.getConfig("show_label") ~= false and not barWidget.isVertical() then
    table.insert(children, ui.label({ text = presetLabel(p), color = color }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, children))

  if not snap.available then
    barWidget.setTooltip(noctalia.tr("error.not_found"))
    return
  end
  local rows = {
    { key = noctalia.tr("tooltip.preset"), value = presetLabel(p) },
  }
  if p then
    local fan = (p.fullSpeed and snap.fullSpeed) and "full" or tostring(p.fan)
    table.insert(rows, { key = noctalia.tr("tooltip.fan"), value = noctalia.tr("fan." .. fan) })
  end
  if snap.managesProfile and snap.profile then
    table.insert(rows, { key = noctalia.tr("tooltip.profile"), value = noctalia.tr("profile." .. snap.profile) })
  end
  if snap.temp then
    table.insert(rows, { key = noctalia.tr("tooltip.cpu_temp"), value = snap.temp .. " °C" })
  end
  table.insert(rows, { key = "", value = noctalia.tr("tooltip.hint") })
  barWidget.setTooltip(rows)
end

local function step(direction)
  if not snap.available then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("error.not_found"))
    return
  end
  -- The nonce makes a repeated request a new value, so the watch fires.
  noctalia.state.set(COMMAND, {
    action = "set",
    preset = presets.next(snap.preset or "normal", direction),
    nonce = os.clock() .. ":" .. math.random(),
  })
end

noctalia.state.watch(SNAPSHOT, function(value)
  if type(value) == "table" then
    snap = value
    render()
  end
end)

function update()
  render()
end

function onClick()
  step(1)
end

function onRightClick()
  step(-1)
end

render()
