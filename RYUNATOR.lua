local mem = manager:machine().devices[":maincpu"].spaces["program"]

-- Player stats dict
local p1_stats, p2_stats = {}, {}
-- Memory address offset to differentiate p1 and p2
local p_offset = 0x0300
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
-- The parameter represents which player's info you want, indexed from 0.
function get_pos_x(player_num)
    return mem:read_i16(0xFF83C4 + (p_offset * player_num))
end

function get_health(player_num)
    return mem:read_i16(0xFF83EA + (p_offset * player_num))
end

function get_round_start(player_num)
    return mem:read_i16(0xFF83EE + (p_offset * player_num))
end

function get_pos_y(player_num)
    return mem:read_i16(0xFF83C8 + (p_offset * player_num))
end

function get_defense_value(player_num)
    return mem:read_i16(0xFF83C4 + (p_offset * player_num))
end

function is_player_midair(player_num)
    return mem:read_i16(0xFF853F + (p_offset * player_num))
end

function get_histop_time()
    return mem:read_i16(0xFF8405 + (p_offset * player_num))
end

function get_player_distance()
    return mem:read_i16(0xFF8540)
end

--[[
  State?

  20 (00010100) - being thrown
	14 (00001110) - hitstun OR blockstun
	12 (00001100) - special move
	10 (00001010) - attacking OR throwing
	8  (00001000) - blocking (not hit yet)
	6  (00000110) - wakeup (getting up after being thrown)
	4  (00000100) - jumping
	2  (00000010) - crouching
	0  (00000000) - standing
]]--
function get_player_state(player_num)
    return mem:read_i8(0xFF83C1 + (p_offset * player_num))
end

function get_timer()
    return tonumber(string.format("%x", mem:read_u8(0xFF8ABE)))
end

-- 0 = no block, 1 = standing block, 2 = crouching block
function get_blocking(player_num)
    return get_animation_byte(player_num, 0x11, 1)
end

-- 0 = standing, 1 = crouching
function get_crouching(player_num)
    return get_animation_byte(player_num, 0x12, 1)
end

-- Player, what byte to start reading from in the 24 byte sequence, how many bytes to read (1, 2, 4)
function get_animation_byte(player_num, byte, to_read)
    anim_pointer = mem:read_u32(0xFF83D8 + (p_offset * player_num))
    
    if to_read == 1 then
      return mem:read_u8(anim_pointer + byte)
    elseif to_read == 2 then
      return mem:read_u16(anim_pointer + byte)
    else
      return mem:read_u32(anim_pointer + byte)
    end
end

function get_hitbox_attack_byte(player_num, byte)
    hitbox_info = get_hitbox_info(player_num)
    
    -- Offset for atk hitboxes
    attack_hitbox_offset = mem:read_u16(hitbox_info + 0x08)
    attack_hitbox_list = hitbox_info + attack_hitbox_offset
    
    -- Offset defined in animation data
    attack_hitbox_list_offset = get_animation_byte(player_num, 0x0C, 1)

    -- multiply by the size of atk hitboxes (12 bytes)
    curr_attack_hitbox = attack_hitbox_list + (attack_hitbox_list_offset * 12)
    
    -- Get the requested byte (atk hitboxes are defined by 12 bytes)
    return mem:read_u8(curr_attack_hitbox + byte)
end

function get_hitbox_info(player_num)
    hitbox_info_pointer = mem:read_u32(0xFF83F2 + (p_offset * player_num))
    
    return hitbox_info_pointer
end

-- player_num = player attacking
-- 0 = no block, 1 = should block high, 2 = should block low
function get_attack_block(player_num)
    if get_animation_byte(player_num, 0x0C, 1) == 0 then
      return 0
    end
    
    attack_ex = get_hitbox_attack_byte(player_num, 0x7)
    
    if attack_ex == 0 or attack_ex == 1 or attack_ex == 3 then
      return 2
    elseif attack_ex == 2 then
      return 1
    end
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
    if get_animation_byte(0, 0x0C, 1) ~= 0 then
      print(get_attack_block(0))
    end
    
    --p1_stats['x'] = get_p1_screen_x
    --p1_stats['y'] = get_p1_screen_y

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
--[[
    local distance = get_player_distance()

    if distance > 150 then
        p1_hadouken()
    elseif distance > 90 and distance < 100 then
        p1_tatsumaki()
    elseif distance > 1 and distance < 10 then
        p1_shoryuken()
    end
]]--
end

-- Initialize controller
map_input()
-- Load savestate
manager:machine():load("1");

-- main will be called after every frame
emu.register_frame(main)