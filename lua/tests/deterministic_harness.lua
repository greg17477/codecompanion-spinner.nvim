--[[
CODECOMPANION SPINNER - DETERMINISTIC TEST HARNESS

HOW TO RUN:
1. Open Neovim in the project root.
2. Run: :luafile lua/tests/deterministic_harness.lua
OR from shell:
   nvim --headless -u NONE -c "set runtimepath+=." -c "luafile lua/tests/deterministic_harness.lua" -c "qall"

INTERPRETING FAILURES:
- FAIL indicates a mismatch between the expected UI message and the actual computed message.
- The output clearly shows [expected: message] vs [actual: message].
- Use the logged state_after_event to diagnose why the priority logic failed.

HOW TO EXTEND:
- Add new entries to the `SCENARIOS` table.
- Each scenario is a table of events. An event can be a string (event name) or a table { event = name, data = ... }.
- You can also add special "commands" like { cmd = "wait", ms = 500 } to simulate timers.

STATE MACHINE LOGIC:
The harness mirrors CodeCompanion's priority:
approval > tool > response > reasoning > idle
]]

local Spinner = require("codecompanion-spinner.spinner")

-- Mocking Neovim APIs for headless execution
vim.api.nvim_create_namespace = function() return 1 end
vim.api.nvim_buf_set_lines = function() end
vim.api.nvim_buf_clear_namespace = function() end
vim.api.nvim_buf_set_extmark = function() end
vim.api.nvim_win_is_valid = function() return true end
vim.api.nvim_win_get_buf = function() return 1 end
vim.api.nvim_win_close = function() end
vim.api.nvim_win_set_config = function() end
vim.api.nvim_create_buf = function() return 1 end
vim.api.nvim_open_win = function() return 1 end
vim.api.nvim_list_wins = function() return { 1 } end
vim.api.nvim_win_get_width = function() return 80 end
vim.api.nvim_win_get_height = function() return 24 end

-- Mock vim.uv.new_timer
vim.uv = vim.uv or {}
vim.uv.new_timer = function()
  return {
    start = function() end,
    stop = function() end,
    close = function() end,
  }
end

local deferred_functions = {}
vim.defer_fn = function(fn, delay)
  table.insert(deferred_functions, { fn = fn, delay = delay })
end

local function run_deferred(match_delay)
  local remaining = {}
  local to_run = {}
  for _, item in ipairs(deferred_functions) do
    if not match_delay or item.delay == match_delay then
      table.insert(to_run, item)
    else
      table.insert(remaining, item)
    end
  end
  deferred_functions = remaining
  -- Sort by delay to ensure correct order
  table.sort(to_run, function(a, b) return a.delay < b.delay end)
  for _, item in ipairs(to_run) do
    item.fn()
  end
end

local opts = {
  timer_interval = 200,
  done_timer = 2000,
  spinner_symbols = { "⠋" },
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
  }
}

local function get_state_summary(s)
  return string.format("R:%s|C:%s|T:%s|#T:%d|Diff:%s",
    s.req_state, s.content_phase, s.tool_phase, s.tool_count, tostring(s.diff_attached))
end

