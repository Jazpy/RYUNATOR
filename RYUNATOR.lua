local mem = manager:machine().devices[":maincpu"].spaces["program"]
-- Player Controller
-- Player stats dict
local p1_stats, p2_stats = {}, {}
-- Memory address offset to differentiate p1 and p2
local player_offset = 0x0300
-- Memory address offset for projectile slots
local projectile_offset = -0xC0
-- Combines ports IN1 and IN2
local pool
local controllers

local max_health = {}
local time_cornered = {}
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
local special_attacks = {
	" special 1",
	" special 2",
	" special 3",
}
--------------------
--- NEAT variables--
--------------------

local output_buttons = {
	" Up",
	" Right",
	" Left",
	" Down",
	" Jab Punch",
	" Strong Punch",
	" Fierce Punch",
	" Short Kick",
	" Forward Kick",
	" Roundhouse Kick",
	" special 1",
	" special 2",
	" special 3",
}

local gui = manager:machine().screens[":screen"]

gui_element = 6
Inputs = 40
Outputs = #output_buttons
Population = 300
DeltaDisjoint = 2.0
DeltaWeights = 0.4
DeltaThreshold = 1.0

StaleSpecies = 15

MutateConnectionsChance = 0.25
PerturbChance = 0.90
CrossoverChance = 0.75
LinkMutationChance = 2.0
NodeMutationChance = 0.50
BiasMutationChance = 0.40
StepSize = 0.1
DisableMutationChance = 0.4
EnableMutationChance = 0.2


MaxNodes = 1000000
-- Used to determine if we need to continue input for a special move accross several frames.
-- counts the frame of the current special move.
local special_move_frame = { ["P1"] = 0, ["P2"] = 0 }

-- 0: no special move
-- 1: Quarter Circle Forward
-- 2: Quarter Circle Back
-- 3: Z-Move
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
	local anim_pointer = mem:read_u32(0xFF83D8 + (player_offset * player_num))

	if to_read == 1 then
		return mem:read_u8(anim_pointer + byte)
	elseif to_read == 2 then
		return mem:read_u16(anim_pointer + byte)
	else
		return mem:read_u32(anim_pointer + byte)
	end
end

function get_hitbox_attack_byte(player_num, byte)
	local hitbox_info = get_hitbox_info(player_num)

	-- Offset for atk hitboxes
	local attack_hitbox_offset = mem:read_u16(hitbox_info + 0x08)
	local attack_hitbox_list = hitbox_info + attack_hitbox_offset

	-- Offset defined in animation data
	local attack_hitbox_list_offset = get_animation_byte(player_num, 0x0C, 1)

	-- multiply by the size of atk hitboxes (12 bytes)
	local curr_attack_hitbox = attack_hitbox_list + (attack_hitbox_list_offset * 12)

	-- Get the requested byte (atk hitboxes are defined by 12 bytes)
	return mem:read_u8(curr_attack_hitbox + byte)
end

function get_hitbox_info(player_num)
	local hitbox_info_pointer = mem:read_u32(0xFF83F2 + (player_offset * player_num))

	return hitbox_info_pointer
end

function get_health(player_num)
	return mem:read_u16(0xFF83EA + (player_offset * player_num))
end

function has_control(player_num)
	return mem:read_u16(0xFF83EE + (player_offset * player_num)) == 1
end

function get_timer()
	return tonumber(string.format("%x", mem:read_u8(0xFF8ABE)))
end

function is_round_finished()
	return mem:read_u16(0xFF8AC0) == 1
end

-- Default 0, 1 -> P1, 2 -> P2, 255 -> Draw
function get_round_winner()
	return mem:read_u8(0xFF8AC2)
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
	return num(mem:read_u16(0xFF853F + (player_offset * player_num)) > 0)
end

function is_thrown(player_num)
	return num(get_player_state(player_num) == 20)
end

function is_crouching(player_num)
	return num(get_animation_byte(player_num, 0x12, 1) == 1)
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

	local attack_ex = get_hitbox_attack_byte(player_num, 0x7)

	if attack_ex == 0 or attack_ex == 1 or attack_ex == 3 then
		return 2
	elseif attack_ex == 2 then
		return 1
	end
