local _M = {}

local item_map = require("item_map")

function _M.is_match(items, items_in_box)
    local match_flag = true
    for i = 1, #items do
        local recipe_item, recipe_size = table.unpack(items[i])

        recipe_item = item_map[recipe_item] or recipe_item
        if items_in_box[recipe_item] == nil or items_in_box[recipe_item] < recipe_size then
            match_flag = false
        end
    end
    return match_flag
end

return _M
