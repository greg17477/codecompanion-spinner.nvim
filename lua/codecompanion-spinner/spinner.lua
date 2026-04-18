local log = require("codecompanion-spinner.log")

local M = {}

-- State Dimensions
local REQ_STATE = {
  IDLE = "IDLE",
  STREAMING = "STREAMING",
  FINISHED = "FINISHED",
}

local CONTENT_STATE = {
  NONE = "NONE",
  REASONING = "REASONING",
  RESPONSE = "RESPONSE",
}

local TOOL_PHASE = {
  NONE = "NONE",
  RUNNING = "RUNNING",
  AWAITING_APPROVAL = "AWAITING_APPROVAL",
}

function M:new(chat_id, buffer, opts)
  local object = {
    chat_id = chat_id,
    buffer = buffer,
    opts = opts or {},
    enabled = false,
    started = false,

    -- Internal State Machine
    req_state = REQ_STATE.IDLE,
    content_phase = CONTENT_STATE.NONE,
    tool_phase = TOOL_PHASE.NONE,
    tool_count = 0,

    -- Boundary tracking for polling
    chat_obj = nil,
    start_chunks = 0,

    -- Window/Timer management
    timer = nil,
    done_timer = nil,
    win_id = nil,
    namespace_id = vim.api.nvim_create_namespace("CodeCompanionSpinner"),
    spinner_index = 0,
    spinner_symbols = opts.spinner_symbols or { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },

    -- Dirty checking
    last_ui_msg = nil,
    last_spinner_index = -1,
  }

  -- Set up highlights once
  local hl = object.opts.highlights or {}
  local highlights = {
    CodeCompanionSpinner = hl.spinner or "DiagnosticError",
    CodeCompanionSpinnerThinking = hl.thinking or "DiagnosticHint",
    CodeCompanionSpinnerReceiving = hl.receiving or "DiagnosticInfo",
    CodeCompanionSpinnerAwaitingApproval = hl.awaiting_approval or "DiagnosticWarn",
    CodeCompanionSpinnerDiffAttached = hl.diff_attached or "DiagnosticWarn",
    CodeCompanionSpinnerToolRunning = hl.tool_running or "DiagnosticHint",
    CodeCompanionSpinnerToolProcessing = hl.tool_processing or "DiagnosticHint",
    CodeCompanionSpinnerDone = hl.done or "DiagnosticOk",
  }
  for group, link in pairs(highlights) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end

  self.__index = self
  setmetatable(object, self)
  return object
end

--- Derive UI state based on strict priority hierarchy
--- @return string|nil message, string|nil highlight_group, boolean is_animated
function M:_get_ui_state()
  local msgs = self.opts.messages or {}

  -- 1. Terminal State
  if self.req_state == REQ_STATE.FINISHED then
    return msgs.done or "󰄬 Done!", "CodeCompanionSpinnerDone", false
  end

  -- 2. Tool Priority
  if self.tool_phase == TOOL_PHASE.AWAITING_APPROVAL then
    return msgs.awaiting_approval or "󱗿 Awaiting approval", "CodeCompanionSpinnerAwaitingApproval", false
  end
  if self.tool_phase == TOOL_PHASE.RUNNING then
    return msgs.tool_running or "...tool running", "CodeCompanionSpinnerToolRunning", true
  end

  -- 3. Streaming Phase
  if self.req_state == REQ_STATE.STREAMING then
    if self.content_phase == CONTENT_STATE.RESPONSE then
      return msgs.receiving or "...receiving", "CodeCompanionSpinnerReceiving", true
    elseif self.content_phase == CONTENT_STATE.REASONING then
      return msgs.thinking or "...thinking", "CodeCompanionSpinnerThinking", true
    end
  end

  return nil, nil, false
end

