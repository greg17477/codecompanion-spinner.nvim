local log = require("codecompanion-spinner.log")

local M = {}

function M:new(chat_id, buffer, opts)
	local object = {
		chat_id = chat_id,
		buffer = buffer,
		opts = opts or {},
		started = false,
		enabled = false,
		state = "none",
		timer = nil,
		done_timer = nil,
		win_id = nil,
		namespace_id = vim.api.nvim_create_namespace("CodeCompanionSpinner"),
		spinner_index = 0,
		spinner_symbols = opts.spinner_symbols or { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	}

	-- Set up highlights
	local hl = object.opts.highlights or {}
	vim.api.nvim_set_hl(0, "CodeCompanionSpinner", { link = hl.spinner or "DiagnosticError", default = true })
	vim.api.nvim_set_hl(0, "CodeCompanionSpinnerThinking", { link = hl.thinking or "DiagnosticHint", default = true })
	vim.api.nvim_set_hl(0, "CodeCompanionSpinnerReceiving", { link = hl.receiving or "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "CodeCompanionSpinnerAwaitingApproval", { link = hl.awaiting_approval or "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "CodeCompanionSpinnerToolRunning", { link = hl.tool_running or "DiagnosticHint", default = true })
	vim.api.nvim_set_hl(0, "CodeCompanionSpinnerDone", { link = hl.done or "DiagnosticOk", default = true })

	self.__index = self
	setmetatable(object, self)
	log.debug("Spinner", object.chat_id, "created")
	return object
end

function M:_create_window(width)
	if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
		-- Update window config if width changed
		local s, current_config = pcall(vim.api.nvim_win_get_config, self.win_id)
		if s and current_config.width ~= width then
			vim.api.nvim_win_set_width(self.win_id, width)
		end
		return
	end

	local chat_win_id = nil
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(win) == self.buffer then
			chat_win_id = win
			break
		end
	end

	if not chat_win_id then
		return
	end

	local win_config = self.opts.window or {}
	local height = win_config.height or 1
	local win_width = vim.api.nvim_win_get_width(chat_win_id)
	local win_height = vim.api.nvim_win_get_height(chat_win_id)

	-- Calculate row/col with negative offset support
	local row = win_config.row or -2
	if row < 0 then
		row = math.max(0, win_height + row)
	end

	local col = win_config.col or -1
	if col < 0 then
		col = math.max(0, win_width - width + (col + 1))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

	local s, win_id = pcall(vim.api.nvim_open_win, buf, false, {
		relative = "win",
		win = chat_win_id,
		width = width,
		height = height,
		row = row,
		col = col,
		zindex = win_config.zindex or 1000,
		border = win_config.border or "none",
		style = "minimal",
		focusable = win_config.focusable or false,
		noautocmd = win_config.noautocmd ~= false,
	})

	if s then
		self.win_id = win_id
	else
		log.error("Failed to open spinner window: " .. tostring(win_id))
		return
	end
	vim.wo[self.win_id].winblend = win_config.winblend or 10
	if win_config.winhl then
		vim.wo[self.win_id].winhighlight = win_config.winhl
	end
end

function M:_update_text()
	if not (self.enabled and self.started) and self.state ~= "done" then
		self:_close_window()
		return
	end

	local msg = ""
	local symbol = ""
	local hl_group = ""
	local msgs = self.opts.messages or {}

	if self.state == "thinking" then
		self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
		symbol = self.spinner_symbols[self.spinner_index]
		msg = " " .. (msgs.thinking or "Thinking...")
		hl_group = "CodeCompanionSpinnerThinking"
	elseif self.state == "receiving" then
		self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
		symbol = self.spinner_symbols[self.spinner_index]
		msg = " " .. (msgs.receiving or "Receiving...")
		hl_group = "CodeCompanionSpinnerReceiving"
	elseif self.state == "awaiting_approval" then
		symbol = ""
		msg = " " .. (msgs.awaiting_approval or "Awaiting approval")
		hl_group = "CodeCompanionSpinnerAwaitingApproval"
	elseif self.state == "tool_running" then
		self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
		symbol = self.spinner_symbols[self.spinner_index]
		msg = " " .. (msgs.tool_running or "Tool running...")
		hl_group = "CodeCompanionSpinnerToolRunning"
	elseif self.state == "done" then
		symbol = ""
		msg = " " .. (msgs.done or "Done!")
		hl_group = "CodeCompanionSpinnerDone"
	end

	local total_width = (self.opts.window and self.opts.window.width) or 20
	local right_padding = (self.opts.window and self.opts.window.padding) or 1
	local content_width = vim.fn.strdisplaywidth(symbol .. msg)
	local required_width = content_width + right_padding

	if required_width > total_width then
		total_width = required_width
	end

	self:_create_window(total_width)

	if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
		return
	end

	local buf = vim.api.nvim_win_get_buf(self.win_id)
	local leading_spaces = math.max(0, total_width - content_width - right_padding)
	local line = string.rep(" ", leading_spaces) .. symbol .. msg .. string.rep(" ", right_padding)

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })

	vim.api.nvim_buf_clear_namespace(buf, self.namespace_id, 0, -1)

	if symbol ~= "" then
		vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces, {
			end_col = leading_spaces + #symbol,
			hl_group = "CodeCompanionSpinner",
		})
		vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces + #symbol, {
			end_col = leading_spaces + #symbol + #msg,
			hl_group = hl_group,
		})
	else
		vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces, {
			end_col = leading_spaces + #msg,
			hl_group = hl_group,
		})
	end
end

function M:_close_window()
	if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
		vim.api.nvim_win_close(self.win_id, true)
		self.win_id = nil
	end
end

function M:_start_timer()
	if self.timer then
		return
	end
	local timer_fn = vim.schedule_wrap(function()
		self:_update_text()
	end)
	self.timer = vim.uv.new_timer()
	self.timer:start(0, 100, timer_fn)
	log.debug("Spinner", self.chat_id, "timer started")
end

function M:_stop_timer()
	if not self.timer then
		return
	end
	self.timer:stop()
	self.timer:close()
	self.timer = nil
	log.debug("Spinner", self.chat_id, "timer stopped")
end

function M:_update_state()
	if self.enabled and self.started then
		self:_start_timer()
	elseif self.state == "done" then
		self:_stop_timer()
		self:_update_text()
	else
		self:_stop_timer()
		self:_close_window()
	end
end

function M:set_state(state)
	self.state = state
	if state == "thinking" or state == "receiving" or state == "tool_running" or state == "awaiting_approval" then
		self.started = true
		if self.done_timer then
			self.done_timer:stop()
			self.done_timer = nil
		end
	elseif state == "done" then
		self.started = false
		if self.done_timer then
			self.done_timer:stop()
		end
		self.done_timer = vim.defer_fn(function()
			self.state = "none"
			self:_update_state()
		end, self.opts.done_timer or 2000)
	end
	self:_update_state()
end

function M:start()
	self:set_state("thinking")
end

function M:stop()
	self:set_state("done")
end

function M:enable()
	self.enabled = true
	self:_update_state()
end

function M:disable()
	self.enabled = false
	self:_update_state()
end

return M
