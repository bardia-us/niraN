# niraN

niraN is a native Windows desktop client for Xray Core, built with Flutter and
a small Win32/C++ bridge. It keeps the local SOCKS and HTTP proxies independent
from Windows System Proxy and native Xray TUN.

## Windows features

- Bundled, checksum-pinned Xray Core with clean process ownership
- Local SOCKS (`127.0.0.1:10808`) and HTTP (`127.0.0.1:10809`) proxies
- Independent Set/Clear Windows System Proxy controls
- Native Xray TUN (administrator privileges required)
- Real Delay through a temporary per-server proxy
- Routing, DNS, subscription updates, logs, themes, and Persian/English UI
- System tray lifecycle: closing the window keeps Core running; Tray > Exit
  performs the final cleanup

## Build

Requirements: Flutter stable, MSVC v143 x64/x86 Build Tools, C++ CMake Tools
for Windows, and a Windows 10/11 SDK.

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

The complete runnable bundle is generated at:

```text
build/windows/x64/runner/Release/
```

Private build inputs can be placed in `windows/local.properties`; this file is
ignored by Git and must never be committed. Xray and Wintun are provisioned by
checksum-verified scripts during a clean build and are also excluded from Git.

## License notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The release bundle ships
the Xray Core and Wintun binary license files next to their binaries.
