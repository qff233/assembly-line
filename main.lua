---@meta

local com = require("component")
local event = require("event")
local config = require("config")
local recipe = require("recipe")

local item_map = require("item_map")

local db = com.database

local input_side = config.transport_input_side
local output_side = config.transport_output_side

local recipes = {} ---@type table<string,[[string,number]]>
local transports = {}
local assembly_line

local function init()
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

    assembly_line = com.gt_machine
end

---@return table<string, number>
local function get_item_size_in_box()
    local trans = transports[1]

    local items = {}
    local stacks = trans.getAllStacks(input_side).getAll()
    for i = 0, #stacks do
        local item = stacks[i]
        if item.label ~= nil then
            local label = item_map[item.label] or item.label
            items[label] = (items[label] or 0) + item.size
        end
    end
    return items
end

---@return table<string, number>
local function get_item_slot_in_box()
    local trans = transports[1]

    local items = {}
    local stacks = trans.getAllStacks(input_side).getAll()
    for i = 0, #stacks do
        local item = stacks[i]
        if item.label ~= nil then
            local label = item_map[item.label] or item.label
            items[label] = i + 1
        end
    end
    return items
end

---@class poll:[{["status"]:number,["output_label"]:string}]
local poll = {}

function poll:add_item(output_label)
    local item = {
        status = 1,
        output_label = output_label,
    }
    table.insert(self, item)
end

---@type table<string,number>
local used_items_in_box = {}

local output_count = 0
local last_output_label = nil
local function loop()
    -- match recipe
    local items_in_box = get_item_size_in_box()
    for k, v in pairs(items_in_box) do
        items_in_box[k] = v - (used_items_in_box[k] or 0)
    end

    local add_task = function(output_label, items)
        for _, input_item in ipairs(items) do
            local label, size = table.unpack(input_item)
            used_items_in_box[label] = (used_items_in_box[label] or 0) + size
            items_in_box[label] = items_in_box[label] - size
        end
        poll:add_item(output_label)
    end

    local has_matched = false
    if last_output_label then
        local items = recipes[last_output_label]
        while recipe.is_match(items, items_in_box) do
            has_matched = true
            add_task(last_output_label, items)
        end
    end
    if not has_matched and #poll == 0 and not assembly_line.isMachineActive() then
        local will_output_label, will_used_items = nil, nil
        for output_label, items in pairs(recipes) do
            if recipe.is_match(items, items_in_box) then
                will_used_items = items
                will_output_label = output_label
                last_output_label = output_label
                break
            end
        end

        while will_used_items ~= nil and recipe.is_match(will_used_items, items_in_box) do
            -- print("match success! ", output_label, " will be process!")
            add_task(will_output_label, will_used_items)
        end
    end

    local process_flag
    repeat
        process_flag = 0
        for _, process in ipairs(poll) do
            local trans_count
            repeat
                trans_count = 0
                local need_item_label, need_item_size = table.unpack(recipes[process.output_label][process.status])
                local slot = get_item_slot_in_box()[need_item_label]
                if slot == nil then
                    print("熊孩子乱拿？？")
                end

                local inputbus_item = transports[process.status].getStackInSlot(output_side, 1) or {}
                local inputbus_item_size = inputbus_item.size or 0
                local inputbus_item_max_size = inputbus_item.maxSize or 64
                if inputbus_item_max_size - inputbus_item_size >= need_item_size then
                    trans_count = transports[process.status].transferItem(input_side, output_side, need_item_size, slot,
                        1)
                end
                if trans_count > 0 then
                    while trans_count < need_item_size do
                        slot = get_item_slot_in_box()[need_item_label]
                        trans_count = trans_count +
                            transports[process.status].transferItem(input_side, output_side, need_item_size - trans_count,
                                slot,
                                1)
                        -- print("try transfer Item need_item_size:", need_item_size, "from", slot, "trans_count:", trans_count)
                    end
                    used_items_in_box[need_item_label] = used_items_in_box[need_item_label] - trans_count
                    process.status = process.status + 1
                    local recipe_need_item_size = #recipes[process.output_label]
                    if process.status > recipe_need_item_size then
                        goto skip
                    end
                    process_flag = 1
                end
            until trans_count == 0
        end
        ::skip::

        for i, process in ipairs(poll) do
            if process.status > #recipes[process.output_label] then
                print(poll[1].output_label, " process done!")
                process_flag = 0
                table.remove(poll, i)
            end
        end
    until process_flag == 0

    if #poll > 0 then
        print("---------------------------", output_count)
        output_count = output_count + 1
    end
    for i = 1, #poll do
        local output_label = poll[i].output_label
        print(output_label, ": ", poll[i].status, "all:", #recipes[output_label])
    end
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
