local M = {}

M.spinner_manager = require("codecompanion-spinner.spinner-manager")
M.log = require("codecompanion-spinner.log")

M.opts = {
	log_level = "info",
	messages = {
		thinking = "Thinking...",
		receiving = "Receiving...",
		done = "Done!",
	},
	window = {
		width = 20,
		height = 1,
		row = -2, -- Offset from bottom (-2 means 2 lines up from bottom of chat window)
		col = -1, -- Offset from right (negative means relative to right edge)
		winblend = 10,
		zindex = 200,
		border = "none",
		style = "minimal",
		focusable = false,
		noautocmd = true,
		winhl = nil, -- Optional: e.g., 'Normal:Comment,NormalNC:Comment'
		padding = 1, -- Right padding
	},
	highlights = {
		spinner = "DiagnosticWarn",
		thinking = "DiagnosticHint",
		receiving = "DiagnosticInfo",
		done = "DiagnosticOk",
	},
}

function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
	M.spinner_manager.setup(M.opts)
	M.log.setup(M.opts.log_level)
end

return M
