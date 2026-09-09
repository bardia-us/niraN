# Security notes

- Subscription profiles and device-access credentials are encrypted at rest
  with Windows DPAPI in the current-user scope. Legacy plaintext files migrate
  automatically. DPAPI protects copied files and other Windows accounts; it
  cannot protect data from malware already executing as the same user.
- Update downloads require HTTPS, a trusted GitHub asset host, an exact size,
  and GitHub's SHA-256 digest. Every redirect is revalidated and the archive is
  hashed again immediately before installation. This does not replace an
  independent offline publisher signature if the GitHub account itself is
  compromised.
- TUN `strict_route` provides active-session route and IPv6 leak protection.
  niraN does not claim a persistent crash-surviving Windows kill switch: a
  correct implementation needs a separately installed and audited privileged
  service or WFP component. Global firewall or adapter hacks are intentionally
  not used.
- TUN currently requires elevation, so its child Core processes inherit the
  elevated token. A least-privilege service split is a future architectural
  change, not something simulated by the UI.
- The installer cleanup restores only a System Proxy lease owned by niraN and
  removes niraN's per-user auto-start/window state. Portable users should exit
  niraN from the tray before deleting its folder.
