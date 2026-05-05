local M = {}

-- Default parameters
M.events_get_focus = { "FocusGained", "CmdlineLeave" }

-- nvim_create_autocmd shortcut
local autocmd = vim.api.nvim_create_autocmd

M.__impl = {}
M.__impl.xkb_switch_lib = nil
M.__impl.user_os_name = vim.uv.os_uname().sysname

local function get_user_layouts()
	local xkb_switch_lib = M.__impl.xkb_switch_lib
	if not xkb_switch_lib then
		vim.notify("Xkb_switch lib not found!", vim.log.levels.ERROR)
		return {}
	end
	return vim.fn.systemlist(
		(string.find(xkb_switch_lib, "dylib") and "issw -l")
			or (string.find(xkb_switch_lib, "xkb") and "xkb-switch -l")
			or (string.find(xkb_switch_lib, "g3kb") and "g3kb-switch -l")
		or ""
	)
end

local function initXkbSwitch()
	local xkb_switch_lib = nil
	-- Find the path to the xkbswitch shared object (macOS)
	if M.__impl.user_os_name == "Darwin" then
		if vim.fn.filereadable("/usr/local/lib/libInputSourceSwitcher.dylib") == 1 then
			xkb_switch_lib = "/usr/local/lib/libInputSourceSwitcher.dylib"
		elseif vim.fn.filereadable("/usr/lib/libInputSourceSwitcher.dylib") == 1 then
			xkb_switch_lib = "/usr/lib/libInputSourceSwitcher.dylib"
		end
	-- Find the path to the xkbswitch shared object (Linux)
	else
		-- g3kb-switch
		if vim.fn.filereadable("/usr/lib/libg3kbswitch.so") == 1 then
			xkb_switch_lib = "/usr/lib/libg3kbswitch.so"
		elseif vim.fn.filereadable("/usr/local/lib64/libg3kbswitch.so") == 1 then
			xkb_switch_lib = "/usr/local/lib64/libg3kbswitch.so"
		elseif vim.fn.filereadable("/usr/local/lib/libg3kbswitch.so") == 1 then
			xkb_switch_lib = "/usr/local/lib/libg3kbswitch.so"
		else
			-- xkb-switch
			local all_libs_locations = vim.fn.systemlist("ldd $(which xkb-switch)")
			for _, value in ipairs(all_libs_locations) do
				if string.find(value, "libxkbswitch.so.1") or string.find(value, "libxkbswitch.so.2") then
					if string.find(value, "not found") then
						xkb_switch_lib = nil
					else
						xkb_switch_lib = string.sub(value, string.find(value, "/") or 1, string.find(value, "%(") - 2)
					end
				end
			end
		end
	end

	if xkb_switch_lib == nil then
		error("(xkbswitch.lua) Error occured: layout switcher file was not found.")
	end
	M.__impl.xkb_switch_lib = xkb_switch_lib
	local user_layouts = get_user_layouts()
	-- Find the used US layout (us/us(qwerty)/us(dvorak)/...)
	for _, value in ipairs(user_layouts) do
		if string.find(value, M.__impl.user_os_name == "Darwin" and "ABC" or "^us") then
			M.__impl.user_us_layout_variation = value
		elseif string.find(value, ".US$") then
			M.__impl.user_us_layout_variation = value
		end
	end
	if M.__impl.user_us_layout_variation == nil then
		error(
			"(xkbswitch.lua) Error occured: could not find the English layout. Check your layout list. (xkb-switch -l / issw -l / g3kb-switch -l)"
		)
	end
end

function M.__impl.get_current_layout()
	return vim.fn.libcall(M.__impl.xkb_switch_lib, "Xkb_Switch_getXkbLayout", "")
end

function M.__impl.set_layout(layout_name)
	vim.fn.libcall(M.__impl.xkb_switch_lib, "Xkb_Switch_setXkbLayout", layout_name)
end

M.__impl.saved_layout = M.__impl.get_current_layout()
M.__impl.user_us_layout_variation = nil


function M.setup(opts)
	-- Parse provided options
	opts = opts or {}
	if opts.events_get_focus then
		M.events_get_focus = opts.events_get_focus
	end
	if not opts.custom_layout_rules then
		initXkbSwitch()
	else
		local rules = opts.custom_layout_rules
		M.__impl.get_current_layout = rules.get_current_layout
			or function()
				vim.notify("(xkbswticth.lua) get_current_layout callback not set", vim.log.levels.ERROR)
				return ""
			end
		M.__impl.set_layout = rules.set_layout
			or function()
				vim.notify("(xkbswticth.lua) set_layout callback not set", vim.log.levels.ERROR)
			end
		if not rules.user_us_layout_variation then
			vim.notify("(xkbswitch.lua) user_us_layout_variation not set so i use default 'us'", vim.log.levels.WARN)
			M.__impl.user_us_layout_variation = "us"
		else
			M.__impl.user_us_layout_variation = not rules.user_us_layout_variation
		end
	end

	-- When leaving Insert Mode:
	-- 1. Save the current layout
	-- 2. Switch to the US layout
	autocmd("InsertLeave", {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				M.__impl.saved_layout = M.__impl.get_current_layout()
				M.__impl.set_layout(M.__impl.user_us_layout_variation)
			end)
		end,
	})

	-- When Neovim gets focus:
	-- 1. Save the current layout
	-- 2. Switch to the US layout if Normal Mode or Visual Mode is the current mode
	autocmd(M.events_get_focus, {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				M.__impl.saved_layout = M.__impl.get_current_layout()
				local current_mode = vim.api.nvim_get_mode().mode
				if
					current_mode == "n"
					or current_mode == "no"
					or current_mode == "v"
					or current_mode == "V"
					or current_mode == "^V"
				then
					M.__impl.set_layout(M.__impl.user_us_layout_variation)
				end
			end)
		end,
	})

	-- When entering Insert Mode:
	-- 1. Switch to the previously saved layout
	autocmd({ "InsertEnter" }, {
		pattern = "*",
		callback = function()
			vim.schedule(function()
				if M.__impl.saved_layout then
					M.__impl.set_layout(M.__impl.saved_layout)
				end
			end)
		end,
	})
end

return M
