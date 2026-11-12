-- Pulse for Rex: a stock and crypto watchlist beside your agents.
--
-- `pulse-rex install` loads this from Rex's config (init.lua):
--
--   dofile("/path/to/lua/pulse.lua").setup({ bin = { "/path/to/node", "/path/to/pulse-rex.js" } })
--
-- The watchlist is a terminal program (`pulse-rex`) in a pane. These actions
-- open it, and change the saved list through the same program; every open
-- Pulse pane picks a change up within a second.
--
-- setup options:
--   bin    the command that runs pulse-rex, as a list
--   width  columns for the Pulse pane (default 48)
--   keys   { open = "cmd+shift+u", add = "...", refresh = "...", pause = "..." }; none by default

local M = {}

local TERMINAL = "com.superlogical.terminal"
local SHELL = "com.superlogical.terminal.shell"
local LABEL = "Pulse"

function M.setup(opts)
  opts = opts or {}
  local bin = opts.bin or { "pulse-rex" }
  if type(bin) == "string" then bin = { bin } end
  local width = opts.width or 48

  local function argv(...)
    local out = {}
    for _, part in ipairs(bin) do out[#out + 1] = part end
    for _, part in ipairs({ ... }) do out[#out + 1] = part end
    return out
  end

  -- Pulse runs on this Mac; a pane on a remote host would have no pulse-rex.
  local function local_only(ctx)
    if ctx.server ~= nil then
      error("Pulse: open it from a session on this Mac. Remote hosts aren't supported yet.", 0)
    end
  end

  local function run(...)
    local result, err = rex.exec(argv(...), { timeout = 10 })
    if result == nil then
      error("Pulse: couldn't run pulse-rex (" .. tostring(err) .. "). Reinstall it, then run `pulse-rex install`.", 0)
    end
    if not result.ok then
      local text = result.stderr ~= "" and result.stderr or result.stdout
      error("Pulse: " .. text:gsub("%s+$", ""), 0)
    end
    return result
  end

  -- The Pulse pane already in the focused pane's window, if there is one.
  local function existing(ctx)
    local listed = rex.session.list_blocks{}
    if type(listed) ~= "table" or type(listed.blocks) ~= "table" then return nil end
    local window
    for _, block in ipairs(listed.blocks) do
      if block.block_id == ctx.block_id then window = block.window_id end
    end
    for _, block in ipairs(listed.blocks) do
      if block.label == LABEL and block.placement == "placed" and block.window_id == window then
        return block.block_id
      end
    end
    return nil
  end

  rex.action{
    name = "pulse_open",
    title = "Pulse: Open Watchlist",
    description = "Stock and crypto quotes in a pane beside this one, with today's line for each ticker.",
    category = "Pulse",
    keywords = "pulse stocks crypto quotes ticker watchlist market price",
    run = function(ctx)
      local_only(ctx)
      local found = existing(ctx)
      if found ~= nil then
        rex.session.focus_block{ block_id = found }
        return
      end
      if ctx.block_id == nil then
        local layout = { block = { flavor = SHELL, label = LABEL, options = { command = argv() } } }
        local _, err = rex.session.new_window{ label = LABEL, layout = layout, focus = true }
        if err ~= nil then error("Pulse: couldn't open a tab: " .. tostring(err), 0) end
        return
      end
      -- Rex sizes splits by fraction, so turn the wanted width into one. The
      -- app evens out a new split once it shows, so pulse-rex moves the border
      -- itself after it starts (--beside, --ratio).
      local command = argv()
      local size = rex.block.call(TERMINAL, "size", { block_id = ctx.block_id })
      if type(size) == "table" and type(size.columns) == "number" and size.columns > width * 1.5 then
        local ratio = math.max(0.3, math.min(0.85, (size.columns - width - 1) / size.columns))
        command = argv("tui", "--beside", ctx.block_id, "--ratio", string.format("%.4f", ratio))
      end
      local _, err = rex.session.new_split{
        anchor_id = ctx.block_id,
        direction = "horizontal",
        side = "after",
        focus = true,
        layout = { block = { flavor = SHELL, label = LABEL, options = { command = command } } },
      }
      if err ~= nil then error("Pulse: couldn't open a pane: " .. tostring(err), 0) end
    end,
  }

  rex.action{
    name = "pulse_add",
    title = "Pulse: Add Ticker…",
    description = "Add a stock, index or crypto pair to the watchlist: AAPL, 0700.HK, ^GSPC, BTC/USDT.",
    category = "Pulse",
    keywords = "pulse add ticker symbol stock crypto watchlist",
    args = { symbol = "string?" },
    run = function(ctx, args)
      if args.symbol ~= nil and args.symbol ~= "" then
        run("add", args.symbol)
        return
      end
      local_only(ctx)
      local _, err = rex.session.new_layer{
        bounds = { 0.3, 0.3, 0.4, 0.2 },
        focus = true,
        layout = { block = { flavor = SHELL, label = "Pulse · Add", options = { command = argv("prompt") } } },
      }
      if err ~= nil then error("Pulse: couldn't open the prompt: " .. tostring(err), 0) end
    end,
  }

  rex.action{
    name = "pulse_refresh",
    title = "Pulse: Refresh Quotes",
    description = "Fetch every ticker now in the open Pulse panes. Yahoo's cooldown still applies.",
    category = "Pulse",
    keywords = "pulse refresh reload quotes now",
    run = function() run("refresh") end,
  }

  rex.action{
    name = "pulse_pause",
    title = "Pulse: Pause or Resume",
    description = "Stop automatic refresh, or start it again. Refresh Quotes still works while paused.",
    category = "Pulse",
    keywords = "pulse pause resume stop start auto refresh",
    run = function() run("toggle-pause") end,
  }

  for short, key in pairs(opts.keys or {}) do
    rex.bind(key, "pulse_" .. short)
  end
end

return M