local SCENARIOS = {
  {
    id = "basic_stream",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "reasoning_chunk", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionRequestFinished", expected = "receiving" }, -- Grace period
      { cmd = "wait", ms = 300, expected = "done" },
      { cmd = "wait", ms = 2000, expected = "nil" },
    }
  },
  {
    id = "reasoning_to_response",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "reasoning_chunk", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionRequestFinished", expected = "receiving" },
      { cmd = "wait", ms = 300, expected = "done" },
    }
  },
  {
    id = "reasoning_to_tool_to_response",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "reasoning_chunk", expected = "thinking" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "thinking" }, -- Back to thinking
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionRequestFinished", expected = "receiving" },
      { cmd = "wait", ms = 300, expected = "tool processing" }, -- used tool, now processing
    }
  },
  {
    id = "response_to_tool_to_response",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "receiving" },
      { event = "CodeCompanionRequestFinished", expected = "receiving" },
      { cmd = "wait", ms = 300, expected = "tool processing" },
    }
  },
  {
    id = "tool_to_approval_to_tool",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolApprovalRequested", expected = "awaiting approval" },
      { event = "CodeCompanionToolApprovalFinished", expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
    }
  },
  {
    id = "response_to_approval_to_response",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionToolApprovalRequested", expected = "awaiting approval" },
      { event = "CodeCompanionToolApprovalFinished", expected = "receiving" },
    }
  },
  {
    id = "reasoning_to_approval_to_response",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "reasoning_chunk", expected = "thinking" },
      { event = "CodeCompanionToolApprovalRequested", expected = "awaiting approval" },
      { event = "CodeCompanionToolApprovalFinished", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
    }
  },
  {
    id = "tool_to_end_to_response",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionRequestFinished", expected = "tool running" },
      { cmd = "wait", ms = 300, expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "tool processing" },
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
    }
  },
  {
    id = "streaming_to_approval_to_stream_end",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolApprovalRequested", expected = "awaiting approval" },
      { event = "CodeCompanionRequestFinished", expected = "awaiting approval" },
      { cmd = "wait", ms = 300, expected = "awaiting approval" },
      { event = "CodeCompanionToolApprovalFinished", expected = "tool processing" },
    }
  },
  {
    id = "approval_to_stream_end",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolApprovalRequested", expected = "awaiting approval" },
      { event = "CodeCompanionRequestFinished", expected = "awaiting approval" },
      { cmd = "wait", ms = 300, expected = "awaiting approval" },
    }
  },
  {
    id = "tool_to_stream_end",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionRequestFinished", expected = "tool running" },
      { cmd = "wait", ms = 300, expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "tool processing" },
    }
  },
  {
    id = "response_to_stream_end",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionRequestFinished", expected = "receiving" },
      { cmd = "wait", ms = 300, expected = "done" },
    }
  },
  {
    id = "diff_attached_priority",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionDiffAttached", expected = "diff attached" },
      { event = "response_chunk", expected = "diff attached" },
      { event = "CodeCompanionToolStarted", expected = "diff attached" },
      { event = "CodeCompanionDiffDetached", expected = "tool running" },
    }
  },
  {
    id = "stop_interaction",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionChatStopped", expected = "thinking" }, -- Grace period
      { cmd = "wait", ms = 300, expected = "stopped" },
      { cmd = "wait", ms = 2000, expected = "nil" },
    }
  },
  {
    id = "multi_tool_parallel",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "thinking" },
    }
  },
  {
    id = "tools_finished_event",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolsFinished", expected = "thinking" },
    }
  },
  {
    id = "approval_persistence",
    steps = {
      { event = "CodeCompanionToolApprovalRequested", expected = "awaiting approval" },
      { event = "CodeCompanionRequestStarted", expected = "awaiting approval" },
      { event = "CodeCompanionToolApprovalFinished", expected = "thinking" },
    }
  },
  {
    id = "done_to_new_request",
    steps = {
      { event = "CodeCompanionChatDone", expected = "nil" }, -- Grace period
      { cmd = "wait", ms = 300, expected = "done" },
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { cmd = "wait", ms = 2000, expected = "thinking" }, -- Done timer should have been cleared
    }
  },
  {
    id = "transient_tool_finished_to_receiving",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "response_chunk", expected = "receiving" },
      { event = "CodeCompanionToolStarted", expected = "tool running" },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "receiving" },
    }
  },
  {
    id = "terminal_stopped_message",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      { event = "CodeCompanionChatStopped", expected = "thinking" },
      { cmd = "wait", ms = 300, expected = "stopped" },
    }
  },
  {
    id = "real_world_tool_calls",
    steps = {
      { event = "CodeCompanionRequestStarted", expected = "thinking" },
      {
        event = "CodeCompanionToolStarted",
        data = { tool = { name = "secrets_scan_repo" } },
        expected = "tool running [secrets_scan_repo]"
      },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "thinking" },
      {
        event = "CodeCompanionToolStarted",
        data = { tool = { name = "git_git_status" } },
        expected = "tool running [git_git_status]"
      },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
      { cmd = "wait", ms = 500, expected = "thinking" },
      {
        event = "CodeCompanionToolStarted",
        data = { tool = { name = "context-mode_ctx_execute" } },
        expected = "tool running [context-mode_ctx_execute]"
      },
      { event = "CodeCompanionToolFinished", expected = "tool finished" },
    }
  }
}

local function run_harness()
  print("\n" .. string.rep("=", 120))
  print("CODECOMPANION SPINNER - DETERMINISTIC VERIFICATION")
  print(string.rep("=", 120))
  print(string.format("%-25s | %-35s | %-25s | %-12s | %-12s | %s", "Scenario ID", "Event/Action", "State Summary", "Expected", "Actual", "Result"))
  print(string.rep("-", 120))

  local total_passed = 0
  local total_steps = 0

  for _, scenario in ipairs(SCENARIOS) do
    local s = Spinner:new(1, 1, opts)
    s.enabled = true
    deferred_functions = {}

    for _, step in ipairs(scenario.steps) do
      total_steps = total_steps + 1
      local action_desc = ""

      if step.cmd == "wait" then
        action_desc = "Wait " .. step.ms .. "ms"
        run_deferred(step.ms)
      elseif step.event == "reasoning_chunk" then
        action_desc = "Reasoning chunk"
        s.content_phase = "REASONING"
      elseif step.event == "response_chunk" then
        action_desc = "Response chunk"
        s.content_phase = "RESPONSE"
      else
        action_desc = step.event
        if step.data and step.data.tool then
          action_desc = action_desc .. " (" .. step.data.tool.name .. ")"
        end
        local event_data = step.data or { chat = { id = 1 } }
        if not event_data.chat then event_data.chat = { id = 1 } end
        s:handle_event(step.event, event_data)
      end

      local actual_msg, _, _ = s:_get_ui_state()
      actual_msg = actual_msg or "nil"
      local expected_msg = step.expected or "nil"
      local state_summary = get_state_summary(s)
      local pass = (actual_msg == expected_msg)

      if pass then total_passed = total_passed + 1 end
      local result_str = pass and "PASS" or "FAIL"

      print(string.format("%-25s | %-35s | %-25s | %-12s | %-12s | %s",
        scenario.id, action_desc, state_summary, expected_msg, actual_msg, result_str))
    end
    print(string.rep("-", 120))
  end

  print(string.format("\nFINAL RESULTS: %d/%d steps passed (%.1f%%)",
    total_passed, total_steps, (total_passed / total_steps) * 100))

  if total_passed < total_steps then
    print("\n[!] SOME TESTS FAILED. Please review the logic in spinner.lua against the requirements.")
    os.exit(1)
  else
    print("\n[+] ALL TESTS PASSED.")
  end
end

local ok, err = pcall(run_harness)
if not ok then
  print("\n[FATAL ERROR] " .. tostring(err))
  os.exit(1)
end
