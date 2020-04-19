local robot = require('robot')
local component = require('component')
local inv = component.inventory_controller

local chests = {
  {
    x = 0,
    y = 0,
    z = -1,
  },

  {
    x = 0,
    y = 0,
    z = -2,
  }
}


-- itemid -> array {
--   {chest_pointer, slot, count}
--   {chest_pointer, slot, count},
--   ...
--   }
local locations = {
  ['minecraft:stone'] = {
    {chests[1], 1, 63},
    {chests[1], 2, 31},
    {chests[2], 1, 15}
  }
}

-- Represents a minecraft chest (single or double)
-- NOTE: If the chest is manipulated outside of this API, our database will become out of sync.
-- to remedy this you can call chest:rescan() when the chest items have changed.
local chest = {}

-- location is {x, y, z, orientation}
-- orientation is 0-3 (north, east, south, west)
-- if the orientation does not matter (aka up/down) just omit orientation.
--[[
chest:new {
  location = {0, 2, 3, 0},
  side = sides.bottom,
  slots = {
    {'minecraft:stone', 63}, -- 63 stone in slot 1
    {'minecraft:stone', 31}, -- 31 stone in slot 2
    ...
  },
}
]]

function chest:new(t)
  t.slots = t.slots or {}
  assert(type(t.side) == 'number', 'side must be a number')
  assert(type(t.invsize) == 'number', 'invsize must be a number')
  assert(type(t.location) == 'table', 'location must be a number')

  setmetatable(t, {__index = chest})
  return t
end

-- Requires that we are next to the chest.
-- put() will automatically find free space in the chest, or if no
-- space is available, then put() will return nil, plus an error.
function chest:put(internal_slot, amount)
  local info = inv.getStackInInternalSlot(internal_slot)
  if info == nil then
    return nil, 'oopsie woopsie no item in internal slot ' .. tostring(internal_slot)
  end

  if info['size'] < amount then
    return nil, ('have %d of %s, want %d'):format(info['size'], info['name'], amount)
  end

  local slots_with_space = {}

  -- find space in our inventory, we decrement amount with each space found.
  for slot=1,self.invsize do
    local slot_info = inv.getStackInSlot(self.side, slot)
    if self.slots[slot] == nil then
      amount = amount - 64
      table.insert(slots_with_space, {slot, 64})
      break
    elseif slot_info['size'] < slot_info['maxSize'] then
      amount  = amount - (slot_info['maxSize'] - slot_info['size'])
      table.insert(slots_with_space, slot)
      if amount <= 0 then break end
    end
  end

  if amount > 0 then
    return nil, ('oopsie!!! no space in chest %s, need %d more slots'):format(info['name'], amount)
  end

  -- we have space! deposit the items and change our internal state to reflect the deposits.

  local selected_slot = robot.select(internal_slot)
  if selected_slot ~= internal_slot then
    return nil, ('failed to select slot %d (out of bounds?)'):format(internal_slot)
  end

  for _, x in ipairs(slots_with_space) do
    local slot, free_space = x[1], x[2]
    local ok, err = inv.dropIntoSlot(self.side, slot, free_space)
    if not ok then return nil, err end
    -- success! update our db of the chest's contents.
    if self.slots[slot] == nil then
      self.slots[slot] = {info['name'], free_space}
    else
      self.slots[slot][2] = self.slots[slot][2] + free_space
    end
  end

  return true
end

-- NOTE: This assumes we are already at the chest. if you need to go to the chest
-- then you can call r.moveTo(chest.location)) (assuming r is the coordanites api)
-- returns true for success, nil, error on failure
function chest:rescan()
  local inv_size, err = inv.getInventorySize(self.side)
  if not inv_size then return nil, err end

  for slot=1,inv_size do
    local info = inv.getStackInSlot(self.side, slot)
    if info ~= nil then
      self.slots[slot] = {info['name'], info['size']}
    end
  end
  return true
end

function chest:slots_with(item_id)
  local slots = {}
  for slot, item in pairs(self.slots) do
    if item[1] == item_id then
      -- NOTE: we return the index for self.slots, NOT a pointer to it
      -- TODO: maybe returning a pointer would make an easier API?
      table.insert(slots, slot)
    end
  end
  return slots
end

return {
  chest = chest,
}
