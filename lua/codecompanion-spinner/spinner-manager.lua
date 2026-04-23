local log = require("codecompanion-spinner.log")
local Spinner = require("codecompanion-spinner.spinner")

local M = {}

local spinners = {} -- one spinner per chat
local config = {}

local function create_spinner(chat_id, bufnr)
  if not chat_id then
    return nil
  end

  if spinners[chat_id] then
    return spinners[chat_id]
  end

  log.debug("Creating spinner for chat", chat_id, "in buffer", bufnr)
  local spinner = Spinner:new(chat_id, bufnr, config)
  spinner:enable()
  spinners[chat_id] = spinner
  return spinner
end

local function get_chat_id(data, bufnr)
  if data then
    local id = (data.chat and data.chat.id) or data.id
    if id then
      return id, bufnr
    end

    -- Fallback to bufnr in data
    if data.bufnr and data.bufnr > 0 then
      local ok, cc = pcall(require, "codecompanion")
      if ok then
        local chat = cc.buf_get_chat(data.bufnr)
        if chat and chat.id then
          return chat.id, data.bufnr
        end
      end
    end
  end

  if bufnr and bufnr > 0 then
    local ok, cc = pcall(require, "codecompanion")
    if ok then
      local chat = cc.buf_get_chat(bufnr)
      if chat and chat.id then
        return chat.id, bufnr
      end
    end
  end

  return nil, nil
end

function M.get_spinner(chat_id)
  if not chat_id then
    return nil
  end
  return spinners[chat_id]
end

M.setup = function(opts)
  config = opts or {}

  -- Scan for existing CodeCompanion buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local ft = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
    if ft == "codecompanion" then
      local ok, cc = pcall(require, "codecompanion")
      if ok then
        local chat = cc.buf_get_chat(bufnr)
        if chat and chat.id then
          create_spinner(chat.id, bufnr)
        end
      end
    end
  end

  local group = vim.api.nvim_create_augroup("CodeCompanionSpinnerManager", { clear = true })

  local all_events = {
    "CodeCompanionChatCreated",
    "CodeCompanionChatClosed",
    "CodeCompanionChatOpened",
    "CodeCompanionChatHidden",

    "CodeCompanionRequestStarted",
    "CodeCompanionRequestStreaming",
    "CodeCompanionRequestFinished",

    "CodeCompanionToolStarted",
    "CodeCompanionToolFinished",
    "CodeCompanionToolApprovalRequested",
    "CodeCompanionToolApprovalFinished",

    "CodeCompanionChatDone",
    "CodeCompanionChatStopped",
  }

  vim.api.nvim_create_autocmd("User", {
    pattern = all_events,
    group = group,
    callback = function(args)
      local event = args.match
      local chat_id, target_bufnr = get_chat_id(args.data, args.buf)

      if not chat_id then
        return
      end

      local spinner = spinners[chat_id]

      spinner = create_spinner(chat_id, target_bufnr)

      if not spinner then
        return
      end

      -- Dispatch actions
      if event == "CodeCompanionChatClosed" then
        spinner:disable()
        spinners[chat_id] = nil
      elseif event == "CodeCompanionChatHidden" then
        spinner:disable()
      elseif event == "CodeCompanionChatOpened" then
        spinner:enable()
      else
        -- Pass the full data payload to the spinner
        spinner:handle_event(event, args.data)
      end
    end,
  })
end

return M