end

function is_in_hitstun(player_num)
	return num(get_player_state(player_num) == 14 and get_blocking(player_num) == 0)
end

-- Special move with invincibility OR waking up
function is_invincible(player_num)
	return num(get_animation_byte(player_num, 0x08, 1) == 0 and
			get_animation_byte(player_num, 0x09, 1) == 0 and
			get_animation_byte(player_num, 0x0A, 1) == 0 and
			get_animation_byte(player_num, 0x0D, 1) == 1)
end

function is_cornered(player_num)

	local pos_player = get_pos_x(player_num)
	local pos_other = get_pos_x((player_num + 1) % 2)

	if pos_player > 925 and get_forward(player_num) == " Left" then
		return 1
	elseif pos_player < 345 and get_forward(player_num) == " Right" then
		return 1
	end

	return 0
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

local function array_has_value(tab, val)
	for index, value in ipairs(tab) do
		if value == val then
			return true
		end
	end

	return false
end
function num(var)
	return var and 1 or 0
end

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

function start_round()
	clear_input(0)
	clear_input(1)
	manager:machine():load("1");
	max_health[1] = get_health(0) < 144 and 144 or get_health(0)
	max_health[2] = get_health(1) < 144 and 144 or get_health(1)
	time_cornered[1] = 0
	time_cornered[2] = 0



	local species = pool.species[pool.current_species]
	local genome = species.genomes[pool.current_genome]
	generate_network(genome)
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
-- x - min / max - min
function get_inputs(player_num)
	-- Without keys to ensure their order is always maintained
	local enemy = player_num == 0 and 1 or 0

	local input_table = {
		-- shared inputs
		(get_x_distance()) / (264),

		-- Own inputs
		(get_pos_x(player_num) - 420) / (990 - 420),
		(get_pos_y(player_num) - 40) / (120 - 40),
		get_health(player_num) / (max_health[(player_num + 1) % 2]),
		is_cornered(player_num),
		is_midair(player_num),
		is_thrown(player_num),
		is_in_hitstun(player_num),
		is_crouching(player_num),
		is_invincible(player_num),
		get_blocking(player_num) / 2,
		get_attack_block(player_num) / 2,

		-- Enemy inputs
		(get_pos_x(enemy) - 420) / (990 - 420),
		(get_pos_y(enemy) - 40) / (120 - 40),
		get_health(enemy) / (max_health[enemy + 1]),
		is_cornered(enemy),
		is_midair(enemy),
		is_thrown(enemy),
		is_in_hitstun(enemy),
		is_crouching(enemy),
		is_invincible(enemy),
		get_blocking(enemy) / 2,
		get_attack_block(enemy) / 2,
	}

	for i = 0, 7, 1 do
		table.insert(input_table, (projectile_pos_x(i) - 420) / (990 - 420))
		table.insert(input_table, (projectile_pos_y(i) - 40) / (120 - 40))
	end
	return input_table
end

function sigmoid(x)
	return 2 / (1 + math.exp(-x)) - 1
end

function new_innovation()
	pool.innovation = pool.innovation + 1
	return pool.innovation
end

function new_pool()
	local pool = {}
	pool.species = {}
	pool.generation = 0
	pool.innovation = Outputs
	pool.current_species = 1
	pool.current_genome = 1
	pool.current_frame = 0
	pool.curr = 0
	pool.max_fitness = 0

	return pool
end

function new_species()
	local species = {}
	species.top_fitness = 0
	species.staleness = 0
	species.genomes = {}
	species.average_fitness = 0

	return species
end

function basic_genome()
	local genome = new_genome()
	local innovation = 1

	genome.max_neuron = Inputs
	mutate(genome)

	return genome
end

function new_genome()
	local genome = {}
	genome.genes = {}
	genome.fitness = 0
	genome.adjusted_fitness = 0
	genome.network = {}
	genome.max_neuron = 0
	genome.global_rank = 0
	genome.mutation_rates = {}
	genome.mutation_rates["connections"] = MutateConnectionsChance
	genome.mutation_rates["link"] = LinkMutationChance
	genome.mutation_rates["bias"] = BiasMutationChance
	genome.mutation_rates["node"] = NodeMutationChance
	genome.mutation_rates["enable"] = EnableMutationChance
	genome.mutation_rates["disable"] = DisableMutationChance
	genome.mutation_rates["step"] = StepSize

	return genome
