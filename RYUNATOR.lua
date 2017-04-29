local mem = manager:machine().devices[":maincpu"].spaces["program"]

-- Combines ports IN1 and IN2
local controller

-- Input port: IN1
local p1_stick_punches = {
  "P1 Up",
  "P1 Down",
  "P1 Left",
  "P1 Right",
  "P1 Jab Punch",
  "P1 Strong Punch",
  "P1 Fierce Punch",
}

-- Input port: IN2
local p1_kicks = {
  "P1 Short Kick",
  "P1 Forward Kick",
  "P1 Roundhouse Kick",
}

-- Used to determine if we need to continue input for a special move accross several frames.
-- counts the frame of the current special move.
local special_move_frame = 0

-- 0: no special move
-- 1: Hadouken
-- 2: Tatsumaki
-- 3: Shoryuken
local curr_special_move = 0

----------------------
-- CONTROLLER INPUT --
----------------------

local function set_input(buttons)
  for name, button in pairs(buttons) do
    button.field:set_value(button.state)
  end
end

local function clear_input()
  controller["P1 Up"].state = 0
  controller["P1 Left"].state = 0
  controller["P1 Right"].state = 0
  controller["P1 Down"].state = 0
  controller["P1 Jab Punch"].state = 0
  controller["P1 Strong Punch"].state = 0
  controller["P1 Fierce Punch"].state = 0
  controller["P1 Short Kick"].state = 0
  controller["P1 Forward Kick"].state = 0
  controller["P1 Roundhouse Kick"].state = 0
  
  set_input(controller)
end

local function map_input()
    controller = {}
    
    -- Table with the arcade's ports
    local ports = manager:machine():ioport().ports
    
    -- Get input port for sticks and punches
    local IN1 = ports[":IN1"]
    -- Get input port for kicks
    local IN2 = ports[":IN2"]
    
    -- Map stick and punches for P1
    for i = 1, #p1_stick_punches do
      -- Iterate over fields (button names) and create button objects
      for field_name, field in pairs(IN1.fields) do
        
        if field_name == p1_stick_punches[i] then
          local button = {}
          button.port = IN1
          button.field = field
          button.state = 0
          controller[p1_stick_punches[i]] = button
        end
        
      end
    end
    
    -- Map kicks for P1
    for i = 1, #p1_kicks do
      -- Iterate over fields (button names) and create button objects
      for field_name, field in pairs(IN2.fields) do
        
        if field_name == p1_kicks[i] then
          local button = {}
          button.port = IN2
          button.field = field
          button.state = 0
          controller[p1_kicks[i]] = button
        end
        
      end
    end
    
    set_input(controller)
end

--------------------------
-- END CONTROLLER INPUT --
--------------------------

----------------
-- MEM ACCESS --
----------------

function get_p1_screen_x()
  return mem:read_i16(0xFF83C4)
end

function get_player_distance()
  return mem:read_i16(0xFF8540)
end

--------------------
-- END MEM ACCESS --
--------------------

----------------
-- P1 ACTIONS --
----------------

function p1_neutral_jump()
  controller["P1 Up"].state = 1
  controller["P1 Left"].state = 0
  controller["P1 Right"].state = 0
  controller["P1 Down"].state = 0
  
  set_input(controller)
end

function p1_hadouken()
  -- Determine input based on current frame
  if special_move_frame == 0 then
    clear_input()
    controller["P1 Down"].state = 1
    
    curr_special_move = 1
  elseif special_move_frame == 1 then
    controller["P1 Down"].state = 1
    controller["P1 Right"].state = 1
  elseif special_move_frame == 2 then
    controller["P1 Down"].state = 0
    controller["P1 Right"].state = 1
    controller["P1 Fierce Punch"].state = 1
  end
  
  set_input(controller)
  special_move_frame = special_move_frame + 1
  
  if special_move_frame == 3 then
    -- Mark the move as finished
    curr_special_move = 0
  end
  
end

function p1_tatsumaki()
  -- Determine input based on current frame
  if special_move_frame == 0 then
    clear_input()
    controller["P1 Down"].state = 1
    
    curr_special_move = 2
  elseif special_move_frame == 1 then
    controller["P1 Down"].state = 1
    controller["P1 Left"].state = 1
  elseif special_move_frame == 2 then
    controller["P1 Down"].state = 0
    controller["P1 Left"].state = 1
    controller["P1 Roundhouse Kick"].state = 1
  end
  
  set_input(controller)
  special_move_frame = special_move_frame + 1
  
  if special_move_frame == 3 then
    -- Mark the move as finished
    curr_special_move = 0
  end
  
end

function p1_shoryuken()
  -- Determine input based on current frame
  if special_move_frame == 0 then
    clear_input()
    controller["P1 Right"].state = 1
    
    curr_special_move = 3
  elseif special_move_frame == 1 then
    controller["P1 Down"].state = 1
    controller["P1 Right"].state = 0
  elseif special_move_frame == 2 then
    controller["P1 Down"].state = 1
    controller["P1 Right"].state = 1
    controller["P1 Fierce Punch"].state = 1
  end
  
  set_input(controller)
  special_move_frame = special_move_frame + 1
  
  if special_move_frame == 3 then
    -- Mark the move as finished
    curr_special_move = 0
  end
  
end

--------------------
-- END P1 ACTIONS --
--------------------

function main()
  -- Check if we're inputting a special move
  if special_move_frame > 0 then
    
    -- Call corresponding special move
    -- Clear the input if we just finished inputting a special move
    if curr_special_move == 0 then
      clear_input()
      special_move_frame = 0
    elseif curr_special_move == 1 then
      p1_hadouken()
    elseif curr_special_move == 2 then
      p1_tatsumaki()
    elseif curr_special_move == 3 then
      p1_shoryuken()
    end
    
    return
  end
  
  local distance = get_player_distance()
    
  if distance > 150 then
    p1_hadouken()
  elseif distance > 90 and distance < 100 then
    p1_tatsumaki()
  elseif distance > 1 and distance < 10 then
    p1_shoryuken()
  end
  
end

-- Initialize controller
map_input()
-- main will be called after every frame
emu.register_frame(main)