# CLASS SEAT SPINNER — Premium Responsive Upgrade

## Isi paket
- `index.html` — UI premium responsif untuk HP/tablet/laptop/PC, login, register user, role UI, manual/auto spin, undo/reset, denah, copy/download, maintenance, Developer Console, dan Secret Seating Control.
- `supabase/schema.sql` — schema awal + migrasi upgrade. Jalankan seluruh file ini di SQL Editor (aman untuk project yang sebelumnya sudah menjalankan versi awal; memakai IF NOT EXISTS/ALTER IF NOT EXISTS).
- `supabase/functions/create-account/index.ts` — Edge Function pembuatan akun oleh Admin/Developer.

## 1. Hubungkan Supabase
Project URL dan publishable key yang sebelumnya diberikan sudah dimasukkan ke `index.html`.
Publishable key memang boleh berada di browser. Jangan pernah memasukkan service_role key atau database password ke file HTML/GitHub.

## 2. Jalankan SQL upgrade
1. Supabase Dashboard → SQL Editor → New query.
2. Salin seluruh isi `supabase/schema.sql` dari file ini.
3. Klik Run.
4. Pastikan hasilnya `Success`.
SQL upgrade menambahkan `seat_no`, `seat_assignments`, maintenance settings, serta RPC yang memeriksa role Developer di database.

## 3. Aktifkan pendaftaran User
1. Supabase Dashboard → Authentication → Providers → Email.
2. Pastikan Email provider aktif.
3. Di Authentication → Settings, aktifkan sign-ups / allow new users.
4. Jika Confirm email aktif, user harus membuka email konfirmasi sebelum login.
Akun yang mendaftar sendiri selalu dibuat dengan role `user` oleh trigger database. User tidak dapat memilih role Admin/Developer dari form.

## 4. Deploy Edge Function create-account
Deploy folder `supabase/functions/create-account` sebagai function bernama `create-account`.
Dengan Supabase CLI:
```bash
supabase link --project-ref PROJECT_REF
supabase functions deploy create-account
```
Pastikan runtime Edge Function memiliki `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY`. Service role hanya disimpan sebagai secret server-side, jangan pernah di HTML atau GitHub.

## 5. Developer pertama
Jika Developer sudah dibuat sebelumnya, tidak perlu mengulang. Jika belum:
1. Authentication → Users → Add user.
2. Salin UID akun.
3. Jalankan:
```sql
update public.profiles
set role='developer', display_name='Developer'
where id='UUID_USER';
```

## 6. Fitur baru
- Register: user daftar sendiri, role selalu `user`.
- Maintenance: Developer mengatur pesan dan jadwal mulai/selesai. Maintenance otomatis aktif pada waktu mulai dan berakhir pada estimasi selesai; Developer tetap dapat masuk.
- Secret Seating Control: menu Developer tersembunyi dari role lain dan meminta verifikasi ulang password. Database RPC juga memeriksa role Developer. Penempatan kursi hanya bisa dibuat untuk siswa yang belum spin dan kursi yang belum terisi.
- Kursi khusus: `spin_no` menyimpan urutan spin, `seat_no` menyimpan kursi fisik. Ini memungkinkan siswa tertentu mendapat kursi yang ditentukan sementara siswa lain tetap acak.
- Auto spin: interval 2,4 detik; pause/resume/stop.
- Layout: CSS responsive; navigasi dan kartu menyesuaikan layar.

## 7. Deploy website
Upload isi folder project ke GitHub dengan `index.html` di root. GitHub Pages → Settings → Pages → Deploy from branch → main → /(root).

## Catatan
- Kapasitas maksimal 42 siswa/kursi.
- Secret Seating dapat menempatkan siswa di kursi mana pun yang masih kosong. Jika jumlah siswa lebih sedikit dari nomor kursi tujuan, denah akan memiliki beberapa kursi kosong sebelum kursi khusus tersebut; sistem tetap menyelesaikan undian tanpa memindahkan siswa dari kursi yang ditentukan.
- Jalankan SQL upgrade sebelum memakai fitur baru.
- Aktifkan Realtime untuk `students` dan `spin_history` jika publication belum aktif.
