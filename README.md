# CLASS SEAT SPINNER — UPGRADE V2

Paket ini menambahkan fitur aplikasi dan panel Developer ke project Class Seat Spinner yang sudah ada. Desain dark premium dan layout mobile dari `index.html` sebelumnya dipertahankan.

## Fitur tambahan yang tersedia

### Fitur utama
1. Dashboard statistik (memakai statistik yang sudah ada dan tetap diperbarui dari data Supabase).
2. Activity Log dengan audit otomatis untuk perubahan daftar siswa dan hasil spin.
3. Denah 21 meja × 2 kursi tetap tersedia, dengan ringkasan kursi.
4. Pengaturan warna aksen dan nama aplikasi melalui Global Settings.
5. Export PDF melalui dialog cetak browser (pilih **Save as PDF**).
6. Notification Center dari aktivitas terbaru.
7. Pencarian siswa pada daftar siswa.
8. Saved Seating Versions / snapshot dan pemulihan versi oleh Developer.
9. Pengaturan durasi animasi dan efek suara spin.
10. Pengamanan akses role di database dan Edge Function.

### Developer Console
- System Health: tes query database dan status subscribe Realtime.
- Backup & Restore: unduh JSON backup dan pulihkan backup. Restore mengganti data siswa, hasil spin, dan secret seating saat ini.
- User Management: ubah role, nonaktifkan, dan aktifkan akun melalui Edge Function `manage-user`.
- Global Settings: nama aplikasi, warna aksen, durasi spin, dan suara.
- Maintenance Scheduler: memakai fitur maintenance start/end yang sudah tersedia pada schema premium. Jadwalkan waktu mulai dan selesai di panel Maintenance Mode.

## PENTING: cara memasang pada project yang sudah berjalan

1. **Backup dulu** dari Supabase sebelum mengubah database. Jangan hapus tabel atau project lama.
2. Buka Supabase → SQL Editor → New Query.
3. Buka `supabase/migration_v2.sql`, salin seluruh isinya, lalu Run. Migration ini bersifat tambahan dan tidak menghapus data existing.
4. Ganti file website di project GitHub/Vercel dengan `index.html` dari paket ini. Pertahankan URL dan Publishable Key Supabase project milikmu. File yang disertakan sudah memakai konfigurasi project yang ada di percakapan ini; cek lagi sebelum deploy.
5. Deploy Edge Functions dari root project Supabase:

```bash
supabase functions deploy create-account
supabase functions deploy manage-user
```

6. Pastikan Edge Functions memiliki secrets bawaan Supabase: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY`. **Service Role Key hanya boleh berada di server/Edge Function, jangan pernah ditaruh di `index.html`, GitHub, atau file publik.**
7. Push ke GitHub dan tunggu deployment Vercel selesai.
8. Login sebagai Developer. Buka Developer Console, jalankan System Health, lalu tes fitur satu per satu.

## Instalasi baru
Untuk project baru, jalankan `supabase/schema.sql` terlebih dahulu, kemudian `supabase/migration_v2.sql`. File `schema.sql` sudah memperbaiki masalah policy profiles yang sebelumnya dapat menyebabkan error `policy already exists` saat SQL dijalankan ulang.

## Catatan keamanan dan batasan
- Public registration tetap membuat akun dengan role `user`.
- Hanya Developer yang dapat mengubah role, menonaktifkan akun, mengubah Global Settings, dan restore backup.
- Admin dapat spin, mengelola daftar siswa, dan membuat akun User sesuai izin yang sudah ada.
- User hanya melihat data dan tidak mendapat kontrol spin.
- Backup JSON berisi nama siswa dan riwayat tempat duduk. Simpan file backup secara pribadi.
- Export PDF menggunakan fitur Print browser; pada Android, pilih opsi simpan sebagai PDF jika tersedia.
- Migration belum dieksekusi ke Supabase dan Edge Functions belum dideploy otomatis. Jalankan langkah di atas sendiri melalui dashboard/CLI.
