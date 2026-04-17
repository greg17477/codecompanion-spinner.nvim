local log = require("codecompanion-spinner.log")

local M = {}

-- Ensure highlight groups exist
vim.api.nvim_set_hl(0, "CodeCompanionSpinner", { link = "DiagnosticWarn", default = true })
vim.api.nvim_set_hl(0, "CodeCompanionSpinnerThinking", { link = "DiagnosticHint", default = true })
vim.api.nvim_set_hl(0, "CodeCompanionSpinnerReceiving", { link = "DiagnosticInfo", default = true })
vim.api.nvim_set_hl(0, "CodeCompanionSpinnerDone", { link = "DiagnosticOk", default = true })

function M:new(chat_id, buffer)
	local object = {
		chat_id = chat_id,
		buffer = buffer,
		started = false, -- whether there is an active request in the chat
		enabled = false, -- whether the chat buffer is displaying the chat
		state = "none", -- none, thinking, receiving, done
		timer = nil,
		done_timer = nil,
		win_id = nil,
		namespace_id = vim.api.nvim_create_namespace("CodeCompanionSpinner"),
		spinner_index = 0,
		spinner_symbols = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	}
	self.__index = self
	setmetatable(object, self)
	log.debug("Spinner", object.chat_id, "created")
	return object
end

function M:_create_window()
	if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
		return
	end

	-- Find the window displaying the buffer
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

	local width = 20
	local height = 1
	local win_width = vim.api.nvim_win_get_width(chat_win_id)
	local win_height = vim.api.nvim_win_get_height(chat_win_id)

	local buf = vim.api.nvim_create_buf(false, true)
	self.win_id = vim.api.nvim_open_win(buf, false, {
		relative = "win",
		win = chat_win_id,
		zindex = 200,
		width = width,
		height = height,
		row = win_height - 2,
		col = win_width - width,
		style = "minimal",
		focusable = false,
		noautocmd = true,
	})
	vim.wo[self.win_id].winblend = 10 -- subtle transparency
end

function M:_update_text()
	if not (self.enabled and self.started) and self.state ~= "done" then
		self:_close_window()
		return
	end

	self:_create_window()
	if not self.win_id or not vim.api.nvim_win_is_valid(self.win_id) then
		return
	end

	local buf = vim.api.nvim_win_get_buf(self.win_id)
	local msg = ""
	local symbol = ""
	local hl_group = ""

	if self.state == "thinking" then
		self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
		symbol = self.spinner_symbols[self.spinner_index]
		msg = " Thinking..."
		hl_group = "CodeCompanionSpinnerThinking"
	elseif self.state == "receiving" then
		self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
		symbol = self.spinner_symbols[self.spinner_index]
		msg = " Receiving..."
		hl_group = "CodeCompanionSpinnerReceiving"
	elseif self.state == "done" then
		symbol = ""
		msg = " Done!"
		hl_group = "CodeCompanionSpinnerDone"
	end

	-- Right-align text by padding
	local padding = 20 - (#symbol + #msg)
	local line = string.rep(" ", padding) .. symbol .. msg

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })

	-- Apply highlights
	vim.api.nvim_buf_clear_namespace(buf, self.namespace_id, 0, -1)
	if symbol ~= "" then
		vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, padding, {
			end_col = padding + #symbol,
			hl_group = "CodeCompanionSpinner",
		})
		vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, padding + #symbol, {
			end_col = #line,
			hl_group = hl_group,
		})
	else
		vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, padding, {
			end_col = #line,
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
	if state == "thinking" or state == "receiving" then
		self.started = true
		if self.done_timer then
			self.done_timer:stop()
			self.done_timer = nil
		end
	elseif state == "done" then
		self.started = false
		-- Clear after 2 seconds
		if self.done_timer then
			self.done_timer:stop()
		end
		self.done_timer = vim.defer_fn(function()
			self.state = "none"
			self:_update_state()
		end, 2000)
	end
	self:_update_state()
end

-- Compatibility wrappers for old calls
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
