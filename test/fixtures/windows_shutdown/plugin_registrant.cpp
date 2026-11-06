#include "flutter/generated_plugin_registrant.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>

#include <chrono>
#include <fstream>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  // Keep a failing probe from showing a crash dialog; its exit code still fails.
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  auto registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          registry->GetRegistrarForPlugin("ShutdownProbe"));
  const auto view = registrar->GetView()->GetNativeWindow();
  flutter::MethodChannel<> channel(registrar->messenger(), "shutdown_probe",
                                  &flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler(
      [view](const auto& call, auto result) {
        const auto method = call.method_name();
        if (method != "quit" && method != "close") {
          result->NotImplemented();
          return;
        }
        const auto requested = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
        std::ofstream("shutdown-requested.txt") << requested;
        result->Success();
        if (method == "quit") {
          // Exactly the Windows action used by window_manager.destroy().
          PostQuitMessage(0);
        } else {
          // Plugins register before SetChildContent reparents the Flutter view.
          PostMessage(GetAncestor(view, GA_ROOT), WM_CLOSE, 0, 0);
        }
      });
}
