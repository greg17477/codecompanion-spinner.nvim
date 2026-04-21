local log = require("codecompanion-spinner.log")

local M = {}

-- State Dimensions
local REQ_STATE = {
  IDLE = "IDLE",
  STREAMING = "STREAMING",
  FINISHED = "FINISHED", -- Turn/Request finished, but chat continues
  DONE = "DONE", -- Entire interaction finished
}

local CONTENT_STATE = {
  NONE = "NONE",
  REASONING = "REASONING",
  RESPONSE = "RESPONSE",
}

local TOOL_PHASE = {
  NONE = "NONE",
  RUNNING = "RUNNING",
  FINISHED = "FINISHED",
  PROCESSING = "PROCESSING",
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
    has_tool_call = false,
    is_stopped = false,
    active_tool = nil,

    -- Boundary tracking for polling
    chat_obj = nil,
    start_chunks = 0,

    -- Window/Timer management
    timer = nil,
    done_timer = nil,
    win_id = nil,
    namespace_id = vim.api.nvim_create_namespace("CodeCompanionSpinner"),
    spinner_index = 0,
    spinner_symbols = opts.spinner_symbols,

    -- Dirty checking
    last_ui_msg = nil,
    last_spinner_index = -1,

    -- Diff state
    diff_attached = false,
  }

  -- Set up highlights once
  local hl = object.opts.highlights or {}
  local highlights = {
    CodeCompanionSpinner = hl.spinner,
    CodeCompanionSpinnerThinking = hl.thinking,
    CodeCompanionSpinnerThinkingSymbol = hl.thinking_symbol,
    CodeCompanionSpinnerReceiving = hl.receiving,
    CodeCompanionSpinnerReceivingSymbol = hl.receiving_symbol,
    CodeCompanionSpinnerAwaitingApproval = hl.awaiting_approval,
    CodeCompanionSpinnerAwaitingApprovalSymbol = hl.awaiting_approval_symbol,
    CodeCompanionSpinnerDiffAttached = hl.diff_attached,
    CodeCompanionSpinnerDiffAttachedSymbol = hl.diff_attached_symbol,
    CodeCompanionSpinnerToolRunning = hl.tool_running,
    CodeCompanionSpinnerToolRunningSymbol = hl.tool_running_symbol,
    CodeCompanionSpinnerToolFinished = hl.tool_finished,
    CodeCompanionSpinnerToolFinishedSymbol = hl.tool_finished_symbol,
    CodeCompanionSpinnerToolProcessing = hl.tool_processing,
    CodeCompanionSpinnerToolProcessingSymbol = hl.tool_processing_symbol,
    CodeCompanionSpinnerDone = hl.done,
    CodeCompanionSpinnerDoneSymbol = hl.done_symbol,
    CodeCompanionSpinnerStopped = hl.stopped,
    CodeCompanionSpinnerStoppedSymbol = hl.stopped_symbol,
  }
  for group, link in pairs(highlights) do
    if link then
      vim.api.nvim_set_hl(0, group, { link = link, default = true })
    end
  end

  self.__index = self
  setmetatable(object, self)
  return object
end

