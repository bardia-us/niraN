# Third-party notices

## Xray-core

- Project: <https://github.com/XTLS/Xray-core>
- Bundled version: `v26.7.28`
- License: Mozilla Public License 2.0 (MPL-2.0)
- Provisioning: `tool/download_xray.ps1` downloads the official Windows x64
  archive and verifies its pinned SHA-256 before use.

The complete Xray license is distributed as `xray/LICENSE` in the Windows
bundle.

## Twemoji country flags

- Project: <https://github.com/jdecked/twemoji>
- Asset version: `17.0.3`
- Graphics license: Creative Commons Attribution 4.0 (CC BY 4.0)

Only Unicode country-flag PNG assets are bundled. The graphics license is
distributed as `assets/flags/twemoji/LICENSE-GRAPHICS` in the Flutter asset
bundle. No platform-vendor emoji artwork is included.

## Wintun

- Project: <https://www.wintun.net/>
- Bundled version: `0.14.1` (amd64)
- Distribution terms: Wintun Prebuilt Binaries License
- Provisioning: `tool/download_wintun.ps1` downloads the official archive and
  verifies its pinned SHA-256 before use.

The complete prebuilt-binary license is distributed as
`xray/WINTUN_LICENSE.txt` in the Windows bundle.

## Flutter and Dart packages

Flutter and Dart dependencies retain their respective licenses. Flutter emits
their generated notices in `data/flutter_assets/NOTICES.Z` in every release
bundle.
