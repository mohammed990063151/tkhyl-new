# النشر عبر SSH + rsync (بدون git pull على السيرفر)

نفس أسلوب مشروع **eliteplussa-**: أي تحديث من جهازك يصل للسيرفر عبر **SSH + rsync** بدون تنفيذ `git pull` على Hostinger.

```
جهازك → git push main → GitHub Actions → rsync/SSH → domains/tkhyl-ai.com/public_html/
```

أو مباشرة من الجهاز:

```
.\deploy.ps1 -Test          # اختبار الاتصال فقط
.\deploy.ps1                # رفع الملفات من جهازك
```

---

## 1) إنشاء مفتاح النشر (مرة واحدة)

في PowerShell داخل مجلد المشروع:

```powershell
ssh-keygen -t ed25519 -C "tkhyl-github-deploy" -f github-deploy -N ""
```

يظهر:
- `github-deploy` ← المفتاح الخاص (Secrets / النشر المحلي)
- `github-deploy.pub` ← المفتاح العام (على السيرفر)

## 2) تثبيت المفتاح العام على Hostinger

من hPanel → SSH Access، ثم:

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
```

الصق محتوى `github-deploy.pub` في سطر جديد، احفظ، ثم:

```bash
chmod 600 ~/.ssh/authorized_keys
```

## 3) أسرار GitHub (Settings → Secrets and variables → Actions)

| الاسم | قيمة تخيل (نفس حساب eliteplussa) |
|--------|-------------------------------------|
| `SSH_HOST` | `147.93.92.221` |
| `SSH_USERNAME` | `u124894987` |
| `SSH_PRIVATE_KEY` | **كل** محتوى `github-deploy` |
| `SSH_PORT` | `65002` |
| `SSH_PATH` | `domains/tkhyl-ai.com/public_html/` |

## 4) النشر المحلي من جهازك (اختياري)

انسخ `.deploy.env.example` إلى `.deploy.env` وعبّئ القيم، ثم:

```powershell
.\deploy.ps1 -Test
.\deploy.ps1
```

`.env` على السيرفر **لا يُستبدل** أبداً.

## 5) أول نشر

1. تأكد من الأسرار الخمسة أو من `.deploy.env`
2. `git push origin main` أو Actions → **Deploy to Hostinger (SSH)** → Run workflow
3. افتح `https://tkhyl-ai.com/`

تغيير باسورد SSH لا يوقف النشر طالما مفتاح SSH مثبت.
