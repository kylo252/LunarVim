local plugin_loader = {}

local in_headless = #vim.api.nvim_list_uis() == 0

local utils = require "lvim.utils"
local Log = require "lvim.core.log"

-- we need to reuse this outside of init()
local compile_path = utils.join_paths(get_config_dir(), "plugin", "packer_compiled.lua")
local default_package_root = utils.join_paths(get_runtime_dir(), "site", "pack")
local default_plugins_root = utils.join_paths(get_runtime_dir(), "site", "pack", "packer", "start")
local default_opt_plugins_root = utils.join_paths(get_runtime_dir(), "site", "pack", "packer", "opt")
local default_install_path = utils.join_paths(default_plugins_root, "packer.nvim")

function plugin_loader.init(opts)
  opts = opts or {}

  local package_root = opts.package_root or default_package_root
  local install_path = opts.install_path or default_install_path

  if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
    vim.fn.system { "git", "clone", "--depth", "1", "https://github.com/wbthomason/packer.nvim", install_path }
    vim.cmd "packadd packer.nvim"
  end

  local log_level = in_headless and "debug" or "warn"

  local _, packer = pcall(require, "packer")
  packer.init {
    package_root = package_root,
    compile_path = compile_path,
    log = { level = log_level },
    git = { clone_timeout = 300 },
    max_jobs = 50,
    display = {
      open_fn = function()
        return require("packer.util").float { border = "rounded" }
      end,
    },
  }

  if vim.fn.empty(vim.fn.glob(default_opt_plugins_root)) > 0 then
    plugin_loader.install_core_plugins()
  end
end

-- packer expects a space separated list
local function pcall_packer_command(cmd, kwargs)
  local status_ok, msg = pcall(function()
    require("packer")[cmd](unpack(kwargs or {}))
  end)
  if not status_ok then
    Log:warn(cmd .. " failed with: " .. vim.inspect(msg))
    Log:trace(vim.inspect(vim.fn.eval "v:errmsg"))
  end
end

function plugin_loader.cache_clear()
  if vim.fn.delete(compile_path) == 0 then
    Log:debug "deleted packer_compiled.lua"
  end
end

function plugin_loader.recompile()
  plugin_loader.cache_clear()
  pcall_packer_command "compile"
  if utils.is_file(compile_path) then
    Log:debug "generated packer_compiled.lua"
  end
end

function plugin_loader.load(configurations)
  Log:debug "loading plugins configuration"
  local packer_available, packer = pcall(require, "packer")
  if not packer_available then
    Log:warn "skipping loading plugins until Packer is installed"
    return
  end
  local status_ok, _ = xpcall(function()
    packer.startup(function(use)
      for _, plugins in ipairs(configurations) do
        for _, plugin in ipairs(plugins) do
          use(plugin)
        end
      end
    end)
  end, debug.traceback)
  if not status_ok then
    Log:warn "problems detected while loading plugins' configurations"
    Log:trace(debug.traceback())
  end
end

function plugin_loader.get_core_plugins()
  local list = {}
  local plugins = require "lvim.plugins"
  for _, item in pairs(plugins) do
    table.insert(list, item[1]:match "/(%S*)")
  end
  return list
end

function plugin_loader.sync_core_plugins()
  local core_plugins = plugin_loader.get_core_plugins()
  Log:trace(string.format("Syncing core plugins: [%q]", table.concat(core_plugins, ", ")))
  pcall_packer_command("sync", core_plugins)
end

function plugin_loader.install_core_plugins()
  local core_plugins = plugin_loader.get_core_plugins()
  local pack_root = utils.join_paths(get_runtime_dir(), "site", "pack", "packer")

  Log:trace(string.format("Syncing core plugins: [%q]", table.concat(core_plugins, ", ")))

  local missing_plugins = {}
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

    Log:debug("Syncing " .. plugin)
    pcall_packer_command("sync", plugin)
  end

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

return plugin_loader