--- Derive UI state based on strict priority hierarchy
--- @return string|nil message, string|nil state_key, boolean is_animated
function M:_get_ui_state()
  local msgs = self.opts.messages or {}

  -- 1. Awaiting Approval or Diff (Highest Priority)
  if self.tool_phase == TOOL_PHASE.AWAITING_APPROVAL or self.diff_attached then
    if self.tool_phase == TOOL_PHASE.AWAITING_APPROVAL then
      return msgs.awaiting_approval, "awaiting_approval", false
    end
    return msgs.diff_attached or msgs.awaiting_approval, "diff_attached", false
  end

  -- 2. Active Tool Work
  if self.tool_phase == TOOL_PHASE.RUNNING or self.tool_count > 0 then
    local msg = msgs.tool_running
    if self.active_tool then
      msg = msg .. " [" .. self.active_tool .. "]"
    end
    return msg, "tool_running", true
  end

  -- 3. Tool Just Finished (Transient State while streaming)
  if self.tool_phase == TOOL_PHASE.FINISHED then
    return msgs.tool_finished, "tool_finished", false
  end

  -- 4. Tool Processing / Waiting for next turn
  -- If tool ended while NOT streaming, or we are specifically in PROCESSING phase
  -- But ONLY if we are not in a terminal DONE state (which is handled later)
  if
    (self.req_state ~= REQ_STATE.DONE and self.req_state ~= REQ_STATE.STREAMING) and
    (self.tool_phase == TOOL_PHASE.PROCESSING or (self.has_tool_call and self.req_state ~= REQ_STATE.IDLE))
  then
    return msgs.tool_processing, "tool_processing", false
  end

  -- 5. Streaming Response vs Reasoning
  if self.req_state == REQ_STATE.STREAMING then
    if self.content_phase == CONTENT_STATE.RESPONSE then
      return msgs.receiving, "receiving", true
    end
    return msgs.thinking, "thinking", true
  end

  -- 6. Done / Stopped / Finished
  if self.req_state == REQ_STATE.DONE or self.req_state == REQ_STATE.FINISHED then
    if self.is_stopped then
      return msgs.stopped or msgs.done, "stopped", false
    end
    return msgs.done, "done", false
  end

  return nil, nil, false
end

function M:_clear_done_timer()
  if self.done_timer then
    pcall(function()
      self.done_timer:stop()
    end)
    self.done_timer = nil
  end
end

