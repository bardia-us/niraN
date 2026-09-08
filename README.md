# niraN

niraN is a native Windows desktop client for Xray Core, built with Flutter and
a small Win32/C++ bridge. It keeps the local SOCKS and HTTP proxies independent
from Windows System Proxy. Native Xray TUN remains the active runtime path. A
checksum-pinned sing-box TUN frontend is staged behind an internal disabled
flag while its full lifecycle integration is completed and verified.

## Windows features

- Bundled, checksum-pinned Xray Core with clean process ownership
- Local SOCKS (`127.0.0.1:10808`) and HTTP (`127.0.0.1:10809`) proxies
- Independent Set/Clear Windows System Proxy controls
- Native Xray TUN mode (administrator privileges required)
- Real Delay through a temporary per-server proxy
- Routing, DNS, subscription updates, logs, themes, and Persian/English UI
- VLESS, VMess, Trojan, Shadowsocks, SOCKS, HTTP, and Hysteria2 profiles
- Semantic subscription reconciliation and persistent drag-to-reorder server list
- In-app Windows update downloads with pause/resume, size and SHA-256 checks
- Consent-gated server-side Block/Unblock enforcement before startup,
  subscription refresh, automatic refresh, and Connect
- System tray lifecycle: closing the window keeps Core running; Tray > Exit
  performs the final cleanup

## Development

The repository contains the Flutter client, Win32 bridge, reproducible Xray,
sing-box and Wintun provisioning scripts, and the optional device-registry
server files.
Machine-local inputs and generated artifacts are excluded from source control.
Runnable Windows bundles are published only through GitHub Releases.

The private subscription URL is not embedded in niraN. Deploy the shared
files in `server/apiniraN/` and configure the upstream only on the server as
`NIRAN_WINDOWS_SUBSCRIPTION_UPSTREAM`. Migration and old-client limitations are
documented in `server/apiniraN/DEPLOYMENT.md`.

Build a local x64 bundle with:

```powershell
flutter analyze
flutter test
flutter build windows --release
```

## License notices

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The release bundle ships
the Xray Core, sing-box and Wintun binary license files next to their binaries.