end


function copy_gene(gene)
	local gene2 = new_gene()
	gene2.into = gene.into
	gene2.out = gene.out
	gene2.weight = gene.weight
	gene2.enabled = gene.enabled
	gene2.innovation = gene.innovation

	return gene2
end

function new_gene()
	local gene = {}
	gene.into = 0
	gene.out = 0
	gene.weight = 0.0
	gene.enabled = true
	gene.innovation = 0

	return gene
end

function new_neuron()
	local neuron = {}
	neuron.incoming = {}
	neuron.value = 0.0

	return neuron
end

function generate_network(genome)
	local network = {}
	network.neurons = {}

	for i = 1, Inputs do
		network.neurons[i] = new_neuron()
	end

	for o = 1, Outputs do
		network.neurons[MaxNodes + o] = new_neuron()
	end

	table.sort(genome.genes, function(a, b)
		return (a.out < b.out)
	end)
	for i = 1, #genome.genes do
		local gene = genome.genes[i]
		if gene.enabled then
			if network.neurons[gene.out] == nil then
				network.neurons[gene.out] = new_neuron()
			end
			local neuron = network.neurons[gene.out]
			table.insert(neuron.incoming, gene)
			if network.neurons[gene.into] == nil then
				network.neurons[gene.into] = new_neuron()
			end
		end
	end

	genome.network = network
end

function evaluate_network(network, inputs, player_num)
	local key = player_num == 0 and "P1" or "P2"
	table.insert(inputs, 1)
	if #inputs ~= Inputs then
		print("Incorrect number of neural network inputs.")
		return {}
	end

	for i = 1, Inputs do
		network.neurons[i].value = inputs[i]
	end

	for _, neuron in pairs(network.neurons) do
		local sum = 0
		for j = 1, #neuron.incoming do
			local incoming = neuron.incoming[j]
			local other = network.neurons[incoming.into]
			sum = sum + incoming.weight * other.value
		end

		if #neuron.incoming > 0 then
			neuron.value = sigmoid(sum)
		end
	end

	local outputs = {}
	for o = 1, Outputs do
		local button = key .. output_buttons[o]
		if network.neurons[MaxNodes + o].value > 0 then
			outputs[button] = true
		else
			outputs[button] = false
		end
	end

	return outputs
end

function crossover(g1, g2)
	-- Make sure g1 is the higher fitness genome
	if g2.fitness > g1.fitness then
		tempg = g1
		g1 = g2
		g2 = tempg
	end

	local child = new_genome()

	local innovations2 = {}
	for i = 1, #g2.genes do
		local gene = g2.genes[i]
		innovations2[gene.innovation] = gene
	end

	for i = 1, #g1.genes do
		local gene1 = g1.genes[i]
		local gene2 = innovations2[gene1.innovation]
		if gene2 ~= nil and math.random(2) == 1 and gene2.enabled then
			table.insert(child.genes, copy_gene(gene2))
		else
			table.insert(child.genes, copy_gene(gene1))
		end
	end

	child.maxn_euron = math.max(g1.max_neuron, g2.max_neuron)

	for mutation, rate in pairs(g1.mutation_rates) do
		child.mutation_rates[mutation] = rate
	end

	return child
end

function random_neuron(genes, nonInput)
	local neurons = {}
	if not nonInput then
		for i = 1, Inputs do
			neurons[i] = true
		end
	end
	for o = 1, Outputs do
		neurons[MaxNodes + o] = true
	end
	for i = 1, #genes do
		if (not nonInput) or genes[i].into > Inputs then
			neurons[genes[i].into] = true
		end
		if (not nonInput) or genes[i].out > Inputs then
			neurons[genes[i].out] = true
		end
	end

	local count = 0
	for _, _ in pairs(neurons) do
		count = count + 1
	end
	local n = math.random(1, count)

	for k, v in pairs(neurons) do
		n = n - 1
		if n == 0 then
			return k
		end
	end

	return 0
end

