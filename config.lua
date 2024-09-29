local sides = require("sides")

local config = {
	check_interval = 2,

	assembly_line_address = "${aa}",

	transport_input_side = sides.east,
	transport_output_side = sides.west,
	transport_addresses = {
		"${ea1}",
		"${ea2}",
		"${ea3}",
		"${ea4}",
		"${ea5}",
		"${ea6}",
		"${ea7}",
		"${ea8}",
		"${ea9}",
		"${ea10}",
		"${ea11}",
		"${ea12}",
		"${ea13}",
		"${ea14}",
		"${ea15}",
		"${ea16}",
	},
}

return config