function M:handle_event(event, data)
  -- Guard: No updates after finished
  if self.req_state == REQ_STATE.FINISHED and event ~= "CodeCompanionRequestStarted" then
    return
  end

  -- Robust chat object acquisition
  if data and data.chat then
    self.chat_obj = data.chat
  end

  if event == "CodeCompanionRequestStarted" then
    self.req_state = REQ_STATE.STREAMING
    -- Before response -> "thinking" (Requirement satisfied)
    self.content_phase = CONTENT_STATE.REASONING
    self.started = true
    self.tool_phase = TOOL_PHASE.NONE
    self.tool_count = 0

    -- Boundary Lock: capture chunk count to ignore old turn data
    if not self.chat_obj then
      local ok, cc = pcall(require, "codecompanion")
      if ok then self.chat_obj = cc.buf_get_chat(self.buffer) end
    end
    if self.chat_obj and self.chat_obj.builder and self.chat_obj.builder.state then
      self.start_chunks = self.chat_obj.builder.state.total_chunks or 0
    else
      self.start_chunks = 0
    end

  elseif event == "CodeCompanionRequestStreaming" then
    if self.req_state ~= REQ_STATE.STREAMING then return end
    self.started = true

  elseif event == "CodeCompanionToolStarted" then
    self.tool_count = self.tool_count + 1
    self.tool_phase = TOOL_PHASE.RUNNING
    self.started = true

  elseif event == "CodeCompanionToolFinished" then
    self.tool_count = math.max(0, self.tool_count - 1)
    if self.tool_count == 0 then
      self.tool_phase = TOOL_PHASE.NONE
    end

  elseif event == "CodeCompanionToolsFinished" then
    self.tool_count = 0
    self.tool_phase = TOOL_PHASE.NONE

  elseif event == "CodeCompanionToolApprovalRequested" then
    self.tool_phase = TOOL_PHASE.AWAITING_APPROVAL
    self.started = true

  elseif event == "CodeCompanionToolApprovalFinished" then
    self.tool_phase = self.tool_count > 0 and TOOL_PHASE.RUNNING or TOOL_PHASE.NONE

  elseif event == "CodeCompanionChatDone" or event == "CodeCompanionChatStopped" then
    self:on_stream_end()
  end

  self:_update_timer_state()
end

function M:on_stream_end()
  -- FULL RESET
  self.req_state = REQ_STATE.FINISHED
  self.content_phase = CONTENT_STATE.NONE
  self.tool_phase = TOOL_PHASE.NONE
  self.tool_count = 0
  self.started = false

  if self.done_timer then
    self.done_timer:stop()
  end

  self.done_timer = vim.defer_fn(function()
    self.req_state = REQ_STATE.IDLE
    self.chat_obj = nil
    self:_update_timer_state()
  end, self.opts.done_timer or 2000)

  self:_update_timer_state()
end

--- Extract status by comparing builder state against the request start boundary
function M:_poll_state()
  if not self.chat_obj then
    local ok, cc = pcall(require, "codecompanion")
    if ok then self.chat_obj = cc.buf_get_chat(self.buffer) end
  end

  if not self.chat_obj then return end

  -- Boundary Check 1: If no request is running, we are effectively idle
  if not self.chat_obj.current_request then
    self.content_phase = CONTENT_STATE.NONE
    return
  end

  local builder = self.chat_obj.builder
  if not builder or not builder.state then return end

  -- Boundary Check 2: Only override "Thinking" if fresh chunks have arrived
  local current_chunks = builder.state.total_chunks or 0
  if current_chunks <= self.start_chunks then
    -- Stay in current phase (Thinking) while waiting for the first token
    return
  end

  local block_type = builder.state.current_block_type
  if block_type == "reasoning_message" then
    -- Reasoning is weak: only active if no response tokens seen yet
    if self.content_phase ~= CONTENT_STATE.RESPONSE then
      self.content_phase = CONTENT_STATE.REASONING
    end
  elseif block_type == "llm_message" then
    -- Response MUST override reasoning
    self.content_phase = CONTENT_STATE.RESPONSE
  end
end