function contains_link(genes, link)
	for i = 1, #genes do
		local gene = genes[i]
		if gene.into == link.into and gene.out == link.out then
			return true
		end
	end
end

-------------
-- Mutations--
-------------
function point_mutate(genome)
	local step = genome.mutation_rates["step"]

	for i = 1, #genome.genes do
		local gene = genome.genes[i]
		if math.random() < perturb_chance then
			gene.weight = gene.weight + math.random() * step * 2 - step
		else
			gene.weight = math.random() * 4 - 2
		end
	end
end

function link_mutate(genome, force_bias)
	local neuron1 = random_neuron(genome.genes, false)
	local neuron2 = random_neuron(genome.genes, true)

	local newLink = new_gene()
	if neuron1 <= Inputs and neuron2 <= Inputs then
		--Both input nodes
		return
	end
	if neuron2 <= Inputs then
		-- Swap output and input
		local temp = neuron1
		neuron1 = neuron2
		neuron2 = temp
	end

	newLink.into = neuron1
	newLink.out = neuron2
	if force_bias then
		newLink.into = Inputs
	end

	if contains_link(genome.genes, newLink) then
		return
	end
	newLink.innovation = new_innovation()
	newLink.weight = math.random() * 4 - 2

	table.insert(genome.genes, newLink)
end

