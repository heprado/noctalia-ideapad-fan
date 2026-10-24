--!nonstrict
-- Presets pair a firmware fan mode with a power-profiles-daemon profile
-- (which drives the firmware platform_profile and the CPU's EPP), so the fan
-- and how much heat CPU/GPU are allowed to make change together.
--
-- fan_mode values are the ones the ideapad_acpi driver accepts
-- (drivers/platform/x86/lenovo/ideapad-laptop.c): 0 quiet, 1 standard,
-- 4 efficient thermal dissipation. 3 is rejected, and 2 ("dust cleaning") is
-- a short full-speed cycle the firmware ends on its own, so neither is used.
--
-- Reading fan_mode back is not reliable: on some models (e.g. IdeaPad Gaming
-- 3 15IMH05) the EC reports its own codes (133, 3, ...) instead of the value
-- written, so the plugin tracks the last preset it applied rather than
-- parsing it.

local M = {}

M.list = {
  { key = "quiet", fan = 0, profile = "power-saver", glyph = "leaf" },
  { key = "normal", fan = 1, profile = "balanced", glyph = "car-fan" },
  { key = "game", fan = 4, profile = "performance", glyph = "device-gamepad-2" },
}

-- Click order: normal -> game -> quiet -> normal.
M.cycle = { "normal", "game", "quiet" }

function M.find(key)
  for _, p in ipairs(M.list) do
    if p.key == key then
      return p
    end
  end
  return nil
end

function M.next(key, step)
  local n = #M.cycle
  for i, k in ipairs(M.cycle) do
    if k == key then
      return M.cycle[((i - 1 + step) % n) + 1]
    end
  end
  return M.cycle[1]
end

return M
