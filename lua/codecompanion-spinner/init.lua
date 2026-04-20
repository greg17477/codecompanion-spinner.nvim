local M = {}

M.spinner_manager = require("codecompanion-spinner.spinner-manager")
M.log = require("codecompanion-spinner.log")

M.opts = {
  log_level = "info",
  spinner_symbols = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  done_timer = 2000,
  timer_interval = 200,
  symbols = {
    thinking = nil,
    receiving = nil,
    tool_running = nil,
    tool_finished = "󰄬",
    tool_processing = "󱗿",
    awaiting_approval = "󱗿",
    diff_attached = "󰙶",
    done = "󰄬",
    stopped = "󰓛",
  },
  messages = {
    thinking = "thinking",
    receiving = "receiving",
    tool_running = "tool running",
    tool_finished = "tool finished",
    tool_processing = "tool processing",
    awaiting_approval = "awaiting approval",
    diff_attached = "diff attached",
    done = "done",
    stopped = "stopped",
  },
  window = {
    width = 20,
    height = 1,
    row = -2, -- Offset from bottom (-2 means 2 lines up from bottom of chat window)
    col = -1, -- Offset from right (negative means relative to right edge)
    padding = 1, -- Right padding
    winblend = 0,
    zindex = 200,
    border = "none",
    style = "minimal",
    focusable = false,
    noautocmd = true,
    winhl = nil, -- Optional: e.g., 'Normal:Comment,NormalNC:Comment'
  },
  highlights = {
    spinner = "DiagnosticError",
    thinking = "DiagnosticHint",
    receiving = "DiagnosticInfo",
    awaiting_approval = "DiagnosticWarn",
    diff_attached = "DiagnosticWarn",
    tool_running = "DiagnosticHint",
    tool_finished = "DiagnosticOk",
    tool_processing = "DiagnosticHint",
    done = "DiagnosticOk",
    -- New symbol-specific highlights
    thinking_symbol = "DiagnosticError",
    receiving_symbol = "DiagnosticError",
    tool_running_symbol = "DiagnosticError",
    tool_finished_symbol = "DiagnosticOk",
    tool_processing_symbol = "DiagnosticWarn",
    awaiting_approval_symbol = "DiagnosticWarn",
    diff_attached_symbol = "DiagnosticWarn",
    done_symbol = "DiagnosticOk",
    stopped_symbol = "DiagnosticError",
  },
}

function M.setup(opts)
  M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
  M.log.setup(M.opts.log_level)
  M.spinner_manager.setup(M.opts)
  M.log.debug("CodeCompanion Spinner initialized")
end

return M
