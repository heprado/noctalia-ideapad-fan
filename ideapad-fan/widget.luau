--!nonstrict
-- IdeaPad Fan Mode -- [[widget]] entry (bar).
--
-- Shows the current fan mode; click steps to the next one (standard -> max
-- -> quiet), right click steps back. The writes happen in service.luau.

local modes = require("./lib/modes.luau")

local SNAPSHOT = "fan.snapshot"
local COMMAND = "fan.command"

local snap = noctalia.state.get(SNAPSHOT) or { available = false }

local function modeLabel(m)
  return m and noctalia.tr("mode." .. m.key) or noctalia.tr("mode.unknown")
end

local function render()
  local m = modes.find(snap.mode)
  local color = "on_surface"
  if not snap.available then
    color = "on_surface_variant"
  elseif m and m.key == "max" then
    color = "primary"
  end

  local children = { ui.glyph({ name = m and m.glyph or "car-fan", color = color }) }
  if snap.available and noctalia.getConfig("show_label") ~= false and not barWidget.isVertical() then
    table.insert(children, ui.label({ text = modeLabel(m), color = color }))
  end

  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, children))

  if not snap.available then
    barWidget.setTooltip(noctalia.tr("error.not_found"))
    return
  end
  local rows = { { key = noctalia.tr("tooltip.mode"), value = modeLabel(m) } }
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
    value = modes.next(snap.mode or 1, direction),
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