function M:handle_event(event, data)
  -- Guard: Prevent late or out-of-order events from re-activating the spinner
  if self.req_state == REQ_STATE.DONE then
    local wake_up_events = {
      CodeCompanionRequestStarted = true,
      CodeCompanionRequestStreaming = true,
      CodeCompanionToolStarted = true,
      CodeCompanionToolApprovalRequested = true,
      CodeCompanionDiffAttached = true,
    }
    -- Only specific events can wake us from a terminal state
    if not wake_up_events[event] and not event:match("Chat") then
      return
    end
  end

  -- Robust chat object acquisition
  if data and data.chat then
    self.chat_obj = data.chat
  end

  if event == "CodeCompanionRequestStarted" then
    self:_clear_done_timer()
    self.req_state = REQ_STATE.STREAMING
    -- Before response -> "thinking"
    self.content_phase = CONTENT_STATE.REASONING
    self.started = true
    -- Only reset tool phases if we're not awaiting approval
    if self.tool_phase ~= TOOL_PHASE.AWAITING_APPROVAL then
      self.tool_phase = TOOL_PHASE.NONE
    end
    self.tool_count = 0
    self.has_tool_call = false
    -- Keep diff_attached if it was already true (highest priority)
    self.is_stopped = false

    -- Boundary Lock: capture chunk count to ignore old turn data
    if not self.chat_obj then
      local ok, cc = pcall(require, "codecompanion")
      if ok then
        self.chat_obj = cc.buf_get_chat(self.buffer)
      end
    end
    if self.chat_obj and self.chat_obj.builder and self.chat_obj.builder.state then
      self.start_chunks = self.chat_obj.builder.state.total_chunks or 0
    else
      self.start_chunks = 0
    end
  elseif event == "CodeCompanionRequestStreaming" then
    if self.req_state ~= REQ_STATE.STREAMING then
      self.req_state = REQ_STATE.STREAMING
    end
    self.started = true
    -- Immediate poll to catch phase changes (thinking -> receiving)
    self:_poll_state()
  elseif event == "CodeCompanionRequestFinished" then
    -- Ensure we have the absolute latest state before finishing the turn
    self:_poll_state()
    self:on_stream_end(REQ_STATE.FINISHED)
  elseif event == "CodeCompanionToolStarted" then
    self:_clear_done_timer()
    self.tool_count = self.tool_count + 1
    if self.tool_phase ~= TOOL_PHASE.AWAITING_APPROVAL then
      self.tool_phase = TOOL_PHASE.RUNNING
    end
    if data and data.tool and data.tool.name then
      self.active_tool = data.tool.name
    end
    self.has_tool_call = true
    self.started = true
  elseif event == "CodeCompanionToolFinished" then
    self.tool_count = math.max(0, self.tool_count - 1)
    if self.tool_count == 0 then
      self.active_tool = nil
      -- Transient state: show "tool finished" briefly
      self.tool_phase = TOOL_PHASE.FINISHED
      vim.defer_fn(function()
        if self.tool_phase == TOOL_PHASE.FINISHED then
          -- Priority: if still streaming, fall back to thinking/receiving
          if self.req_state == REQ_STATE.STREAMING then
            self.tool_phase = TOOL_PHASE.NONE
            self:_poll_state()
          else
            self.tool_phase = TOOL_PHASE.PROCESSING
          end
          self:_update_timer_state()
        end
      end, 500)
    end
  elseif event == "CodeCompanionToolsFinished" then
    self.tool_count = 0
    self.active_tool = nil
    self.tool_phase = TOOL_PHASE.PROCESSING
    self.has_tool_call = true
  elseif event == "CodeCompanionToolApprovalRequested" then
    self:_clear_done_timer()
    self.tool_phase = TOOL_PHASE.AWAITING_APPROVAL
    self.has_tool_call = true
    self.started = true
  elseif event == "CodeCompanionToolApprovalFinished" then
    if self.tool_count > 0 then
      self.tool_phase = TOOL_PHASE.RUNNING
    else
      self.tool_phase = TOOL_PHASE.PROCESSING
    end
  elseif event == "CodeCompanionDiffAttached" then
    self:_clear_done_timer()
    self.diff_attached = true
    self.started = true
  elseif
    event == "CodeCompanionDiffDetached"
    or event == "CodeCompanionDiffAccepted"
    or event == "CodeCompanionDiffRejected"
  then
    self.diff_attached = false
  elseif event == "CodeCompanionChatDone" or event == "CodeCompanionChatStopped" then
    self.is_stopped = (event == "CodeCompanionChatStopped")
    self.tool_phase = TOOL_PHASE.NONE
    self.tool_count = 0
    self.diff_attached = false
    self:on_stream_end(REQ_STATE.DONE)
  end

  self:_update_timer_state()
end

function M:on_stream_end(state)
  -- Use a larger grace period (300ms) to avoid flashing "Done" before
  -- subsequent ToolStarted or RequestStarted events arrive.
  self:_clear_done_timer()

  self.done_timer = vim.defer_fn(function()
    self.req_state = state or REQ_STATE.DONE
    self.started = false

    -- If we are truly done (no tools, no approval, no diff), show the "Done" message for a while
    if self.tool_count == 0 and self.tool_phase ~= TOOL_PHASE.AWAITING_APPROVAL and not self.diff_attached then
      self.done_timer = vim.defer_fn(function()
        if self.req_state == REQ_STATE.DONE or self.req_state == REQ_STATE.FINISHED then
          self.req_state = REQ_STATE.IDLE
          self.content_phase = CONTENT_STATE.NONE
          if self.tool_phase ~= TOOL_PHASE.AWAITING_APPROVAL then
            self.tool_phase = TOOL_PHASE.NONE
          end
          if not self.diff_attached then
            self.diff_attached = false
          end
          self.started = false
          self.chat_obj = nil
          self.done_timer = nil
          self:_update_timer_state()
        end
      end, self.opts.done_timer)
    else
      self.done_timer = nil
    end

    self:_update_timer_state()
  end, 300)

  self:_update_timer_state()
end

