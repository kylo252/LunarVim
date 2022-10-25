local M = {}

local utils = require "lvim.utils"
local Log = require "lvim.core.log"
local join_paths = utils.join_paths
local in_headless = #vim.api.nvim_list_uis() == 0

local runtime_dir = get_runtime_dir() or vim.fn.stdpath "data"
local config_dir = get_config_dir() or vim.fn.stdpath "config"
local cache_dir = get_cache_dir() or vim.fn.stdpath "cache"

local snapshot_path = join_paths(cache_dir, "snapshots")

local package_name = "packer"
local package_root = join_paths(runtime_dir, "site", "pack")
local packer_install_path = join_paths(package_root, package_name, "start", "packer.nvim")

local compile_path = join_paths(config_dir, "plugin", "packer_compiled.lua")

function M.config()
  local max_jobs = 100
  if vim.fn.has "mac" == 1 then
    max_jobs = 50
  end

  lvim.builtin.packer = {
    install_path = packer_install_path,
    init_opts = {
      package_root = package_root,
      compile_path = compile_path,
      snapshot_path = snapshot_path,
      max_jobs = max_jobs, -- Limit the number of simultaneous jobs. nil means no limit
      auto_reload_compiled = false, -- Automatically reload the compiled file after creating it. (default: true)
      auto_clean = true, -- During sync(), remove unused plugins
      compile_on_sync = true, -- During sync(), run packer.compile()
      disable_commands = false, -- Disable creating commands
      opt_default = false, -- Default to using opt (as opposed to start) plugins
      transitive_opt = true, -- Make dependencies of opt plugins also opt by default
      transitive_disable = true, -- Automatically disable dependencies of disabled plugins
      preview_updates = false, -- If true, always preview updates before choosing which plugins to update, same as `PackerUpdate --preview`.
      ensure_dependencies = true, -- Should packer install plugin dependencies?
      plugin_package = package_name, -- The default package for plugins
      -- IMPORTANT: this will constantly trigger the rollback function
      -- https://github.com/wbthomason/packer.nvim/blob/c576ab3f1488ee86d60fd340d01ade08dcabd256/lua/packer.lua#L998-L995
      snapshot = nil,
      log = { level = "warn" },
      git = {
        clone_timeout = 120,
      },
      autoremove = false, -- Remove disabled or unused plugins without prompting the user
      display = {
        -- An optional function to open a window for packer's display
        open_fn = function()
          return require("packer.util").float { border = "rounded" }
        end,

        non_interactive = in_headless and true, -- If true, disable display windows for all operations
        compact = false, -- If true, fold updates results by default
        open_cmd = "65vnew \\[packer\\]", -- An optional command to open a window for packer's display
        working_sym = "⟳", -- The symbol for a plugin being installed/updated
        error_sym = "✗", -- The symbol for a plugin with an error in installation/updating
        done_sym = "✓", -- The symbol for a plugin which has completed installation/updating
        removed_sym = "-", -- The symbol for an unused plugin which was removed
        moved_sym = "→", -- The symbol for a plugin which was moved (e.g. from opt to start)
        header_sym = "━", -- The symbol for the header line in packer's display
        show_all_info = true, -- Should packer show all update details automatically?
        prompt_border = "double", -- Border style of prompt popups.
        keybindings = { -- Keybindings for the display window
          quit = "q",
          toggle_update = "u", -- only in preview
          continue = "c", -- only in preview
          toggle_info = "<CR>",
          diff = "d",
          prompt_revert = "r",
        },
      },
    },
  }

  local status_ok, core_plugins = xpcall(function()
    return require "lvim.plugins"
  end, debug.traceback)

  if not status_ok then
    Log:warn "problems detected while loading plugins"
    Log:trace(debug.traceback())
    return
  end
  lvim.builtin.packer.core_plugins = core_plugins
end

function M.bootstrap()
  lvim.builtin = lvim.builtin or { packer = { install_path = packer_install_path } }
  local install_path = lvim.builtin.packer.install_path

  if not utils.is_directory(install_path) then
    Log:info "Downloading packer.nvim..."
    local packer_repo = "https://github.com/wbthomason/packer.nvim"

    local ret = vim.fn.system { "git", "clone", "--depth", "1", packer_repo, install_path }
    Log:info(ret or "Download complete")
    vim.cmd.packadd { "packer.nvim", bang = true }
  end
end

function M.setup()
  M.bootstrap()

  local status_ok, packer = pcall(require, "packer")
  if not status_ok then
    Log:info "Unable to initialize packer.nvim"
    return
  end
  packer.on_complete = vim.schedule_wrap(function()
    reload("lvim.utils.hooks").run_on_packer_complete()
  end)
  packer.init(lvim.builtin.packer.init_opts)
end

-- packer expects a space separated list
local function pcall_command(cmd, kwargs)
  local status_ok, msg = pcall(function()
    require("packer")[cmd](unpack(kwargs or {}))
  end)
  if not status_ok then
    Log:warn(cmd .. " failed with: " .. vim.inspect(msg))
    Log:trace(vim.inspect(vim.fn.eval "v:errmsg"))
  end
end

local function cache_clear()
  if not utils.is_file(lvim.builtin.packer.init_opts.compile_path) then
    return
  end
  if vim.fn.delete(compile_path) == 0 then
    Log:debug "deleted packer_compiled.lua"
  end
end

local function recompile()
  cache_clear()
  pcall_command "compile"
  vim.api.nvim_create_autocmd("User", {
    pattern = "PackerCompileDone",
    once = true,
    callback = function()
      if utils.is_file(lvim.builtin.packer.init_opts.compile_path) then
        Log:debug "generated packer_compiled.lua"
      end
    end,
  })
end

local function get_core_plugins()
  local list = {}
  for _, item in pairs(lvim.builtin.packer.core_plugins) do
    if not item.disable then
      table.insert(list, item[1]:match "/(%S*)")
    end
  end
  return list
end

function M.load_snapshot(snapshot_file)
  local default_snapshot = join_paths(get_lvim_base_dir(), "snapshots", "default.json")
  snapshot_file = snapshot_file or default_snapshot
  if not in_headless then
    vim.notify("Syncing core plugins is in progress..", vim.log.levels.INFO, { title = "lvim" })
  end
  Log:debug(string.format("Using snapshot file [%s]", snapshot_file))
  local core_plugins = get_core_plugins()
  pcall_command("rollback", snapshot_file, unpack(core_plugins))
end

function M.sync_core_plugins()
  -- problem: rollback() will get stuck if a plugin directory doesn't exist
  -- solution: call sync() beforehand
  -- see https://github.com/wbthomason/packer.nvim/issues/862
  vim.api.nvim_create_autocmd("User", {
    pattern = "PackerComplete",
    once = true,
    callback = function()
      require("lvim.plugin-loader").load_snapshot()
    end,
  })

  cache_clear()
  local core_plugins = get_core_plugins()
  Log:trace(string.format("Syncing core plugins: [%q]", table.concat(core_plugins, ", ")))
  pcall_command("sync", core_plugins)
end

function M.ensure_plugins()
  vim.api.nvim_create_autocmd("User", {
    pattern = "PackerComplete",
    once = true,
    callback = function()
      Log:debug "calling packer.clean()"
      pcall_command "clean"
    end,
  })
  Log:debug "calling packer.install()"
  pcall_command "install"
end

M.pcall_command = pcall_command
M.get_core_plugins = get_core_plugins
M.cache_clear = cache_clear
M.recompile = recompile

return M
