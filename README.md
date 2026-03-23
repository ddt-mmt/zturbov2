# 🚀 ZTURBO_V2 - High Performance Data Transfer Engine (Optimized)

![Version](https://img.shields.io/badge/version-2.0.0%20(Optimized)-blue.svg?style=flat-square)
![Platform](https://img.shields.io/badge/platform-Linux-green.svg?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-orange.svg?style=flat-square)

**ZTURBO_V2** is the next-generation, high-performance evolution of the original ZTURBO toolkit. Re-engineered for maximum efficiency, it features a **RAM-Disk IPC architecture** and **Real-time Monitoring** specifically designed for massive data migrations (Cryo-EM data, Big Data) where every second and every I/O cycle counts.

---

## 🔥 Key Features (V2.0.0 Optimized & Enhanced)

### 1. ⚡ Zero I/O Lag Architecture
*   **🧠 RAM-Disk IPC**: Semua Inter-Process Communication (IPC), file status monitoring, dan cache UI browser kini disimpan di **RAM (`/dev/shm`)**.
*   **🚀 Zero Disk Overhead**: Monitoring transfer dan navigasi UI menggunakan 0% bandwidth Hardisk/SSD Anda, memastikan 100% kinerja penyimpanan didedikasikan untuk transfer data.

### 2. 📊 Ultra-Responsive Monitoring (ZMTURBO_V2)
*   **⏱️ 1-Second Real-time Refresh**: Progress bar dan kecepatan diperbarui setiap detik (mulus).
*   **📡 Dual-Format Bandwidth**: Menampilkan kecepatan jaringan dalam **MB/s (Ukuran File)** dan **Mbps/Gbps (Bandwidth Jaringan)**.
*   **🟢 Smooth Progress Bar**: Interpolasi presisi tinggi memastikan progress bar bergerak mulus.
*   **✨ Progress Bar Ultra-Andal**: Kini secara adaptif menggunakan output JSON dari `rsync` (jika didukung oleh `rsync` v3.1.0+ Anda) untuk keandalan dan akurasi yang lebih tinggi, tidak mudah rusak oleh perubahan format teks `rsync`.

### 3. 📜 Enterprise Reconciliation & History
*   **🕵️ Detailed Audit Logs**: Laporan mencakup Waktu Mulai, Waktu Selesai, Jalur Sumber, dan Jalur Tujuan untuk ketertelusuran penuh.
*   **📏 Human-Readable Reports**: Semua ukuran file dalam riwayat dikonversi otomatis (misal, `1.2TB` daripada `1200000000`).
*   **📂 Permanent Archive**: Meskipun data monitoring berada di RAM, riwayat transfer Anda disimpan permanen di disk (`~/.zturbo_v2/reports`).
*   **⚡ Verifikasi Pasca-Transfer Cepat**: Proses verifikasi file setelah transfer selesai jauh lebih cepat dengan memfokuskan pengecekan hanya pada item yang ditransfer, mengurangi beban I/O.

### 4. 🚀 Hybrid Parallel Engine
*   **🏎️ TURBO Mode**: Memanfaatkan `fpsync` dan multi-threaded `rsync` untuk menjenuhkan pipa jaringan 10G/40G/100G.
*   **🛡️ SAFE Mode**: Memprioritaskan stabilitas sistem dengan prioritas latar belakang `nice` dan `ionice`.
*   **🔒 Keamanan & Keandalan Ditingkatkan**: Penggunaan `eval` yang berpotensi tidak aman telah dihilangkan, diganti dengan metode eksekusi perintah yang lebih modern dan tangguh, meningkatkan keamanan kode.

### 5. 🖥️ UI Direktori Sangat Responsif (ZTURBO)
*   **💨 Navigasi Instan**: Penjelajahan direktori di `zturbo` tidak akan lagi "macet" atau lambat, bahkan di direktori besar, berkat sistem kalkulasi ukuran file di latar belakang yang cerdas, efisien, dan "sopan".
*   **🧠 Cache RAM-Disk**: Ukuran file dan folder dihitung secara asinkron dan di-cache di RAM-disk untuk pembaruan UI yang sangat cepat.

### 6. ⚙️ Manajemen Dependensi Cerdas
*   **💡 Umpan Balik Proaktif**: `zturbo` sekarang memberikan peringatan yang membantu jika versi `rsync` Anda tidak mendukung fitur optimal (seperti output JSON), memungkinkan Anda mengambil tindakan untuk pengalaman terbaik.

---

## 📦 Installation

1.  **Clone the Repository**
    ```bash
    git clone https://github.com/ddt-mmt/zturbov2.git
    cd zturbov2
    ```

2.  **Run the Installer**
    ```bash
    chmod +x install.sh
    sudo ./install.sh
    ```
    *Note: This version installs as `zturbo_v2` and `zmturbo_v2` to allow side-by-side usage with older versions.*

---

## 🚀 Getting Started

### 1. Launch Transfer Wizard
```bash
zturbo_v2
```

### 2. Monitor in Real-time
Open a new terminal session:
```bash
zmturbo_v2
```

### 3. View History
Inside `zmturbo_v2`, press **`H`** to open the enhanced history menu.

---

## 👨‍💻 Credits
*   **Original Concept**: [ddt-mmt](https://github.com/ddt-mmt)
*   **Optimized V2**: [ddt-mmt](https://github.com/ddt-mmt)

## 🤝 License
Licensed under the **MIT License**.