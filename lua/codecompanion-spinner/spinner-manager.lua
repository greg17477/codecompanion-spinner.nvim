local log = require("codecompanion-spinner.log")
local Spinner = require("codecompanion-spinner.spinner")

local M = {}

local spinners = {} -- one spinner per chat
local config = {}

M.setup = function(opts)
	config = opts or {}

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionChatCreated",
		callback = function(args)
			log.debug(args.match)

			local chat_id = args.data.id
			if spinners[chat_id] then
				log.debug("Spinner", chat_id, "already exists")
				return
			end

			local spinner = Spinner:new(chat_id, args.buf, config)
			spinner:enable()
			spinners[chat_id] = spinner
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionChatClosed",
		callback = function(args)
			log.debug("CodeCompanionChatClosed")
			local chat_id = args.data.id
			local spinner = spinners[chat_id]
			if not spinner then
				log.debug("Spinner", chat_id, "not found")
				return
			end
			spinner:disable()
			spinners[chat_id] = nil
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionChatOpened",
		callback = function(args)
			log.debug(args.match)

			local spinner = spinners[args.data.id]
			if spinner then
				spinner:enable()
			end
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionChatHidden",
		callback = function(args)
			log.debug(args.match)
			local chat_id = args.data.id
			local spinner = spinners[chat_id]
			if not spinner then
				log.debug("Spinner", chat_id, "not found")
				return
			end
			spinner:disable()
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionChatSubmitted",
		callback = function(args)
			log.debug(args.match)
			local chat_id = args.data.id
			local spinner = spinners[chat_id]
			if not spinner then
				log.debug("Spinner", args.data.id, "not found")
				return
			end
			spinner:set_state("thinking")
		end,
	})

	vim.api.nvim_create_autocmd("User", {
		pattern = "CodeCompanionRequestStreaming",
		callback = function(args)
			local chat_id = (args.data.chat and args.data.chat.id) or args.data.id
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
		pattern = "CodeCompanionChatDone",
		callback = function(args)
			log.debug(args.match)
			local chat_id = args.data.id
			local spinner = spinners[chat_id]
			if not spinner then
				log.debug("Spinner", chat_id, "not found")
				return
			end
			spinner:set_state("done")
		end,
	})
end

return M