function M:_poll_state()
  if not self.chat_obj then
    local ok, cc = pcall(require, "codecompanion")
    if ok then
      self.chat_obj = cc.buf_get_chat(self.buffer)
    end
  end

  if not self.chat_obj then
    return
  end

  local builder = self.chat_obj.builder
  if not builder or not builder.state then
    return
  end

  if self.chat_obj.status == "awaiting_approval" then
    self.tool_phase = TOOL_PHASE.AWAITING_APPROVAL
    self.has_tool_call = true
  end

  if not self.chat_obj.current_request and self.req_state ~= REQ_STATE.STREAMING then
    return
  end

  local current_chunks = builder.state.total_chunks or 0
  if current_chunks <= self.start_chunks then
    return
  end

  local block_type = builder.state.current_block_type
  if block_type == "reasoning_message" then
    self.content_phase = CONTENT_STATE.REASONING
  elseif block_type == "llm_message" or block_type == "tool_use" then
    self.content_phase = CONTENT_STATE.RESPONSE
    if block_type == "tool_use" or (builder.tools and #builder.tools > 0) then
      self.has_tool_call = true
    end
  end
end


function M:_update_text()
  local should_be_open = self.enabled and (
    self.started
    or self.req_state == REQ_STATE.FINISHED
    or self.req_state == REQ_STATE.DONE
    or self.tool_phase ~= TOOL_PHASE.NONE
    or self.diff_attached
  )

  if not should_be_open then
    self:_close_window()
    return
  end

  if self.req_state == REQ_STATE.STREAMING then
    self:_poll_state()
  end

  local msg, state_key, is_animated = self:_get_ui_state()

  if not msg or not state_key then
    self:_close_window()
    return
  end

  if is_animated then
    self.spinner_index = (self.spinner_index % #self.spinner_symbols) + 1
  end

  if msg == self.last_ui_msg and self.spinner_index == self.last_spinner_index then
    return
  end

  local symbol = ""
  if is_animated then
    symbol = self.spinner_symbols[self.spinner_index]
  else
    symbol = self.opts.symbols[state_key] or ""
  end

  local display_text = " " .. msg
  local full_text = symbol .. display_text
  log.info("UI Update: " .. full_text)

  local total_width = self.opts.window.width
  local right_padding = self.opts.window.padding
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
  local win_width = vim.api.nvim_win_get_width(self.win_id)
  local leading_spaces = math.max(0, win_width - content_width - right_padding)
  local line = string.rep(" ", leading_spaces) .. full_text .. string.rep(" ", right_padding)

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
  vim.api.nvim_buf_clear_namespace(buf, self.namespace_id, 0, -1)

  local camel_state = state_key:gsub("_(%l)", string.upper):gsub("^%l", string.upper)
  local hl_group = "CodeCompanionSpinner" .. camel_state
  local symbol_hl_group = hl_group .. "Symbol"

  if symbol ~= "" then
    vim.api.nvim_buf_set_extmark(buf, self.namespace_id, 0, leading_spaces, {
      end_col = leading_spaces + #symbol,
      hl_group = symbol_hl_group,
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

  local row = win_config.row
  if row < 0 then
    row = math.max(0, win_height + row)
  end

  local col = win_config.col
  if col < 0 then
    col = math.max(0, win_width - width + (col + 1))
  end

  local config = {
    relative = "win",
    win = chat_win_id,
    width = width,
    height = win_config.height,
    row = row,
    col = col,
    zindex = win_config.zindex,
    border = win_config.border,
    style = win_config.style,
    focusable = win_config.focusable,
    noautocmd = win_config.noautocmd,
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
    vim.api.nvim_set_option_value("winblend", win_config.winblend, { win = self.win_id })
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
  self.timer:start(0, self.opts.timer_interval, timer_fn)
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
  if self.enabled and (
    self.started
    or self.req_state == REQ_STATE.FINISHED
    or self.req_state == REQ_STATE.DONE
    or self.tool_phase ~= TOOL_PHASE.NONE
    or self.diff_attached
  ) then
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
