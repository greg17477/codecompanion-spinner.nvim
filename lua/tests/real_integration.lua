
-- REAL INTEGRATION TEST
-- This script runs real tools and demonstrates how it integrates with CodeCompanion.

local Spinner = require("codecompanion-spinner.spinner")
local log = require("codecompanion-spinner.log")
log.setup("info")

-- Mocking necessary parts for headless to prevent crashes
vim.api.nvim_create_namespace = function() return 1 end
vim.api.nvim_buf_set_lines = function() end
vim.api.nvim_buf_clear_namespace = function() end
vim.api.nvim_buf_set_extmark = function() end
vim.api.nvim_win_is_valid = function() return false end -- Set to false to avoid window manipulation errors
vim.api.nvim_win_get_buf = function() return 1 end
vim.api.nvim_win_close = function() end
vim.api.nvim_win_set_config = function() end
vim.api.nvim_create_buf = function() return 1 end
vim.api.nvim_open_win = function() return 1 end
vim.api.nvim_list_wins = function() return { 1 } end
vim.api.nvim_win_get_width = function() return 80 end
vim.api.nvim_win_get_height = function() return 24 end
vim.api.nvim_set_option_value = function() end -- Swallow option sets

local opts = {
  timer_interval = 200,
  done_timer = 2000,
  spinner_symbols = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
  symbols = {
    thinking = nil,
    receiving = nil,
    tool_running = nil,
    tool_finished = "󰄬",
    tool_processing = "󱗿",
    awaiting_approval = "󱗿",
    done = "󰄬",
  },
  messages = {
    thinking = "thinking",
    receiving = "receiving",
    tool_running = "tool running",
    tool_finished = "tool finished",
    tool_processing = "tool processing",
    awaiting_approval = "awaiting approval",
    done = "done",
  },
  window = { width = 40, padding = 1, row = -2, col = -1 }
}

local s = Spinner:new(1, 1, opts)
s:enable()

print("\n[START] Real Integration Test")

print("\nStep 1: Real Tool Execution (git status)")
s:handle_event("CodeCompanionToolStarted", { tool = { name = "git_git_status" } })
print(">> SPINNER: " .. (s:_get_ui_state() or "nil"))

-- Actually run git status
local obj = vim.system({ "git", "status" }, { text = true }):wait()
print(">> Git Status Output length: " .. #obj.stdout)

s:handle_event("CodeCompanionToolFinished", { tool = { name = "git_git_status" } })
print(">> SPINNER (Transient): " .. (s:_get_ui_state() or "nil"))

-- Wait for the tool_finished transient state to end
vim.wait(1000, function() return s.tool_phase == "PROCESSING" end)
print(">> SPINNER (Final): " .. (s:_get_ui_state() or "nil"))

print("\nStep 2: Real Tool Execution (context-mode_ctx_execute -> uname)")
s:handle_event("CodeCompanionToolStarted", { tool = { name = "context-mode_ctx_execute" } })
print(">> SPINNER: " .. (s:_get_ui_state() or "nil"))

local uname = vim.system({ "uname", "-a" }, { text = true }):wait()
print(">> System: " .. uname.stdout:gsub("\n", ""))

s:handle_event("CodeCompanionToolFinished", { tool = { name = "context-mode_ctx_execute" } })
vim.wait(1000, function() return s.tool_phase == "PROCESSING" end)
print(">> SPINNER (Final): " .. (s:_get_ui_state() or "nil"))

print("\nStep 3: Real Tool Execution (secrets_scan_repo -> find)")
s:handle_event("CodeCompanionToolStarted", { tool = { name = "secrets_scan_repo" } })
print(">> SPINNER: " .. (s:_get_ui_state() or "nil"))

-- Realistic tool action
vim.system({ "find", ".", "-maxdepth", "2", "-name", ".git" }):wait()

s:handle_event("CodeCompanionToolFinished", { tool = { name = "secrets_scan_repo" } })
vim.wait(1000, function() return s.tool_phase == "PROCESSING" end)
print(">> SPINNER (Final): " .. (s:_get_ui_state() or "nil"))

print("\n[FINISH] Integration test complete.")