function M:_update_text()
  -- Window Stay-Open Condition
  local should_be_open = self.enabled and (
    self.started
    or self.req_state == REQ_STATE.FINISHED
    or self.tool_phase ~= TOOL_PHASE.NONE
  )

  if not should_be_open then
    self:_close_window()
    return
  end

  -- Synchronize state with CodeCompanion internal builder
  if self.req_state == REQ_STATE.STREAMING then
    self:_poll_state()
  end

  local msg, hl_group, is_animated = self:_get_ui_state()

  -- If state is NONE, hide window.
  if not msg then
    self:_close_window()
    return
  end

  if is_animated then
    self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
  end

  -- Dirty check
  if msg == self.last_ui_msg and self.spinner_index == self.last_spinner_index then
    return
  end

  local symbol = is_animated and self.spinner_symbols[self.spinner_index] or ""
  local display_text = " " .. msg
  local full_text = symbol .. display_text

  local total_width = self.opts.window.width or 20
  local right_padding = self.opts.window.padding or 1
  local content_width = vim.fn.strdisplaywidth(full_text)
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
  local line = string.rep(" ", leading_spaces) .. full_text .. string.rep(" ", right_padding)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(buf, self.namespace_id, 0, -1)

  if symbol ~= "" then
    vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces, {
      end_col = leading_spaces + #symbol,
      hl_group = "CodeCompanionSpinner",
    })
    vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces + #symbol, {
      end_col = leading_spaces + #symbol + #display_text,
      hl_group = hl_group,
    })
  else
    vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces, {
      end_col = leading_spaces + #display_text,
      hl_group = hl_group,
    })
  end

  self.last_ui_msg = msg
  self.last_spinner_index = self.spinner_index
end

function M:_get_chat_win_id()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == self.buffer then
      return win
    end
  end
  return nil
end

function M:_create_window(width)
  local chat_win_id = self:_get_chat_win_id()
  if not chat_win_id then
    return
  end

  local win_config = self.opts.window or {}
  local win_width = vim.api.nvim_win_get_width(chat_win_id)
  local win_height = vim.api.nvim_win_get_height(chat_win_id)

  local row = win_config.row or -2
  if row < 0 then
    row = math.max(0, win_height + row)
  end

  local col = win_config.col or -1
  if col < 0 then
    col = math.max(0, win_width - width + (col + 1))
  end

  local config = {
    relative = "win",
    win = chat_win_id,
    width = width,
    height = win_config.height or 1,
    row = row,
    col = col,
    zindex = win_config.zindex or 1000,
    border = win_config.border or "none",
    style = "minimal",
    focusable = win_config.focusable or false,
    noautocmd = win_config.noautocmd ~= false,
  }

  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    pcall(vim.api.nvim_win_set_config, self.win_id, config)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })

  local s, win_id = pcall(vim.api.nvim_open_win, buf, false, config)

  if s then
    self.win_id = win_id
    vim.api.nvim_set_option_value("winblend", win_config.winblend or 10, { win = self.win_id })
    if win_config.winhl then
      vim.api.nvim_set_option_value("winhighlight", win_config.winhl, { win = self.win_id })
    end
  else
    log.error("Failed to open spinner window: " .. tostring(win_id))
  end
end

function M:_close_window()
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    vim.api.nvim_win_close(self.win_id, true)
    self.win_id = nil
  end
  self.last_ui_msg = nil
  self.last_spinner_index = -1
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
end

function M:_stop_timer()
  if not self.timer then
    return
  end
  self.timer:stop()
  self.timer:close()
  self.timer = nil
end

function M:_update_timer_state()
  if self.enabled and (self.started or self.req_state == REQ_STATE.FINISHED or self.tool_phase ~= TOOL_PHASE.NONE) then
    self:_start_timer()
  else
    self:_stop_timer()
    self:_close_window()
  end
end

function M:enable()
  self.enabled = true
  self:_update_timer_state()
end

function M:disable()
  self.enabled = false
  self:_update_timer_state()
end

return M
