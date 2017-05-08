local mem = manager:machine().devices[":maincpu"].spaces["program"]
-- Player Controller
-- Player stats dict
local p1_stats, p2_stats = {}, {}
-- Memory address offset to differentiate p1 and p2
local player_offset = 0x0300
-- Memory address offset for projectile slots
local projectile_offset = -0xC0
-- Combines ports IN1 and IN2
local controller
local controllers

local punches = {
    " Jab Punch",
    " Strong Punch",
    " Fierce Punch",
}
local kicks = {
    " Short Kick",
    " Forward Kick",
    " Roundhouse Kick",
}
-- Used to determine if we need to continue input for a special move accross several frames.
-- counts the frame of the current special move.
local special_move_frame = { ["P1"] = 0, ["P2"] = 0 }


-- 0: no special move
-- 1: Hadouken
-- 2: Tatsumaki
-- 3: Shoryuken
local curr_special_move = { ["P1"] = 0, ["P2"] = 0 }

----------------------
-- CONTROLLER INPUT --
----------------------
local function set_input(key)
    --    print("key is ".. key)
    --    for kp,p in pairs(controllers) do
    --        print("Values for table " .. kp)
    --        for k,b in pairs(p) do
    --            print(k .. " : " .. b.state)
    --        end
    --    end
    for name, button in pairs(controllers[key]) do
        button.field:set_value(button.state)
    end
end

local function clear_input(controller_to_update)
    local key = controller_to_update == 0 and "P1" or "P2"
    for button in pairs(controllers[key]) do
        controllers[key][button].state = 0
    end
    set_input(key)
end

local function map_input()
    controllers = {}
    controllers["P1"] = {}
    controllers["P2"] = {}
    -- Table with the arcade's ports
    local ports = manager:machine():ioport().ports

    -- Get input port for sticks and punches
    local IN1 = ports[":IN1"]
    -- Get input port for kicks
    local IN2 = ports[":IN2"]

    -- Iterate over fields (button names) and create button objects
    for field_name, field in pairs(IN1.fields) do
        local button = {}
        button.port = IN1
        button.field = field
        button.state = 0
        controllers[string.sub(field_name, 1, 2)][field_name] = button
    end


    -- Iterate over fields (button names) and create button objects
    for field_name, field in pairs(IN2.fields) do
        local button = {}
        button.port = IN2
        button.field = field
        button.state = 0
        controllers[string.sub(field_name, 1, 2)][field_name] = button
    end

    set_input("P1")
    set_input("P2")
end

--------------------------
-- END CONTROLLER INPUT --
--------------------------

----------------
-- MEM ACCESS --
----------------
-- The parameter represents which player's info you want, indexed from 0.

-- Player, what byte to start reading from in the 24 byte sequence, how many bytes to read (1, 2, 4)
function get_animation_byte(player_num, byte, to_read)
    anim_pointer = mem:read_u32(0xFF83D8 + (player_offset * player_num))

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
    hitbox_info_pointer = mem:read_u32(0xFF83F2 + (player_offset * player_num))

    return hitbox_info_pointer
end

function get_health(player_num)
    return mem:read_u16(0xFF83EA + (player_offset * player_num))
end

function get_round_start(player_num)
    return mem:read_u16(0xFF83EE + (player_offset * player_num))
end

function get_timer()
    return tonumber(string.format("%x", mem:read_u8(0xFF8ABE)))
end

--[[
  State?

  20 (00010100) - thrown / grounded
	14 (00001110) - hitstun OR blockstun
	12 (00001100) - special move
	10 (00001010) - attacking OR throwing
	8  (00001000) - blocking (not hit yet)
	6  (00000110) - ?
	4  (00000100) - jumping
	2  (00000010) - crouching
	0  (00000000) - standing
]] --
function get_player_state(player_num)
    return mem:read_u8(0xFF83C1 + (player_offset * player_num))
end

-- NN INPUTS --

function get_pos_x(player_num)
    return mem:read_u16(0xFF83C4 + (player_offset * player_num))
end

function get_pos_y(player_num)
    return mem:read_u16(0xFF83C8 + (player_offset * player_num))
end

function get_x_distance()
    return mem:read_u16(0xFF8540)
end

function get_y_distance()
    return mem:read_u16(0xFF8542)
end

function is_midair(player_num)
    return mem:read_u16(0xFF853F + (player_offset * player_num)) > 0
end

function is_thrown(player_num)
    return get_player_state(player_num) == 20
end

function is_crouching(player_num)
    return get_animation_byte(player_num, 0x12, 1) == 1
end

-- player_num = player blocking
-- 0 = no block, 1 = standing block, 2 = crouching block
function get_blocking(player_num)
    return get_animation_byte(player_num, 0x11, 1)
end

-- player_num = player attacking
-- 0 = no attack, 1 = should block high, 2 = should block low
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

function is_in_hitstun(player_num)
    return get_player_state(player_num) == 14 and get_blocking(player_num) == 0
end

-- Special move with invincibility OR waking up
function is_invincible(player_num)
    return get_animation_byte(player_num, 0x08, 1) == 0 and
            get_animation_byte(player_num, 0x09, 1) == 0 and
            get_animation_byte(player_num, 0x0A, 1) == 0 and
            get_animation_byte(player_num, 0x0D, 1) == 1
end

function is_cornered(player_num)
    return get_pos_x(player_num) > 935 or get_pos_x(player_num) < 345
end

-- 8 projectile slots, indexed from 0
function projectile_pos_x(projectile_slot)
    return mem:read_u16(0xFF98BC + (projectile_offset * projectile_slot))
end

function projectile_pos_y(projectile_slot)
    return mem:read_u16(0xFF98C0 + (projectile_offset * projectile_slot))
