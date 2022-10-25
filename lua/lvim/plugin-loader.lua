local plugin_loader = {}

local Log = require "lvim.core.log"
local packer_tools = require "lvim.core.packer"

function plugin_loader.cache_clear()
  vim.cmd [[LuaCacheClear]]
  packer_tools.cache_clear()
end

function plugin_loader.recompile()
  plugin_loader.cache_clear()
  packer_tools.recompile()
end

function plugin_loader.reload(configurations)
  local packer_available, packer = pcall(require, "packer")
  if not packer_available then
    Log:warn "skipping reloading plugins since Packer is missing"
    return
  end
  packer.reset()
  _G.packer_plugins = _G.packer_plugins or {}
  for k, v in pairs(_G.packer_plugins) do
    if k ~= "packer.nvim" then
      _G.packer_plugins[v] = nil
    end
  end
  plugin_loader.load(configurations)

  plugin_loader.ensure_plugins()
end

function plugin_loader.load(configurations)
  Log:debug "loading plugins configuration"
  require("lvim.core.packer").setup()
  local packer_available, packer = pcall(require, "packer")
  if not packer_available then
    Log:warn "skipping loading plugins until Packer is installed"
    return
  end
  local status_ok, _ = xpcall(function()
    packer.init(lvim.builtin.packer.init_opts)
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
  packer_tools.get_core_plugins()
end

function plugin_loader.load_snapshot(snapshot_file)
  packer_tools.load_snapshot(snapshot_file)
end

function plugin_loader.sync_core_plugins()
  packer_tools.sync_core_plugins()
end

function plugin_loader.ensure_plugins()
  packer_tools.ensure_plugins()
end

return plugin_loader
