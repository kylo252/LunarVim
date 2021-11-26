local M = {}

local plugin_loader = require "lvim.plugin-loader"
local utils = require "lvim.utils"
local uv = vim.loop
local Log = require "lvim.core.log"
local in_headless = #vim.api.nvim_list_uis() == 0

function M.run_pre_update()
  Log:debug "Starting pre-update hook"
  _G.__luacache.clear_cache()
  vim.cmd "LspStop"
end

---Reset any startup cache files used by Packer and Impatient
---It also forces regenerating any template ftplugin files
---Tip: Useful for clearing any outdated settings
function M.reset_cache()
  _G.__luacache.clear_cache()
  require("lvim.plugin-loader").recompile()
  package.loaded["lvim.lsp.templates"] = nil

  Log:debug "Re-generatring ftplugin template files"
  require("lvim.lsp.templates").generate_templates()
end

function M.run_post_update()
  Log:debug "Starting post-update hook"

  Log:debug "Re-generatring ftplugin template files"
  package.loaded["lvim.lsp.templates"] = nil
  require("lvim.lsp.templates").generate_templates()

  Log:debug "Updating core plugins"
  plugin_loader:sync_core_plugins()

  if not in_headless then
    vim.schedule(function()
      -- TODO: add a changelog
      vim.notify("Update complete", vim.log.levels.INFO)
      vim.cmd "LspRestart"
    end)
  end
end

function M.run_post_install()
  local function call_proc(process, opts, cb)
    local log, stderr, handle
    local logfile = Log:get_path()
    log = uv.fs_open(logfile, "a+", 0x1A4)
    stderr = uv.new_pipe(false)
    stderr:open(log)
    handle = uv.spawn(
      process,
      { args = opts.args, cwd = opts.cwd or vim.fn.getcwd(), stdio = { nil, nil, stderr }, env = opts.env },
      vim.schedule_wrap(function(code)
        uv.fs_close(log)
        stderr:close()
        handle:close()
        cb(code == 0)
      end)
    )
  end

  local core_plugins = require "lvim.plugins"
  local pack_root = utils.join_paths(get_runtime_dir(), "site", "pack", "packer")

  local missing_plugins = {}
  -- based on paq.nvim
  local function install(plugin)
    if plugin.disable then
      Log:trace("skipping disabled plugin: " .. plugin[1])
      return
    end
    local is_optional = plugin.cmd or plugin.event or plugin.opt
    local name = plugin[1]:match "^[%w-]+/([%w-_.]+)$"
    local plugin_dir = utils.join_paths(pack_root, is_optional and "opt" or "start", name)
    local exists = vim.fn.isdirectory(plugin_dir) ~= 0
    if exists then
      Log:trace("plugin already installed: " .. plugin[1])
      return
    end
    missing_plugins[name] = true
    local url = plugin.url or ("https://github.com/" .. plugin[1] .. ".git")
    local args = { "clone", url, "--depth=1", "--recurse-submodules", "--shallow-submodules" }
    if plugin.branch then
      vim.list_extend(args, { "-b", plugin.branch })
    end
    vim.list_extend(args, { plugin_dir })
    local post_install = function(successful)
      missing_plugins[name] = nil
      Log:debug(string.format("[%q] install status: %q", name, successful and "ok" or "err"))
    end

    Log:debug("spawining git " .. table.concat(args, " "))
    call_proc("git", { args = args, env = { "GIT_TERMINAL_PROMPT=0" } }, post_install)
  end

  Log:debug "installing core plugins"
  for _, plugin in pairs(core_plugins) do
    install(plugin)
  end
  if vim.wait(60000 * #missing_plugins, function()
    return #missing_plugins == 0
  end, 100) then
    Log:debug "installation complete"
    plugin_loader.recompile()
  end
end

return M
