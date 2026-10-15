# niraN · Windows

A focused Windows proxy client with Xray, optional sing-box, and a Clear Lens
interface. Part of the **nira** family, alongside [niraNG for Android](https://github.com/bardia-us/niraNG).

[Download latest release](https://github.com/bardia-us/niraN/releases/latest) ·
[Report an issue](https://github.com/bardia-us/niraN/issues)

## فارسی

نیرا ویندوز؛ مدیریت کانفیگ و ساب، اتصال با Xray و رابط شیشه‌ای با تم روشن و تاریک.

### نصب و استفاده

- **Setup** برای نصب یا آپدیت با حفظ تنظیمات و اطلاعات موجود.
- **Portable ZIP** بدون نصب؛ کل پوشه را استخراج کنید و `niraN.exe` را اجرا کنید. فایل اجرایی را از DLLها و پوشهٔ `data` جدا نکنید.
- فایل‌های این انتشار برای **Windows x64** هستند؛ فایل APK مربوط به [نسخهٔ اندروید](https://github.com/bardia-us/niraNG/releases/latest) است.
- برای عبور ترافیک برنامه‌های سازگار از پراکسی سیستم، **Set System Proxy** را بزنید؛ **Clear System Proxy** آن را برمی‌دارد. **TUN** مسیر جداگانه‌ای برای ترافیک سیستم دارد و ممکن است دسترسی Administrator بخواهد.
- ضربدر پنجره برنامه را به Tray می‌فرستد؛ برای خروج کامل از آیکن کنار ساعت، **Exit** را بزنید.

### امکانات

- مدیریت ساب و کانفیگ، پینگ واقعی، مرتب‌سازی، لاگ قابل کپی و رابط فارسی/انگلیسی.
- هستهٔ Xray و انتخاب sing-box برای پروتکل‌ها و تنظیمات سازگار؛ SOCKS و HTTP محلی مستقل از System Proxy.
- تنظیمات DNS و Routing، بای‌پس ایران و انتخاب مسیر شبکهٔ محلی.
- تنظیمات TLS/REALITY، انتخاب Fingerprint و ALPN و پشتیبانی Xray از ECH و پین گواهی سازگار.
- چیدمان قابل تغییر Home و نوار شناور قابل قرارگیری در چپ، راست یا پایین.
- نمایش مصرف اندازه‌گیری‌شدهٔ کانفیگ و مجموع روزانه/ماهانه؛ این آمار، مصرف اعلامی سرویس‌دهنده یا کل اینترنت ویندوز نیست.
- **Performance & recovery**: حالت سبک با منوهای مات و بدون Liquid Glass؛ تغییر آن با تأیید و اجرای مجدد اعمال می‌شود. برای سیستم‌هایی که شروع حالت عادی کند است، این گزینه پیشنهاد می‌شود.
- آپدیت داخل برنامه با بررسی اندازه و SHA-256؛ حفاظت DPAPI برای اطلاعات دسترسی و کش ساب.

## English

### Get started

- **Setup:** install or update while retaining existing settings and data.
- **Portable ZIP:** extract the entire folder and run `niraN.exe`; keep its DLLs and `data` folder together.
- Release packages target **Windows x64**. Android users should use [niraNG](https://github.com/bardia-us/niraNG/releases/latest).
- **Set/Clear System Proxy** controls the Windows proxy setting. **TUN** is a separate system-traffic option and may require Administrator privileges.
- Closing the window minimizes to the system tray; use **Tray → Exit** to quit completely.

### Highlights

- Subscriptions, real-delay tests, server ordering, selectable logs, Persian/English UI and light/dark themes.
- Bundled Xray, optional sing-box for compatible profiles, and independent local SOCKS/HTTP proxies.
- DNS and routing controls, Iran bypass and configurable local-network routing.
- TLS/REALITY profile controls, Fingerprint/ALPN choices, Xray ECH and compatible certificate pinning. Unsupported core/parameter combinations are rejected rather than silently dropping security constraints.
- Customizable Home layout, floating left/right/bottom navigation and measured per-profile, daily and monthly traffic totals.
- Clear Lens glass with animated menus, plus a restart-applied **Performance & recovery** mode with opaque lightweight menus and no Liquid Glass.
- Verified in-app update downloads and DPAPI-protected access credentials/subscription cache.

Normal-mode startup still depends on GPU/driver shader preparation; Performance
mode is the faster alternative. Traffic counters reflect traffic measured by
niraN, not provider billing or all traffic on your computer. Protocol support
depends on the selected core; Hysteria2 requires a compatible sing-box path.

## Security & notices

Download only from this repository's [Releases](https://github.com/bardia-us/niraN/releases)
and compare the provided `SHA256SUMS.txt` when needed. Never share subscription
links, access credentials or private configuration details in public issues.

See [SECURITY.md](SECURITY.md) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
Bundled components retain their respective licenses. The local Clear Lens
implementation builds on `liquid_glass_widgets`; optical reference work also
credits `Liquid-Glass-Android` in the shipped notices.
