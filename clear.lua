local com = require("component")
local config = require("config")

local transports = {}
local input_side = config.transport_input_side
local output_side = config.transport_output_side

local addresses = config.transport_addresses
for i = 1, #addresses do
	local address = addresses[i]
	table.insert(transports, com.proxy(address))
end

for i, transport in ipairs(transports) do
	transport.transferItem(output_side, input_side, 64, 1, i)
end

print("如果清空失败，清空末影箱后再尝试")
