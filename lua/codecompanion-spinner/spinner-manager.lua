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

function M.get_spinner(chat_id)
  return spinners[chat_id]
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

  local all_events = {
    "CodeCompanionChatCreated",
    "CodeCompanionChatClosed",
    "CodeCompanionChatOpened",
    "CodeCompanionChatHidden",

    "CodeCompanionRequestStarted",
    "CodeCompanionRequestStreaming",
    "CodeCompanionRequestFinished",

    "CodeCompanionToolsStarted",
    "CodeCompanionToolsFinished",

    "CodeCompanionToolStarted",
    "CodeCompanionToolFinished",
    "CodeCompanionToolApprovalRequested",
    "CodeCompanionToolApprovalFinished",

    "CodeCompanionDiffAttached",
    "CodeCompanionDiffDetached",
    "CodeCompanionDiffAccepted",
    "CodeCompanionDiffRejected",

    "CodeCompanionChatDone",
    "CodeCompanionChatStopped",
  }

  vim.api.nvim_create_autocmd("User", {
    pattern = all_events,
    group = group,
    callback = function(args)
      local event = args.match
      local chat_id = get_chat_id(args.data)
      local spinner = spinners[chat_id]

      vim.notify('pre spinner creatrion lookup: ' .. event)

      -- -- Handle spinner creation/lookup
      -- if not spinner and chat_id then
      --   local creation_events = {
      --     CodeCompanionChatCreated = true,
      --     CodeCompanionChatOpened = true,
      --     CodeCompanionRequestStarted = true,
      --     CodeCompanionRequestStreaming = true,
      --     -- TODO:
      --     CodeCompanionToolStarted = true,
      --     CodeCompanionToolsStarted = true,
      --     CodeCompanionToolFinished = true,
      --     CodeCompanionToolsFinished = true,
      --   }
      --   if creation_events[event] then
      --     spinner = create_spinner(chat_id, args.buf)
      --   end
      -- end


      -- if vim.tbl_contains(all_events, event) then
      --   spinner = create_spinner(chat_id, args.buf)
      -- end
      spinner = create_spinner(chat_id, args.buf)

      -- -- If we still don't have a spinner for a streaming event, try to find the active one
      -- if not spinner and event == "CodeCompanionRequestStreaming" then
      --    for _, s in pairs(spinners) do
      --      if s.req_state == "STREAMING" then
      --        spinner = s
      --        break
      --      end
      --    end
      -- end
      --
      -- if not spinner then
      --   return
      -- end

      vim.notify('post spinner creatrion lookup: ' .. event)

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
