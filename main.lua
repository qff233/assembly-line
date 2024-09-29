local com = require("component")
local event = require("event")
local config = require("config")
local recipe = require("recipe")

local db = com.database

local input_side = config.transport_input_side
local output_side = config.transport_output_side

local recipes = {}
local transports = {}
local assembly_line

local init = function()
	for i = 1, 81 do
		local item = db.get(i)
		if item == nil then
		    goto continue
		end
		local label = item.output
		local input_items = item.inputItems
		print("----------------------------------")
		print("recipe: ", label)
		for idx, v in ipairs(item.inputItems) do
			print(idx, v[1], v[2])
		end
		print("----------------------------------")
		recipes[label] = input_items
        ::continue::
	end

	local addresses = config.transport_addresses
	for i = 1, #addresses do
		local address = addresses[i]
		local me_export_bus = com.proxy(address)
		assert(me_export_bus ~= nil, "me_export_bus_address error, address: ", address)
		table.insert(transports, com.proxy(address))
	end

    local address = config.assembly_line_address
    assembly_line = com.proxy(address)
    assert(assembly_line ~= nil, "assembly_line_address error, address: ", address)
end

local get_item_size_in_box = function()
	local trans = transports[1]

	local items = {}
	local stacks = trans.getAllStacks(input_side).getAll()
	for i = 0, #stacks do
		local item = stacks[i]
		if item.label ~= nil then
			items[item.label] = (items[item.label] or 0) + item.size
		end
	end
	return items
end

local get_item_slot_in_box = function()
	local trans = transports[1]

	local items = {}
	local stacks = trans.getAllStacks(input_side).getAll()
	for i = 0, #stacks do
		local item = stacks[i]
		if item.label ~= nil then
			items[item.label] = i + 1
		end
	end
	return items
end

local queue = {
	-- {
	--    status: 1-16
	--    output_label: string
    -- }, .......
}

local queue_add_item = function(output_label)
	local item = {
		status = 1,
		output_label = output_label,
	}
	table.insert(queue, item)
end

local used_items_in_box = {}
local output_count = 0
local loop = function()
	-- match recipe
	local items_in_box = get_item_size_in_box()
	for k, v in pairs(items_in_box) do
		items_in_box[k] = v - (used_items_in_box[k] or 0)
	end

    if #queue > 0 then
        local output_label = queue[1].output_label
        local items = recipes[output_label]
        while recipe.is_match(items, items_in_box) do
            for _, input_item in ipairs(items) do
                local label, size = table.unpack(input_item)
                used_items_in_box[label] = (used_items_in_box[label] or 0) + size
                items_in_box[label] = items_in_box[label] - size
            end
            queue_add_item(output_label)
        end
    elseif not assembly_line.isMachineActive() then
        local will_output_label,will_used_items = nil,nil
        for output_label, items in pairs(recipes) do
            if recipe.is_match(items, items_in_box) then
                will_used_items = items
                will_output_label = output_label
                break
            end
        end

        while will_used_items ~= nil and recipe.is_match(will_used_items, items_in_box) do
            -- print("match success! ", output_label, " will be process!")
            for _, input_item in ipairs(will_used_items) do
                local label, size = table.unpack(input_item)
                used_items_in_box[label] = (used_items_in_box[label] or 0) + size
                items_in_box[label] = items_in_box[label] - size
            end
            queue_add_item(will_output_label)
        end
    end

	local process_flag
	repeat
		process_flag = 0
		local item_slot_in_box = get_item_slot_in_box()
		local last_status = 16
		for _, process in ipairs(queue) do
			local status = process.status
			if status >= last_status then
				goto skip
			end
			last_status = status

			local need_item_label, need_item_size = table.unpack(recipes[process.output_label][status])
			local slot = item_slot_in_box[need_item_label]
			if slot == nil then
				print("熊孩子乱拿？？")
			end

			local trans_count = transports[status].transferItem(input_side, output_side, need_item_size, slot, 1)
			if trans_count > 0 then
                local recipe_size = #recipes[process.output_label]
				-- print("process ", process.output_label, " is in ", status, "all has ", recipe_size)
				used_items_in_box[need_item_label] = used_items_in_box[need_item_label] - need_item_size
				process.status = status + 1
                if process.status > recipe_size then
                    process_flag = 0
                    goto skip
                end
				process_flag = 1
			end
		end
		::skip::
		if #queue > 0 and queue[1].status > #recipes[queue[1].output_label] then
			print(queue[1].output_label, " process done!")
            process_flag = 0
			table.remove(queue, 1)
		end
	until process_flag == 0

    if #queue > 0 then
        print("---------------------------", output_count)
        output_count = output_count + 1
    end
    for i = 1,#queue do
        local output_label = queue[i].output_label
        print(output_label, ": ", queue[i].status, "all:", #recipes[output_label])
    end
end

function Loop()
    pcall(loop)
end

function Main()
	init()

	print("start match!")
	local interval = config.check_interval or 2
	local timer = event.timer(interval, loop, math.huge)
	while true do
		local id, _, _, _ = event.pullMultiple("interrupted")
		if id == "interrupted" then
			print("interrupted cancel timer")
			event.cancel(timer)
			break
		end
	end
end

Main()
