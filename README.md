# CLASS SEAT SPINNER — HTML + Supabase

## Isi paket
- `index.html` — aplikasi single-page, UI responsif, login, role UI, spin manual/otomatis, undo/reset, copy dan download PNG.
- `supabase/schema.sql` — tabel, RLS, trigger profil, dan RPC transaksi spin.
- `supabase/functions/create-account/index.ts` — Edge Function untuk membuat akun dengan aman.

## 1. Buat project Supabase
1. Buat project di https://supabase.com.
2. Buka **SQL Editor**, jalankan seluruh isi `supabase/schema.sql`.
3. Jika akun hanya boleh dibuat oleh staff, buka Authentication → Settings dan nonaktifkan public sign-ups. Pembuatan akun staf tetap berjalan melalui Edge Function.\n4. Buka **Project Settings → API** dan salin Project URL serta anon/public key.
5. Buka `index.html`, ganti:
   - `YOUR_SUPABASE_URL`
   - `YOUR_SUPABASE_ANON_KEY`
   Jangan pernah memasukkan `service_role` key ke HTML.

## 2. Buat akun Developer pertama
1. Supabase → Authentication → Users → Add user.
2. Buat user dengan email dan password Developer, lalu konfirmasi email.
3. Jalankan SQL berikut di SQL Editor dengan UUID user tersebut:
   ```sql
   update public.profiles
   set role='developer', display_name='Developer'
   where id='UUID_USER_DARI_AUTH_USERS';
   ```
4. Login melalui aplikasi. Developer dapat membuat Admin dan User.

## 3. Deploy fungsi pembuatan akun
Install Supabase CLI dan login, lalu dari folder project:
```bash
supabase link --project-ref PROJECT_REF
supabase functions deploy create-account
```
Atur secrets (jangan taruh service key di HTML):
```bash
supabase secrets set SUPABASE_URL=https://PROJECT_REF.supabase.co
supabase secrets set SUPABASE_ANON_KEY=YOUR_ANON_KEY
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
```
Jika project CLI Anda sudah menyediakan `SUPABASE_URL` dan `SUPABASE_SERVICE_ROLE_KEY` otomatis, cukup pastikan `SUPABASE_ANON_KEY` tersedia sebagai secret.

## 4. Aktifkan Realtime
Supabase Dashboard → Database → Replication / Publications → `supabase_realtime`.
Aktifkan tabel `students` dan `spin_history`. Aplikasi juga dapat dimuat ulang manual jika realtime belum diaktifkan.

## 5. Jalankan
Karena memakai Supabase CDN, buka `index.html` melalui web server lokal atau hosting statis (misalnya Netlify, Vercel static, GitHub Pages). Jangan mengandalkan `file://` untuk semua browser.
Contoh server lokal:
```bash
python -m http.server 8000
```
Lalu buka `http://localhost:8000`.

## Hak akses
- User: hanya SELECT data siswa dan hasil spin; dapat copy dan download denah.
- Admin: spin, auto spin, pause/resume/stop, kelola daftar siswa, undo/reset, membuat User.
- Developer: semua akses Admin + membuat akun Admin.
- RLS dan RPC memeriksa role di database. Edge Function memeriksa role lagi di server sebelum membuat akun.

## Catatan penting
- Spin dipilih secara acak di PostgreSQL (`ORDER BY random()`), dengan row lock agar dua permintaan bersamaan tidak mengambil urutan spin yang sama.
- Auto spin menunggu sekitar 2,4 detik antar hasil.
- Undo menghapus hasil terakhir, sehingga nama tersebut otomatis kembali tersedia.
- Reset hanya menghapus hasil spin, daftar nama tetap ada.
- Maksimal 42 siswa/kursi. Sistem ini memakai satu kelas bersama dalam satu project Supabase.
- Untuk produksi publik, batasi CORS Edge Function ke domain website Anda, aktifkan proteksi akun (MFA/rate limit), dan jangan bagikan kredensial.
