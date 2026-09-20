## English

### New

- Added Windows forced-update policy controlled independently by the shared niraN/niraNG backend.
- Added optional Windows update recovery with persisted, verified installers and portable packages.
- Added bilingual What's New notes after a real upgrade, with rendered Markdown and one unified scroll area.
- Added a Windows-compatible Liquid Glass treatment with live blur, color transmission, specular edges and an opaque performance-mode fallback.
- Added XUDP concurrency and UDP/443 handling controls to Mux, matching niraNG, and adopted the simple `nirang-mark` application logo.
- Added the mandatory Telegram notice after the first successful connected ping; clicking Join completes it locally without membership verification.

### Fixed

- Ping actions can no longer remain permanently busy after errors, timeouts, cancellation, or a missing completion event.
- Subscription imports now preserve connection-identical configurations when their names differ, while exact duplicates are still removed.
- Temporary network failures no longer cause a false forced-update lock.
- Raw platform, network, hostname, and subscription errors are converted to user-friendly messages.
- Reset Settings is now clearly styled as a destructive action.

### Compatibility

- Xray remains the primary core.
- TUN remains sing-box → Xray.
- System Proxy, Tray, TUN, and server Drag/Reorder behavior are unchanged.

## فارسی

### قابلیت‌های جدید

- سیاست آپدیت اجباری ویندوز با کنترل مستقل از طریق Backend مشترک niraN و niraNG اضافه شد.
- بازیابی آپدیتر ویندوز اضافه شد؛ فایل تأییدشده پس از بستن یا اجرای دوباره برنامه برای نصب مجدد حفظ می‌شود.
- پنجره دوزبانه «چه چیزهایی جدید است؟» فقط پس از ارتقای واقعی نمایش داده می‌شود و Markdown صحیح با یک اسکرول یکپارچه دارد.
- Liquid Glass سازگار با ویندوز با بلور زنده، انتقال رنگ، لبه‌های درخشان و حالت مات مخصوص Performance Mode اضافه شد.
- دو تنظیم هم‌زمانی XUDP و رفتار UDP/443 برای Mux مانند niraNG اضافه شد و لوگوی ساده `nirang-mark` جایگزین لوگوی پرنور داخل برنامه شد.
- پیام اجباری تلگرام بعد از نخستین اتصال و پینگ موفق اضافه شد؛ کلیک روی عضویت بدون بررسی واقعی عضویت، آن را تکمیل می‌کند.

### باگ‌های رفع‌شده

- وضعیت Ping بعد از خطا، timeout، لغو یا نرسیدن completion event دیگر برای همیشه فعال نمی‌ماند.
- کانفیگ‌های اتصال یکسان با نام متفاوت هنگام Import حفظ می‌شوند و فقط duplicate کاملاً یکسان حذف می‌شود.
- خطای موقت اینترنت باعث قفل اشتباه Forced Update نمی‌شود.
- خطاهای خام Platform، شبکه، hostname و Subscription به پیام‌های قابل‌فهم برای کاربر تبدیل شدند.
- دکمه بازنشانی تنظیمات اکنون به‌وضوح به‌عنوان عملیات حساس با رنگ قرمز نمایش داده می‌شود.

### سازگاری

- Xray همچنان Core اصلی است.
- مسیر TUN همچنان sing-box → Xray است.
- رفتار System Proxy، Tray، TUN و Drag/Reorder سرورها تغییر نکرده است.
