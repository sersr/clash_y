//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <clash_window_dll/clash_window_dll_plugin.h>
#include <sqlite3_windows_dll/sqlite3_windows_dll_plugin.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  ClashWindowDllPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ClashWindowDllPlugin"));
  Sqlite3WindowsDllPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("Sqlite3WindowsDllPlugin"));
}
