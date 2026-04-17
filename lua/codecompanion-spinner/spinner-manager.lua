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
			-- Try to get the chat from the buffer's variables if available
			local ok, chat = pcall(vim.api.nvim_buf_get_var, bufnr, "codecompanion_chat")
			if ok and chat and chat.id then
				create_spinner(chat.id, bufnr)
			end
		end
	end

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionChatCreated",
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
		callback = function(args)
			log.debug("Event: CodeCompanionChatHidden")
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]
			if spinner then
				spinner:disable()
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestStarted",
		callback = function(args)
			log.debug("Event: CodeCompanionRequestStarted")
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]
			if not spinner and chat_id then
				spinner = create_spinner(chat_id, args.buf)
			end

			if spinner then
				spinner:set_state("thinking")
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestStreaming",
		callback = function(args)
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]

			if not spinner then
				-- Fallback: If chat_id detection fails, transition the active thinking spinner
				for _, s in pairs(spinners) do
					if s.state == "thinking" then
						s:set_state("receiving")
						return
					end
				end
				return
			end

			if spinner.state == "thinking" then
				spinner:set_state("receiving")
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionToolApprovalRequested",
		callback = function(args)
			log.debug("Event: CodeCompanionToolApprovalRequested")
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]
			if spinner then
				spinner:set_state("awaiting_approval")
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionToolStarted",
		callback = function(args)
			log.debug("Event: CodeCompanionToolStarted")
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]
			if spinner then
				spinner:set_state("tool_running")
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionToolFinished",
		callback = function(args)
			log.debug("Event: CodeCompanionToolFinished")
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]
			if spinner then
				spinner:set_state("thinking")
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestFinished",
		callback = function(args)
			log.debug("Event: CodeCompanionRequestFinished")
			local chat_id = get_chat_id(args.data)
			local spinner = spinners[chat_id]
			if spinner then
				spinner:set_state("done")
			end
		end,
	})
end

return M
