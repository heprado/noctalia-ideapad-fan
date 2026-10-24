--!nonstrict
-- The fan modes the ideapad_acpi driver accepts in its fan_mode attribute
-- (drivers/platform/x86/lenovo/ideapad-laptop.c). 3 is rejected by the
-- driver, and 2 ("dust cleaning") is a short full-speed cycle the firmware
-- ends on its own, so it isn't part of the click cycle.
--
-- Reading fan_mode back is not reliable: on some models (e.g. IdeaPad Gaming
-- 3 15IMH05) the EC reports its own codes (133, 3, ...) instead of the value
-- written, so the plugin tracks the last mode it set rather than parsing it.

local M = {}

M.list = {
  { value = 0, key = "quiet", glyph = "car-fan-1" },
  { value = 1, key = "standard", glyph = "car-fan-2" },
  { value = 4, key = "max", glyph = "car-fan-3" },
}

-- Click order: standard -> max -> quiet -> standard.
M.cycle = { 1, 4, 0 }

function M.find(value)
  for _, m in ipairs(M.list) do
    if m.value == value then
      return m
    end
  end
  return nil
end

function M.next(value, step)
  local n = #M.cycle
  for i, v in ipairs(M.cycle) do
    if v == value then
      return M.cycle[((i - 1 + step) % n) + 1]
    end
  end
  return M.cycle[1]
end

return M
