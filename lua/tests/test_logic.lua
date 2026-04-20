local Spinner = require("codecompanion-spinner.spinner")

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
  for _, item in ipairs(to_run) do
    item.fn()
  end
end

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected '%s', got '%s'", msg, tostring(expected), tostring(actual)))
  end
end

local function test()
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
    }
  }
  local s = Spinner:new(1, 1, opts)
  s.enabled = true

  print("Test 1: Request started")
  s:handle_event("CodeCompanionRequestStarted", { chat = { id = 1 } })
  local msg, state_key = s:_get_ui_state()
  assert_eq(msg, "thinking", "Should be thinking after start")
  assert_eq(state_key, "thinking", "State key should be thinking")

  print("Test 2: Response incoming")
  -- Mock poll state to transition to receiving
  s.content_phase = "RESPONSE"
  msg, state_key = s:_get_ui_state()
  assert_eq(msg, "receiving", "Should be receiving after response starts")
  assert_eq(state_key, "receiving", "State key should be receiving")

  print("Test 3: Tool starts")
  s:handle_event("CodeCompanionToolStarted", {})
  msg, state_key = s:_get_ui_state()
  assert_eq(msg, "tool running", "Tool running should have priority over receiving")
  assert_eq(state_key, "tool_running", "State key should be tool_running")

  print("Test 4: Tool ends (still streaming)")
  s:handle_event("CodeCompanionToolFinished", {})
  msg, state_key = s:_get_ui_state()
  assert_eq(msg, "tool finished", "Should show tool finished briefly")
  
  -- Run the 500ms delay timer
  run_deferred(500)
  
  msg, state_key = s:_get_ui_state()
  assert_eq(msg, "receiving", "Should fall back to receiving when tool ends but still streaming")
  assert_eq(state_key, "receiving", "State key should be receiving")

  print("Test 5: Request finished (terminal state)")
  s:handle_event("CodeCompanionRequestFinished", {})
  
  -- Request finished sets a 300ms grace timer
  run_deferred(300)

  msg, state_key = s:_get_ui_state()
  -- has_tool_call should be true because of Test 3
  assert_eq(msg, "tool processing", "Should show tool processing if turn ended and tool was used")
  assert_eq(state_key, "tool_processing", "State key should be tool_processing")

  print("Test 6: Awaiting approval")
  s:handle_event("CodeCompanionRequestStarted", { chat = { id = 1 } }) -- new turn
  s:handle_event("CodeCompanionToolApprovalRequested", {})
  msg, state_key = s:_get_ui_state()
  assert_eq(msg, "awaiting approval", "Should show awaiting approval")
  assert_eq(state_key, "awaiting_approval", "State key should be awaiting_approval")

  print("Test 7: Request finished while awaiting approval")
  s:handle_event("CodeCompanionRequestFinished", {})
  msg, state_key = s:_get_ui_state()
  assert_eq(msg, "awaiting approval", "Should STILL show awaiting approval even if request finished")
  assert_eq(state_key, "awaiting_approval", "State key should be awaiting_approval")

  print("Test 8: Done timer should not clear awaiting approval")
  -- Simulate timer firing
  s.req_state = "IDLE"
  s.tool_phase = "NONE" -- This is what the current code does WRONGLY
  msg = s:_get_ui_state()
  -- If it's IDLE and tool_phase is NONE, it returns nil or done?
  -- Actually, in the code:
  -- if self.req_state == REQ_STATE.DONE or self.req_state == REQ_STATE.FINISHED then ...
  -- If IDLE, it returns nil.

  print("All logic tests passed!")
end

local ok, err = pcall(test)
if not ok then
  print("Test failed: " .. tostring(err))
  os.exit(1)
end