end

-- END NN INPUTS --

--------------------
-- END MEM ACCESS --
--------------------

----------------------
-- HELPER FUNCTIONS --
----------------------
function get_forward(player)
    local p1 = get_pos_x(0)
    local p2 = get_pos_x(1)

    if player == 0 then
        if p1 < p2 then
            return " Right"
        else
            return " Left"
        end
    else
        if p2 < p1 then
            return " Right"
        else
            return " Left"
        end
    end
end

function get_backward(player)
    local p1 = get_pos_x(0)
    local p2 = get_pos_x(1)

    if player == 0 then
        if p1 > p2 then
            return " Right"
        else
            return " Left"
        end
    else
        if p2 > p1 then
            return " Right"
        else
            return " Left"
        end
    end
end

--------------------------
-- END HELPER FUNCTIONS --
--------------------------


--------------------
-- PLAYER ACTIONS --
--------------------
function neutral_jump(controller_to_update)
    if not is_midair(controller_to_update) then
        local key = controller_to_update == 0 and "P1" or "P2"
        controllers[key]["P1 Up"].state = 1
        controllers[key]["P1 Left"].state = 0
        controllers[key]["P1 Right"].state = 0
        controllers[key]["P1 Down"].state = 0
        set_input(key)
    end
end

function quarter_circle_forward(controller_to_update, punch_type)
    local key = controller_to_update == 0 and "P1" or "P2"
    local forward = get_forward(controller_to_update)
    local attack = punches[punch_type]
    clear_input(controller_to_update)
    -- Determine input based on current frame
    if special_move_frame[key] == 0 then
        controllers[key][key .. " Down"].state = 1
    elseif special_move_frame[key] == 1 then
        controllers[key][key .. " Down"].state = 1
        controllers[key][key .. forward].state = 1
    elseif special_move_frame[key] == 2 then
        controllers[key][key .. forward].state = 1
        controllers[key][key .. attack].state = 1
    elseif special_move_frame[key] == 3 then
        special_move_frame[key] = 0

        -- Mark the move as finished
        curr_special_move[key] = 0
        clear_input(key)
    end

    set_input(key)
    
    if curr_special_move[key] ~= 0 then
        special_move_frame[key] = special_move_frame[key] + 1
    end
end

function quarter_circle_back(controller_to_update, kick_type)
    -- Determine input based on current frame
    local attack = kicks[kick_type]
    local key = controller_to_update == 0 and "P1" or "P2"
    local back = get_backward(controller_to_update)
    clear_input(controller_to_update)
    -- Determine input based on current frame
    if special_move_frame[key] == 0 then
        controllers[key][key .. " Down"].state = 1
    elseif special_move_frame[key] == 1 then
        controllers[key][key .. " Down"].state = 1
        controllers[key][key .. back].state = 1
    elseif special_move_frame[key] == 2 then
        controllers[key][key .. back].state = 1
        controllers[key][key .. attack].state = 1
    elseif special_move_frame[key] == 3 then
        special_move_frame[key] = 0

        -- Mark the move as finished
        curr_special_move[key] = 0
        clear_input(key)
    end

    set_input(key)
    
    if curr_special_move[key] ~= 0 then
        special_move_frame[key] = special_move_frame[key] + 1
    end
end

function z_move(controller_to_update, attack_type)
    local attack = punches[attack_type]
    local key = controller_to_update == 0 and "P1" or "P2"
    local forward = get_forward(controller_to_update)
    clear_input(controller_to_update)
    -- Determine input based on current frame
    if special_move_frame[key] == 0 then
        controllers[key][key .. forward].state = 1
    elseif special_move_frame[key] == 1 then
        controllers[key][key .. " Down"].state = 1
    elseif special_move_frame[key] == 2 then
        controllers[key][key .. forward].state = 1
        controllers[key][key .. " Down"].state = 1
        controllers[key][key .. attack].state = 1
    elseif special_move_frame[key] == 3 then
        special_move_frame[key] = 0

        -- Mark the move as finished
        curr_special_move[key] = 0
        clear_input(key)
    end

    set_input(key)
    
    if curr_special_move[key] ~= 0 then
        special_move_frame[key] = special_move_frame[key] + 1
    end
end

------------------------
-- END PLAYER ACTIONS --
------------------------

----------
-- NEAT --
----------
function fitness()
    return 0
end

--------------
-- END NEAT --
--------------

function p1_frame()
  
    -- Check if we're inputting a special move
    if curr_special_move["P1"] ~= 0 then
      
        -- Call corresponding special move
        if curr_special_move["P1"] == 1 then
            quarter_circle_forward(0, 2)
        elseif curr_special_move["P1"] == 2 then
            quarter_circle_back(0, 2)
        elseif curr_special_move["P1"] == 3 then
            z_move(0, 2)
        end

        return
    end
    
end

function p2_frame()
  
    -- Check if we're inputting a special move
    if curr_special_move["P2"] ~= 0 then
      
        -- Call corresponding special move
        if curr_special_move["P2"] == 1 then
            quarter_circle_forward(1, 2)
        elseif curr_special_move["P2"] == 2 then
            quarter_circle_back(1, 2)
        elseif curr_special_move["P2"] == 3 then
            z_move(1, 2)
        end

        return
    end
    
end

function main()
    -- Testing out special moves
    if get_timer() % 10 == 0 then
        curr_special_move["P1"] = 3
        curr_special_move["P2"] = 3
    end
  
    p1_frame()
    p2_frame()
end

-- Initialize controller
map_input()
-- Load savestate
manager:machine():load("1");

-- main will be called after every frame
emu.register_frame(main)