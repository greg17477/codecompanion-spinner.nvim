# 🌀 CodeCompanion Spinner

## 📖 Overview

Elegant, state-aware status feedback for [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim).

This plugin provides a non-intrusive floating spinner that tracks the lifecycle of AI requests, tool executions, and user interactions within your CodeCompanion chat buffers.

![demo-spinner](https://github.com/user-attachments/assets/66191a4e-8bab-4c37-88f6-f208c9f387ea)

## ✨ Features

- **Lifecycle Tracking:** Visual feedback for thinking, receiving (streaming), tool execution, and diff generation.
- **State-Aware Messages:** Contextual indicators for "Awaiting Approval", "Diff Attached", and more.
- **Multi-Chat Support:** Concurrent requests across different chat buffers are managed independently.
- **Zero-Config by Default:** Works out of the box with sensible defaults, yet fully customizable.
- **Smart Positioning:** Heuristic floating window placement relative to the chat buffer.

## 📦 Installation

Install via your preferred package manager and register the extension in your `codecompanion` setup:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "franco-ruggeri/codecompanion-spinner.nvim",
  },
  opts = {
    -- ... your existing config ...
    extensions = {
      spinner = {}, -- Load the extension with default settings
    },
  },
}
```

## ⚙️ Configuration

While the spinner works without configuration, you can customize every aspect of its behavior and appearance.

```lua
extensions = {
  spinner = {
    log_level = "info",
    spinner_symbols = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
    done_timer = 2000, -- Duration (ms) to show the "Done!" message
    timer_interval = 200, -- Animation speed
    messages = {
      thinking = "thinking",
      receiving = "receiving",
      tool_running = "tool running",
      tool_processing = "tool processing",
      awaiting_approval = "󱗿 Awaiting approval",
      diff_attached = "󰙶 Diff attached",
      done = "󰄬 Done!",
    },
    window = {
      width = 20,
      height = 1,
      row = -2,    -- Offset from bottom of the chat window
      col = -1,    -- Offset from right edge
      padding = 1, -- Right padding
      winblend = 0,
      zindex = 200,
      border = "none",
      style = "minimal",
      focusable = false,
      winhl = nil, -- e.g., 'Normal:Comment,NormalNC:Comment'
    },
    highlights = {
      spinner = "DiagnosticError",
      thinking = "DiagnosticHint",
      receiving = "DiagnosticInfo",
      awaiting_approval = "DiagnosticWarn",
      diff_attached = "DiagnosticWarn",
      tool_running = "DiagnosticHint",
      tool_processing = "DiagnosticHint",
      done = "DiagnosticOk",
    },
  },
},
```

### Customizing Highlights

The spinner uses the following highlight groups. You can override them in your colorscheme setup:

| Group | Default | Description |
| :--- | :--- | :--- |
| `spinner` | `DiagnosticError` | The animated symbol |
| `thinking` | `DiagnosticHint` | Text while AI is processing |
| `receiving` | `DiagnosticInfo` | Text while AI is streaming |
| `awaiting_approval` | `DiagnosticWarn` | When a tool requires user input |
| `diff_attached` | `DiagnosticWarn` | When a diff is ready for review |
| `done` | `DiagnosticOk` | Final success state |

## 🙏 Acknowledgements

- [yuhua99](https://github.com/yuhua99) for the original [spinner logic](https://github.com/olimorris/codecompanion.nvim/discussions/640#discussioncomment-12866279).
- [olimorris](https://github.com/olimorris) for the excellent [codecompanion.nvim](https://github.com/olimorris/codecompanion.nvim).
