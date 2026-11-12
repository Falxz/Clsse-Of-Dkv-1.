# CLASS SEAT SPINNER V3 — Classroom Management + QR Attendance

V3 melanjutkan project V2 yang sudah ada. Ini **bukan website terpisah**: spin wheel, seating plan, Developer Console, dan modul kelas berada dalam satu website dan satu project Supabase.

## Fitur V3

### Fitur lama yang dipertahankan
- Spin wheel manual dan auto, pause/resume/stop, undo/reset.
- Denah 21 meja × 2 kursi, secret seating.
- Role User/Admin/Developer.
- Activity Log, snapshot seating, maintenance scheduler.
- System Health, User Management, Global Settings.
- Backup & Restore JSON (V3 sekarang mencakup data kelas baru juga).

### Modul kelas baru
1. **QR Attendance** — Admin membuat QR yang berlaku 1–60 menit; siswa login lalu scan lewat kamera HP atau memasukkan token; satu akun hanya dapat absen sekali per sesi.
2. **Input manual Admin** — status Hadir, Izin, Sakit, Alpa; tombol menandai siswa yang belum tercatat sebagai Alpa tersedia setelah sesi QR ditutup.
3. **Student-account linking** — Admin menghubungkan akun login dengan satu record siswa. Ini wajib agar scan QR bisa dikaitkan ke siswa yang benar.
4. **Student Dashboard** — status kehadiran, tempat duduk, jadwal mendatang, pengumuman.
5. **Student Profile** — nomor siswa, foto URL, catatan profil, posisi duduk, dan riwayat kehadiran.
6. **Class Calendar** — Admin menambah/menghapus kegiatan; semua akun terautentikasi dapat melihat.
7. **Pengumuman Kelas** — Admin menerbitkan dan menghapus pengumuman normal/penting.
8. **Kotak Saran** — siswa mengirim saran; dapat anonim bagi siswa lain; Admin membalas dan mengubah status.
9. **Export CSV** — Admin mengekspor rekap sesi absensi.

## Cara memasang ke project V2 yang sudah berjalan

**PENTING:** Buat backup dari website/Supabase terlebih dahulu. Jangan menghapus project atau tabel lama.

### 1. Jalankan migration V3
1. Buka Supabase Dashboard → SQL Editor → New Query.
2. Buka file `supabase/migration_v3.sql` dari paket ini.
3. Salin seluruh isi file, tempel ke SQL Editor, lalu tekan Run.
4. Pastikan hasilnya `Success. No rows returned` atau tidak ada error.

Migration ini harus dijalankan **setelah** `migration_v2.sql` dan schema premium V2 yang sudah dipakai. Jangan menjalankan ulang `schema.sql` atau `migration_v2.sql` jika keduanya sudah berhasil dipasang.

Migration V3 bersifat tambahan. Migration ini menambah tabel absensi, kalender, pengumuman, saran, kolom profil siswa, RPC QR, dan izin baca Developer untuk `seat_assignments` agar backup dapat membaca data tersebut.

### 2. Ganti website
1. Ganti `index.html` website yang saat ini dipakai dengan `index.html` dari folder V3.
2. Pertahankan konfigurasi URL dan Publishable Key project Supabase kamu. File ini membawa konfigurasi dari project V2 yang diunggah; periksa kembali sebelum publish.
3. Commit/push ke GitHub atau upload ke hosting yang kamu gunakan.

### 3. Edge Functions
Edge Functions `create-account` dan `manage-user` dari V2 **tidak berubah**. Jika dua function itu sudah berhasil dideploy, tidak perlu deploy ulang untuk V3.

Pastikan secret bawaan Supabase tetap tersedia: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, dan `SUPABASE_SERVICE_ROLE_KEY`. Service role key hanya boleh berada di server/Edge Function, jangan di HTML atau GitHub.

### 4. Setup akun siswa untuk QR
1. Pastikan setiap siswa yang akan scan memiliki akun login User.
2. Login sebagai Admin.
3. Buka **Absensi QR → Hubungkan akun dengan siswa**.
4. Pilih akun login dan nama siswa yang sesuai, lalu simpan.
5. Ulangi untuk setiap siswa. Satu record siswa hanya boleh dihubungkan ke satu akun.

### 5. Cara menggunakan absensi
1. Admin membuka **Absensi QR**, memasukkan nama sesi dan masa berlaku QR, lalu tekan **Buat QR Absensi**.
2. Tampilkan QR di layar Admin.
3. Siswa login di HP masing-masing, buka menu Absensi QR, tekan **Buka Kamera**, lalu scan QR yang ditampilkan.
4. Jika kamera tidak tersedia, siswa dapat memasukkan token yang dibaca dari QR menggunakan aplikasi pembaca QR tepercaya.
5. Admin memilih sesi di bagian Rekap dan input manual untuk melihat status.
6. Setelah waktu absensi selesai, Admin tutup sesi. Admin dapat memperbaiki status manual atau menandai yang belum tercatat sebagai Alpa.
7. Rekap dapat diunduh sebagai CSV.

**Catatan keamanan:** QR memiliki masa berlaku dan token yang disimpan sebagai hash di database. Setiap akun hanya bisa tercatat sekali pada sesi yang sama. Namun QR tetap dapat difoto/dibagikan selama masa aktif; sistem ini tidak membuktikan lokasi fisik siswa.

## Catatan dan batasan
- Pemindaian kamera membutuhkan HTTPS dan izin kamera browser. Di Android, gunakan Chrome dan izinkan akses kamera.
- Library QR/scanner dimuat dari CDN, sehingga koneksi internet diperlukan.
- Akun siswa yang belum dihubungkan Admin tidak dapat menyelesaikan scan QR.
- Sesi QR yang dipulihkan dari backup akan berstatus tertutup; token lama tidak dapat dipakai.
- Backup V3 mencakup siswa, spin history, secret seating, sesi/rekap absensi, kalender, pengumuman, saran, dan hubungan akun-siswa. Backup tidak mencakup password akun atau secret Supabase.
- Restore V3 mengganti data kelas dan modul kelas yang ada saat ini. Akun login dan pengaturan global tetap dipertahankan.
- File migration belum dijalankan ke Supabase secara otomatis dan website belum dipublish otomatis. Lakukan langkah di atas secara manual.

## Pemeriksaan sebelum dipakai
- Login satu akun User, satu Admin, dan satu Developer.
- Coba scan QR menggunakan dua HP (satu menampilkan QR, satu memindai).
- Pastikan akun yang belum ditautkan mendapat pesan untuk menghubungi Admin.
- Pastikan satu siswa tidak bisa absen dua kali pada sesi yang sama.
- Uji input manual, export CSV, kalender, pengumuman, dan kotak saran.
- Buat backup V3 dan uji restore hanya setelah backup tambahan dibuat.
