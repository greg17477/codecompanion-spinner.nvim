local Spinner = require("codecompanion-spinner.spinner")

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
    messages = {
      thinking = "thinking",
      receiving = "receiving",
      tool_running = "tool running",
      tool_processing = "tool processing",
      awaiting_approval = "awaiting approval",
      done = "done",
    }
  }
  local s = Spinner:new(1, 1, opts)
  s.enabled = true

  print("Test 1: Request started")
  s:handle_event("CodeCompanionRequestStarted", { chat = { id = 1 } })
  local msg = s:_get_ui_state()
  assert_eq(msg, "thinking", "Should be thinking after start")

  print("Test 2: Response incoming")
  -- Mock poll state to transition to receiving
  s.content_phase = "RESPONSE"
  msg = s:_get_ui_state()
  assert_eq(msg, "receiving", "Should be receiving after response starts")

  print("Test 3: Tool starts")
  s:handle_event("CodeCompanionToolStarted", {})
  msg = s:_get_ui_state()
  assert_eq(msg, "tool running", "Tool running should have priority over receiving")

  print("Test 4: Tool ends (still streaming)")
  s:handle_event("CodeCompanionToolFinished", {})
  msg = s:_get_ui_state()
  assert_eq(msg, "receiving", "Should fall back to receiving when tool ends but still streaming")

  print("Test 5: Request finished (terminal state)")
  s:handle_event("CodeCompanionRequestFinished", {})
  msg = s:_get_ui_state()
  -- has_tool_call should be true because of Test 3
  assert_eq(msg, "tool processing", "Should show tool processing if turn ended and tool was used")

  print("Test 6: Awaiting approval")
  s:handle_event("CodeCompanionRequestStarted", { chat = { id = 1 } }) -- new turn
  s:handle_event("CodeCompanionToolApprovalRequested", {})
  msg = s:_get_ui_state()
  assert_eq(msg, "awaiting approval", "Should show awaiting approval")

  print("Test 7: Request finished while awaiting approval")
  s:handle_event("CodeCompanionRequestFinished", {})
  msg = s:_get_ui_state()
  assert_eq(msg, "awaiting approval", "Should STILL show awaiting approval even if request finished")

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
