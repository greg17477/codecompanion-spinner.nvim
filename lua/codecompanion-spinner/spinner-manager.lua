local log = require("codecompanion-spinner.log")
local Spinner = require("codecompanion-spinner.spinner")

local M = {}

local spinners = {} -- one spinner per chat
local config = {}

local function create_spinner(chat_id, bufnr)
  if spinners[chat_id] then
    return spinners[chat_id]
  end

  log.debug("Creating spinner for chat", chat_id, "in buffer", bufnr)
  local spinner = Spinner:new(chat_id, bufnr, config)
  spinner:enable()
  spinners[chat_id] = spinner
  return spinner
end

local function get_chat_id(data)
  if not data then
    return nil
  end
  return (data.chat and data.chat.id) or data.id
end

M.setup = function(opts)
  config = opts or {}

  -- Scan for existing CodeCompanion buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if ft == "codecompanion" then
      local ok, chat = pcall(vim.api.nvim_buf_get_var, bufnr, "codecompanion_chat")
      if ok and chat and chat.id then
        create_spinner(chat.id, bufnr)
      end
    end
  end

  local group = vim.api.nvim_create_augroup("CodeCompanionSpinnerManager", { clear = true })

  -- Lifecycle events
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatCreated",
    group = group,
    callback = function(args)
      log.debug("Event: CodeCompanionChatCreated")
      local chat_id = get_chat_id(args.data)
      if chat_id then
        create_spinner(chat_id, args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatClosed",
    group = group,
    callback = function(args)
      log.debug("Event: CodeCompanionChatClosed")
      local chat_id = get_chat_id(args.data)
      local spinner = spinners[chat_id]
      if spinner then
        spinner:disable()
        spinners[chat_id] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatOpened",
    group = group,
    callback = function(args)
      log.debug("Event: CodeCompanionChatOpened")
      local chat_id = get_chat_id(args.data)
      local spinner = spinners[chat_id]
      if not spinner and chat_id then
        spinner = create_spinner(chat_id, args.buf)
      end
      if spinner then
        spinner:enable()
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatHidden",
    group = group,
    callback = function(args)
      log.debug("Event: CodeCompanionChatHidden")
      local chat_id = get_chat_id(args.data)
      local spinner = spinners[chat_id]
      if spinner then
        spinner:disable()
      end
    end,
  })

  -- State tracking events
  local state_events = {
    "CodeCompanionRequestStarted",
    "CodeCompanionRequestStreaming",
    "CodeCompanionRequestFinished",
    "CodeCompanionToolStarted",
    "CodeCompanionToolFinished",
    "CodeCompanionToolsFinished",
    "CodeCompanionToolApprovalRequested",
    "CodeCompanionChatDone",
    "CodeCompanionChatStopped",
  }

  vim.api.nvim_create_autocmd("User", {
    pattern = state_events,
    group = group,
    callback = function(args)
      log.debug("Event:", args.match)
      local chat_id = get_chat_id(args.data)
      local spinner = spinners[chat_id]

      if not spinner and chat_id then
        spinner = create_spinner(chat_id, args.buf)
      end

      if spinner then
        spinner:handle_event(args.match)
      else
        -- Fallback: If chat_id detection fails, try to find a plausible spinner
        -- This is mostly for streaming events where data might be sparse
        if args.match == "CodeCompanionRequestStreaming" then
           for _, s in pairs(spinners) do
             if s.state == "thinking" then
               s:handle_event(args.match)
               return
             end
           end
        end
      end
    end,
  })
end

return M
