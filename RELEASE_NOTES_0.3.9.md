<!-- niran-build: 13 -->

## فارسی

> **فایل‌های این نسخه در ۱۵ اکتبر جایگزین شدند.** اگر فایل قبلی 0.3.9 را دارید، بهتر است Setup یا پرتابل جدید را از همین صفحه دوباره دانلود کنید؛ به‌خصوص اگر ثبت دستگاه یا اولین دریافت ساب مشکل داشته است. تشخیص شبکه و پیام‌های خطای API/ساب دقیق‌تر شده‌اند. شمارهٔ نسخه تغییر نکرده، پس ممکن است آپدیتر داخل برنامه آپدیت تازه‌ای نشان ندهد. نیازی به Reset یا حذف اطلاعات نیست.

نسخهٔ **0.3.9 — بیلد 13**؛ تغییرات نسبت به نسخهٔ عمومی 0.3.8:

- بازطراحی Liquid Glass با ظاهر Clear Lens، منوهای متحرک، دکمه‌های Clay هماهنگ، hover خواناتر و اصلاح لبه‌ها و فوکوس منوها در تم روشن و تاریک.
- نوار شناور با جای‌گذاری چپ، راست یا پایین و پیش‌نمایش قبل از ذخیره؛ بهبود فاصله‌ها و چیدمان Home، هدرها و صفحهٔ اطلاعات کانفیگ. هدر Servers دیگر لمس را به کانفیگ پشتش منتقل نمی‌کند.
- حالت **Performance & recovery** با منوهای کاملاً مات و حذف گلس؛ تغییر با تأیید و اجرای مجدد. نمایش لودینگ و بهینه‌سازی شیدر هندسه، زمان شروع حالت عادی را در تست محلی کاهش داده‌اند؛ سرعت همچنان به سیستم بستگی دارد و Performance سریع‌تر است.
- کارهای خودکار شروع، از جمله بررسی API، آپدیت و راه‌اندازی خودکار اتصال، پس از آماده‌شدن واقعی Home انجام می‌شوند. درخواست‌های بررسی دسترسی و آپدیت مهلت کلی ۱۰ ثانیه دارند؛ مسیر ثبت‌نام اولیه و محدودیت واقعی دسترسی حفظ شده‌اند.
- اصلاح ارسال پین گواهی TLS با `pcs` / `pinSHA256` و نام‌های بررسی گواهی به Xray؛ ورودی نامعتبر یا متناقض و ترکیب ناسازگار با هسته، به‌جای نادیده‌گرفتن رد می‌شود. تنظیم ECH از جمله `udp://` و گزینه‌های Fingerprint/ALPN نیز بهبود یافته‌اند؛ REALITY گزینهٔ unsafe ندارد.
- انتخاب مسیر شبکهٔ محلی در Routing، بهبود نمایش ترافیک کانفیگ و مجموع روزانه/ماهانه، پیام‌های شناور مدرن‌تر و اصلاح مدیریت پنجره، خروج و اجرای مجدد. آپدیت موفق ساب، Fingerprint ویرایش‌شده را به مقدار اصلی ساب برمی‌گرداند.

**دانلود:** Setup برای نصب/آپدیت با حفظ اطلاعات؛ Portable ZIP برای اجرا بدون نصب، پس از استخراج کامل پوشه. هر دو **Windows x64** و از یک بیلد هستند. برای آپدیت، ابتدا از Tray → Exit خارج شوید؛ نیازی به Reset یا حذف داده نیست. آمار ترافیک، اندازه‌گیری خود برنامه است نه صورتحساب سرویس‌دهنده. این انتشار ادعای رفع همهٔ مشکلات درایور یا پنجرهٔ سیاه روی تمام سیستم‌ها را ندارد.

## English

> **Release files refreshed on October 15.** If you downloaded the earlier 0.3.9 files, we recommend downloading the refreshed Setup or portable package here, especially if device registration or the first subscription refresh failed. This revision improves network diagnostics and API/subscription error reporting. The version number is unchanged, so the in-app updater may not offer it automatically. No reset or data deletion is required.

**0.3.9 — build 13**, compared with public release 0.3.8:

- Reworked Clear Lens Liquid Glass, animated menus, matching Clay controls, clearer hover feedback and refined menu edges/focus in light and dark themes.
- Floating left/right/bottom navigation with live placement preview; improved Home spacing, headers and profile details. The Servers header now blocks clicks from reaching profiles underneath.
- Added restart-applied **Performance & recovery** mode with opaque menus and no Liquid Glass. Startup loading feedback and geometry-shader optimization reduced normal-mode startup in local testing; timings remain system-dependent and Performance starts faster.
- Automatic startup work, including API/update checks and connection auto-start, waits for the usable Home frame. Access/update HTTP requests now have a 10-second overall deadline; initial registration and actual access restrictions remain enforced.
- Fixed Xray forwarding of TLS certificate pins (`pcs` / `pinSHA256`) and verification names; malformed/conflicting values and incompatible core combinations are rejected instead of silently ignored. Improved ECH inputs including `udp://` and Fingerprint/ALPN choices; REALITY excludes unsafe.
- Configurable local-network routing, improved per-profile/daily/monthly traffic reporting, modern floating messages, and window/exit/restart lifecycle refinements. Successful subscription refresh restores the subscription's original Fingerprint after a manual edit.

**Downloads:** Setup installs/updates while retaining data; Portable ZIP runs after extracting the complete folder. Both are **Windows x64** from the same build. Quit through Tray → Exit before updating; no reset or data deletion is needed. Traffic counters are app measurements, not provider billing. This release does not claim to resolve every driver-specific black-window problem.
