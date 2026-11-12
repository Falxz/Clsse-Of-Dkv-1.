CLASS SEAT SPINNER — PREMIUM CLASSROOM UPDATE

ISI PAKET
- index.html: versi website dengan penyegaran UI premium dan modul kelas tambahan.
- migration_classroom_premium.sql: migrasi database tambahan untuk modul baru.
- migration_permanent_qr.sql: migrasi QR permanen versi sebelumnya (disertakan sebagai arsip/referensi).

FITUR TAMBAHAN
1. Penghubung akun ↔ siswa dengan konfirmasi, pencegahan siswa terhubung ke dua akun, dan log perubahan.
2. Chat Kelas realtime, identitas pengirim dari akun login, batas panjang pesan dan pembatasan spam; Admin dapat moderasi.
3. Riwayat Aktivitas Admin yang hanya dapat dibaca sesuai hak akses dan tidak dapat diedit dari dashboard.
4. Jadwal Piket manual Senin–Jumat, bisa memilih beberapa siswa per hari dan menerbitkan jadwal mingguan.
5. Pengumuman dengan level Normal/Penting/Mendesak, pin, tanggal kedaluwarsa, dan arsip.
6. Pengaturan izin Admin oleh Developer; izin modul baru diperiksa juga oleh kebijakan database.
7. Struktur Organisasi kelas dengan penempatan siswa pada jabatan.
8. Checklist Kebersihan yang dapat dikirim siswa, foto bukti opsional, dan pemeriksaan Admin.
9. Kartu Identitas Digital siswa dengan QR identitas (bukan QR absensi) dan opsi cetak.
10. Galeri Kelas berbasis album dengan foto yang disimpan di bucket privat.

CARA UPDATE
1. Simpan backup database terlebih dahulu.
2. Pastikan migrasi V3 dan migrasi QR permanen sebelumnya sudah berhasil dijalankan.
3. Buka Supabase Dashboard → SQL Editor.
4. Jalankan isi file migration_classroom_premium.sql satu kali.
5. Ganti file index.html di project GitHub/Vercel dengan index.html dari paket ini.
6. Deploy ulang di Vercel, lalu refresh website.

PENTING
- Jangan jalankan ulang migration_v3.sql atau fungsi restore backup V3 untuk update ini.
- Jika migrasi QR permanen belum pernah dijalankan, jalankan migration_permanent_qr.sql terlebih dahulu setelah V3, lalu migration_classroom_premium.sql. Jika sudah pernah, jangan jalankan ulang hanya untuk update UI.
- Migrasi ini bersifat tambahan, tetapi tetap backup database sebelum menjalankan SQL.
- Jika SQL memberi pesan duplicate student links, berarti ada siswa yang saat ini tertaut ke lebih dari satu akun. Selesaikan melalui menu penghubung akun, lalu jalankan ulang bagian pembuatan unique index saja setelah memastikan tidak ada duplikasi.
- Foto checklist dan galeri menggunakan Storage bucket privat. Foto hanya dapat dibuka oleh pemilik laporan/anggota kelas sesuai kebijakan database.
- Kartu Digital memakai QR identitas siswa. QR tersebut tidak menggantikan QR absensi.
- Pengaturan izin Admin mengatur modul baru serta pengelolaan siswa, absensi, kalender, pengumuman, dan kotak saran. Akses spin/fitur Developer tetap mengikuti aturan role bawaan sistem.
- Tidak ada service_role key di browser. Jangan pernah menaruh service_role key di index.html.

CATATAN PENGGUNAAN
- Siswa perlu dihubungkan ke data siswa oleh Admin agar fitur yang memerlukan identitas siswa (absensi, kartu digital, checklist) bekerja.
- Struktur Organisasi dan Jadwal Piket diisi Admin secara manual.
- Persetujuan untuk mengunggah foto siswa/kegiatan harus diperhatikan oleh pihak kelas/sekolah.