function node_mutate(genome)
	if #genome.genes == 0 then
		return
	end

	genome.max_neuron = genome.max_neuron + 1

	local gene = genome.genes[math.random(1, #genome.genes)]
	if not gene.enabled then
		return
	end
	gene.enabled = false

	local gene1 = copy_gene(gene)
	gene1.out = genome.max_neuron
	gene1.weight = 1.0
	gene1.innovation = new_innovation()
	gene1.enabled = true
	table.insert(genome.genes, gene1)

	local gene2 = copy_gene(gene)
	gene2.into = genome.max_neuron
	gene2.innovation = new_innovation()
	gene2.enabled = true
	table.insert(genome.genes, gene2)
end

function enable_disable_mutate(genome, enable)
	local candidates = {}
	for _, gene in pairs(genome.genes) do
		if gene.enabled == not enable then
			table.insert(candidates, gene)
		end
	end

	if #candidates == 0 then
		return
	end

	local gene = candidates[math.random(1, #candidates)]
	gene.enabled = not gene.enabled
end

function mutate(genome)
	for mutation, rate in pairs(genome.mutation_rates) do
		if math.random(1, 2) == 1 then
			genome.mutation_rates[mutation] = 0.95 * rate
		else
			genome.mutation_rates[mutation] = 1.05263 * rate
		end
	end

	if math.random() < genome.mutation_rates["connections"] then
		point_mutate(genome)
	end

	local p = genome.mutation_rates["link"]
	while p > 0 do
		if math.random() < p then
			link_mutate(genome, false)
		end
		p = p - 1
	end

	p = genome.mutation_rates["bias"]
	while p > 0 do
		if math.random() < p then
			link_mutate(genome, true)
		end
		p = p - 1
	end

	p = genome.mutation_rates["node"]
	while p > 0 do
		if math.random() < p then
			node_mutate(genome)
		end
		p = p - 1
	end

	p = genome.mutation_rates["enable"]
	while p > 0 do
		if math.random() < p then
			enable_disable_mutate(genome, true)
		end
		p = p - 1
	end

	p = genome.mutation_rates["disable"]
	while p > 0 do
		if math.random() < p then
			enable_disable_mutate(genome, false)
		end
		p = p - 1
	end
end

function player_fitness(player_num)
	local enemy = player_num == 0 and 2 or 1
	local key = player_num == 0 and "P1" or "P2"

	local multiplier = math.ceil((get_timer() + 1) / 20)

	local damage_taken = max_health[player_num + 1] - get_health(player_num)
	local damage_made = max_health[enemy] - get_health(enemy - 1)
	local bonus = get_round_winner() == player_num + 1 and get_timer() * 5 or 0
	--[[	print("max health for " .. key .. " "..max_health[player_num +1 ] )
		print("health for " .. key .. " "..get_health(player_num))
		print("multiplier" .. multiplier)
		print("damage taken "..player_num + 1 .. " ".. damage_taken)
		print("damage made " .. enemy .. " ".. damage_made)
		print("Time cornered " .. time_cornered[enemy] /60)
		print("bonus" .. bonus)]]
	return multiplier * math.floor(2 * (time_cornered[enemy] / 60) - 3 * damage_taken + 5 * damage_made + bonus)
end



function disjoint(genes1, genes2)
	local i1 = {}
	for i = 1, #genes1 do
		local gene = genes1[i]
		i1[gene.innovation] = true
	end

	local i2 = {}
	for i = 1, #genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = true
	end

	local disjointGenes = 0
	for i = 1, #genes1 do
		local gene = genes1[i]
		if not i2[gene.innovation] then
			disjointGenes = disjointGenes + 1
		end
	end

	for i = 1, #genes2 do
		local gene = genes2[i]
		if not i1[gene.innovation] then
			disjointGenes = disjointGenes + 1
		end
	end

	local n = math.max(#genes1, #genes2)

	return disjointGenes / n
end

function weights(genes1, genes2)
	local i2 = {}
	for i = 1, #genes2 do
		local gene = genes2[i]
		i2[gene.innovation] = gene
	end

	local sum = 0
	local coincident = 0
	for i = 1, #genes1 do
		local gene = genes1[i]
		if i2[gene.innovation] ~= nil then
			local gene2 = i2[gene.innovation]
			sum = sum + math.abs(gene.weight - gene2.weight)
			coincident = coincident + 1
		end
	end

	return sum / coincident
end

function same_species(genome1, genome2)
	local dd = DeltaDisjoint * disjoint(genome1.genes, genome2.genes)
	local dw = DeltaWeights * weights(genome1.genes, genome2.genes)
	return dd + dw < DeltaThreshold
end

----------------
-- END MUTATION--
----------------
function rank_globally()
	local global = {}
	for s = 1, #pool.species do
		local species = pool.species[s]
		for g = 1, #species.genomes do
			table.insert(global, species.genomes[g])
		end
	end
	table.sort(global, function(a, b)
		return (a.fitness < b.fitness)
	end)

	for g = 1, #global do
		global[g].global_rank = g
	end
end

function total_average_fitness()
	local total = 0
	for s = 1, #pool.species do
		local species = pool.species[s]
		total = total + species.average_fitness
	end

	return total
end

--------------------------
-- EVOLUTION AND BREEDING--
--------------------------
function cull_species(cut_to_one)
	for s = 1, #pool.species do
		local species = pool.species[s]

		table.sort(species.genomes, function(a, b)
			return (a.fitness > b.fitness)
		end)

		local remaining = math.ceil(#species.genomes / 2)
		if cut_to_one then
			remaining = 1
		end
		while #species.genomes > remaining do
			table.remove(species.genomes)
		end
	end
end

function breed_child(species)
	local child = {}
	if math.random() < CrossoverChance then
		local g1 = species.genomes[math.random(1, #species.genomes)]
		local g2 = species.genomes[math.random(1, #species.genomes)]
		child = crossover(g1, g2)
	else
		local g = species.genomes[math.random(1, #species.genomes)]
		child = copyGenome(g)
	end

	mutate(child)

	return child
end

function remove_stale_species()
	local survived = {}

	for s = 1, #pool.species do
		local species = pool.species[s]

		table.sort(species.genomes, function(a, b)
			return (a.fitness > b.fitness)
		end)

		if species.genomes[1].fitness > species.topFitness then
			species.top_fitness = species.genomes[1].fitness
			species.staleness = 0
		else
			species.staleness = species.staleness + 1
		end
		if species.staleness < StaleSpecies or species.topFitness >= pool.maxFitness then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end

function remove_weak_species()
	local survived = {}

	local sum = total_average_fitness()
	for s = 1, #pool.species do
		local species = pool.species[s]
		local breed = math.floor(species.average_fitness / sum * Population)
		if breed >= 1 then
			table.insert(survived, species)
		end
	end

	pool.species = survived
end


function add_to_species(child)
	local found_species = false
	for s = 1, #pool.species do
		local species = pool.species[s]
		if not found_species and same_species(child, species.genomes[1]) then
			table.insert(species.genomes, child)
			found_species = true
		end
	end

	if not found_species then
		local child_species = new_species()
		table.insert(child_species.genomes, child)
		table.insert(pool.species, child_species)
	end
end

function new_generation()
	cull_species(false) -- Cull the bottom half of each species
	rank_globally()
	remove_stale_species()
	rank_globally()
	for s = 1, #pool.species do
		local species = pool.species[s]
		calculateAverageFitness(species)
	end
	remove_weak_species()
	local sum = total_average_fitness()
	local children = {}
	for s = 1, #pool.species do
		local species = pool.species[s]
		local breed = math.floor(species.averageFitness / sum * Population) - 1
		for i = 1, breed do
			table.insert(children, breedChild(species))
		end
	end
	cull_species(true) -- Cull all but the top member of each species
	while #children + #pool.species < Population do
		local species = pool.species[math.random(1, #pool.species)]
		table.insert(children, breedChild(species))
	end
	for c = 1, #children do
		local child = children[c]
		addToSpecies(child)
	end

	pool.generation = pool.generation + 1

	--writeFile("backup." .. pool.generation .. "." .. forms.gettext(saveLoadFile))
end

------------------------------
-- END EVOLUTION AND BREEDING--
------------------------------

------------------------------
--------- CURRENT GENOME-------
------------------------------
function initialize_pool()
	pool = new_pool()

	for i = 1, Population do
		local basic = basic_genome()
		add_to_species(basic)
	end
end

function next_genome()
	pool.current_genome = pool.current_genome + 1
	if pool.current_genome > #pool.species[pool.current_species].genomes then
		pool.current_genome = 1
		pool.current_species = pool.current_species + 1
		if pool.current_species > #pool.species then
			new_generation()
			pool.current_species = 1
		end
	end
end

function fitness_already_measured()
	local species = pool.species[pool.current_species]
	local genome = species.genomes[pool.current_genome]

	return genome.fitness ~= 0
end

------------------------------
--------- END CURRENT GENOME---
------------------------------
function evaluate_current(player_num)
	local key = player_num == 0 and "P1" or "P2"

	local species = pool.species[pool.current_species]
	local genome = species.genomes[pool.current_genome]

	local inputs = get_inputs(player_num)
	--	controllers[key]
	local net_response = evaluate_network(genome.network, inputs, player_num)

--	print(" ")
	for button_name, button_value in pairs(net_response) do
		local is_special_move = False
		local bv = num(button_value)

		if array_has_value(special_attacks, string.sub(button_name, 3)) then
			local special_move = string.match(button_name, "%d+")
			if bv == 1 then
				--print("Activating special move #".. special_move)
				curr_special_move[key] = special_move
			end
		else
--			print("Setting " .. button_name .. " as " .. bv)
			controllers[key][button_name].state = bv
		end
	end
	clear_input(key)
	set_input(key)
end

--------------
--- GUI ------
--------------
function draw_genome(genome, player_num)
	local network = genome.network
	local cells = {}
	local i = 1
	local cell = {}
	for dy = -gui_element, gui_element do
		for dx = -gui_element, gui_element do
			cell = {}
			cell.x = 50 + 5 * dx
			cell.y = 70 + 5 * dy
			cell.value = network.neurons[i].value
			cells[i] = cell
			i = i + 1
		end
	end
	local biasCell = {}
	biasCell.x = 80
	biasCell.y = 110
	biasCell.value = network.neurons[Inputs].value
	cells[Inputs] = biasCell

	for o = 1, Outputs do
		cell = {}
		cell.x = 220
		cell.y = 30 + 8 * o
		cell.value = network.neurons[MaxNodes + o].value
		cells[MaxNodes + o] = cell
		local color
		if cell.value > 0 then
			color = 0xFF0000FF
		else
			color = 0xFF000000
		end
		gui:draw_text(223, 24 + 8 * o, output_buttons[o])
	end

	for n, neuron in pairs(network.neurons) do
		cell = {}
		if n > Inputs and n <= MaxNodes then
			cell.x = 140
			cell.y = 40
			cell.value = neuron.value
			cells[n] = cell
		end
	end

	for n = 1, 4 do
		for _, gene in pairs(genome.genes) do
			if gene.enabled then
				local c1 = cells[gene.into]
				local c2 = cells[gene.out]
				if gene.into > Inputs and gene.into <= MaxNodes then
					c1.x = 0.75 * c1.x + 0.25 * c2.x
					if c1.x >= c2.x then
						c1.x = c1.x - 40
					end
					if c1.x < 90 then
						c1.x = 90
					end

					if c1.x > 220 then
						c1.x = 220
					end
					c1.y = 0.75 * c1.y + 0.25 * c2.y
				end
				if gene.out > Inputs and gene.out <= MaxNodes then
					c2.x = 0.25 * c1.x + 0.75 * c2.x
					if c1.x >= c2.x then
						c2.x = c2.x + 40
					end
					if c2.x < 90 then
						c2.x = 90
					end
					if c2.x > 220 then
						c2.x = 220
					end
					c2.y = 0.25 * c1.y + 0.75 * c2.y
				end
			end
		end
	end

	gui.drawBox(50 - gui_element * 5 - 3, 70 - gui_element * 5 - 3, 50 + gui_element * 5 + 2, 70 + gui_element * 5 + 2, 0xFF000000, 0x80808080)
	for n, cell in pairs(cells) do
		if n > Inputs or cell.value ~= 0 then
			local color = math.floor((cell.value + 1) / 2 * 256)
			if color > 255 then color = 255 end
			if color < 0 then color = 0 end
			local opacity = 0xFF000000
			if cell.value == 0 then
				opacity = 0x50000000
			end
			color = opacity + color * 0x10000 + color * 0x100 + color
			gui.drawBox(cell.x - 2, cell.y - 2, cell.x + 2, cell.y + 2, opacity, color)
		end
	end
	for _, gene in pairs(genome.genes) do
		if gene.enabled then
			local c1 = cells[gene.into]
			local c2 = cells[gene.out]
			local opacity = 0xA0000000
			if c1.value == 0 then
				opacity = 0x20000000
			end

			local color = 0x80 - math.floor(math.abs(sigmoid(gene.weight)) * 0x80)
			if gene.weight > 0 then
				color = opacity + 0x8000 + 0x10000 * color
			else
				color = opacity + 0x800000 + 0x100 * color
			end
			gui:draw_line(c1.x + 1, c1.y, c2.x - 3, c2.y, color)
		end
	end

	gui:draw_bow(49, 71, 51, 78, 0x00000000, 0x80FF0000)
end

--------------
--- END GUI --
--------------
--------------
-- END NEAT --
--------------
function player_frame(player)
	local key = player == 0 and "P1" or "P2"
	-- Check if we're inputting a special move
	if curr_special_move[key] ~= 0 then
		-- Call corresponding special move
		if curr_special_move[key] == 1 then
			quarter_circle_forward(player, 2)
		elseif curr_special_move[key] == 2 then
			quarter_circle_back(player, 2)
		elseif curr_special_move[key] == 3 then
			z_move(player, 2)
		end

		return
	end
end

function advance_neural_net(player_num)
	local species = pool.species[pool.current_species]
	local genome = species.genomes[pool.current_genome]
	local p_fitness = player_fitness(player_num)
	print("Gen " .. pool.generation .. " species " .. pool.current_species .. " genome " .. pool.current_genome
			.. " fitness: " .. p_fitness)
	genome.fitness = p_fitness

	if p_fitness > pool.max_fitness then
		pool.max_fitness = p_fitness
	end

	next_genome()
	start_round()
end

function main()
	for i = 0, 0 do -- TODO Change once it works with a single controller
		local species = pool.species[pool.current_species]
		local genome = species.genomes[pool.current_genome]
		--draw_genome(genome)
		if not is_round_finished() then
			player_frame(i)
			evaluate_current(i)
			if is_cornered(i) == 1 then
				time_cornered[i + 1] = time_cornered[i + 1] + 1
			end
		else
			advance_neural_net(i)
		end
	end
end



initialize_pool()
-- Initialize controller
map_input()
-- Load savestate
-- main will be called after every frame
start_round()

emu.register_frame(main)