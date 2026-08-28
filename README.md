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

## Development

The repository contains the Flutter client, Win32 bridge, reproducible Xray and
Wintun provisioning scripts, and the optional device-registry server files.
Machine-local inputs and generated artifacts are excluded from source control.
Runnable Windows bundles are published only through GitHub Releases.

## License notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The release bundle ships
the Xray Core and Wintun binary license files next to their binaries.
