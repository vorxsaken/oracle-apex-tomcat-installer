# Oracle APEX + ORDS + Tomcat — Unattended Installer

> **One-script, fully automated installation** of Oracle Database 23ai Free, Oracle APEX 24.2, ORDS, and Apache Tomcat on Oracle Linux 8.

---

## 📋 Overview

Script `unattended_apex_install.sh` mengotomasi seluruh proses instalasi stack Oracle APEX dari nol hingga siap digunakan, tanpa interaksi manual. Seluruh tahapan—mulai dari instalasi Oracle Database 23ai Free, APEX 24.2, ORDS, hingga deployment di Apache Tomcat—dilakukan secara sequential dan idempotent.

### Yang Di-Install

| Komponen | Versi / Detail |
|---|---|
| **Oracle Database** | 23ai Free |
| **Oracle APEX** | 24.2 |
| **ORDS** | 26.2.3 |
| **Java** | OpenJDK 17 |
| **Apache Tomcat** | 9.0.111 |

---

## ✅ Prasyarat

- **OS**: Oracle Linux 8 (x86_64)
- **Akses**: Root / `sudo`
- **Internet**: Diperlukan untuk mengunduh paket Oracle, APEX, dan Tomcat
- **RAM**: Minimal 4 GB (disarankan 8 GB+)
- **Disk**: Minimal 20 GB ruang kosong
- **dnf/yum**: Repositori Oracle Linux harus aktif

---

## ⚙️ Konfigurasi

Edit variabel di bagian atas file `unattended_apex_install.sh` sebelum menjalankan:

### Database

```bash
DB_PASSWORD="Tohnga123\$"      # Password SYS database
DB_PORT="1521"                  # Port listener
DB_SERVICE="FREEPDB1"           # Nama PDB service
ORACLE_SID="FREE"               # Oracle SID
ORACLE_HOME="/opt/oracle/product/23ai/dbhomeFree"
```

### APEX

```bash
APEX_DOWNLOAD_URL="https://download.oracle.com/otn_software/apex/apex_24.2_en.zip"
APEX_ADMIN_USER="ADMIN"
APEX_ADMIN_EMAIL="your.email@gmail.com"
APEX_ADMIN_PASSWORD="Tohnga123\$"
APEX_PUBLIC_USER_PASSWORD="admin123"
APEX_TABLESPACE="SYSAUX"
APEX_FILES_TABLESPACE="SYSAUX"
APEX_TEMP_TABLESPACE="TEMP"
APEX_IMAGES_PATH="/i/"
```

### ORDS

```bash
ORDS_VERSION="ords-26.2.3-3.el8"
ORDS_CONFIG_DIR="/etc/ords/config"
ORDS_STATIC_IMAGES="/opt/oracle/apex/images"
ORDS_CONTEXT_PATH="/ords"
ORDS_HTTP_PORT="8080"
ORDS_EXTERNAL_DOMAIN="https://your-own-domain.care"
```

### ORDS Connection Pool

```bash
ORDS_JDBC_INITIAL_LIMIT="15"
ORDS_JDBC_MAX_LIMIT="25"
ORDS_JDBC_MIN_LIMIT="15"
```

### Tomcat

```bash
TOMCAT_VERSION="9.0.111"
TOMCAT_INSTALL_DIR="/opt/tomcat"
TOMCAT_USER="tomcat"
TOMCAT_GROUP="tomcat"
```

> [!IMPORTANT]
> Ganti `APEX_ADMIN_EMAIL`, `APEX_ADMIN_PASSWORD`, `DB_PASSWORD`, dan `ORDS_EXTERNAL_DOMAIN` dengan nilai yang sesuai untuk environment Anda sebelum menjalankan script.

---

## 🚀 Cara Penggunaan

### 1. Clone atau Salin Script

```bash
git clone https://github.com/<username>/oracle-apex-tomcat-installer.git
cd oracle-apex-tomcat-installer
```

### 2. Edit Konfigurasi

```bash
nano unattended_apex_install.sh
# Sesuaikan variabel di bagian CONFIGURATION
```

### 3. Jalankan

```bash
chmod +x unattended_apex_install.sh
sudo ./unattended_apex_install.sh
```

> [!NOTE]
> Proses instalasi memakan waktu **30–60 menit** tergantung spesifikasi server dan kecepatan internet. Instalasi APEX sendiri membutuhkan sekitar 20–45 menit.

---

## 🔄 Tahapan Instalasi

Script menjalankan **5 tahap utama** secara berurutan:

```
┌─────────────────────────────────────────────┐
│  1/5  Install Oracle Database 23ai Free     │
│  2/5  Install Oracle APEX 24.2              │
│  3/5  Install & Configure ORDS              │
│  4/5  Install & Configure Apache Tomcat     │
│  5/5  Verification & Summary                │
└─────────────────────────────────────────────┘
```

### 1/5 — Oracle Database 23ai Free

- Install paket `oracle-database-preinstall-23ai`
- Install paket `oracle-database-free-23ai`
- Konfigurasi instance secara silent (menggunakan `ORACLE_PWD`)
- Set environment variables untuk user `oracle`
- Enable systemd service `oracle-free-23ai`
- Verifikasi database berjalan

### 2/5 — Oracle APEX

- Download dan ekstrak APEX dari URL yang dikonfigurasi
- Install APEX ke PDB (`FREEPDB1`) via `apexins.sql`
- Unlock dan set password `APEX_PUBLIC_USER`
- Buat akun admin APEX
- Konfigurasi APEX REST (`apex_rest_config_core.sql`)
- Salin static images ke lokasi permanen

### 3/5 — ORDS (Oracle REST Data Services)

- Install Java 17 OpenJDK
- Konfigurasi `sudoers` untuk user `oracle`
- Install ORDS dari repositori Oracle Linux
- Install schema ORDS ke database (non-interactive via `--password-stdin`)
- Konfigurasi ORDS settings:
  - Context path, HTTP port, static images path
  - Security headers (HTTPS proxy support)
  - JDBC connection pool tuning
- Fix MBEAN warning di `logging.properties`
- Generate `ords.war` untuk deployment Tomcat

### 4/5 — Apache Tomcat

- Download dan ekstrak Tomcat
- Buat user/group `tomcat` (nologin)
- Hapus default webapps (security hardening: `docs`, `examples`, `host-manager`)
- Deploy `ords.war` ke `webapps/`
- Deploy APEX static images sebagai context `/i/`
- Buat `setenv.sh` dengan konfigurasi ORDS dan JVM options
- Set ownership & permissions
- Buat systemd service `tomcat` (depends on `oracle-free-23ai`)
- Enable dan start service

### 5/5 — Verification

- Tunggu Tomcat startup (30 detik)
- Health check ORDS via HTTP
- Verifikasi status service Tomcat dan Oracle Database
- Cleanup work directory
- Tampilkan summary instalasi

---

## 📂 Struktur File Setelah Instalasi

```
/opt/oracle/product/23ai/dbhomeFree/   # Oracle Database Home
/opt/oracle/apex/images/               # APEX Static Images
/etc/ords/config/                      # ORDS Configuration
/opt/tomcat/                           # Apache Tomcat
├── bin/
│   ├── setenv.sh                      # ORDS env configuration
│   ├── startup.sh
│   └── shutdown.sh
├── webapps/
│   ├── ords.war                       # ORDS deployment
│   └── i/                             # APEX static images
├── logs/
│   └── catalina.out                   # Tomcat log
└── ...
/var/log/apex_install.log              # Installation log
```

---

## 🌐 Akses Setelah Instalasi

Setelah instalasi selesai, akses APEX melalui browser:

| Item | Nilai |
|---|---|
| **URL** | `http://<server-ip>:8080/ords/` |
| **Workspace** | `INTERNAL` |
| **Username** | `ADMIN` |
| **Password** | *(sesuai konfigurasi `APEX_ADMIN_PASSWORD`)* |

---

## 🔧 Systemd Services

Dua service systemd dibuat dan di-enable secara otomatis:

```bash
# Oracle Database
sudo systemctl status oracle-free-23ai
sudo systemctl start oracle-free-23ai
sudo systemctl stop oracle-free-23ai

# Tomcat (ORDS/APEX)
sudo systemctl status tomcat
sudo systemctl start tomcat
sudo systemctl stop tomcat
sudo systemctl restart tomcat
```

Tomcat service dikonfigurasi dengan:
- **Dependency**: `After=oracle-free-23ai.service` — Tomcat start setelah database
- **Auto-restart**: `Restart=on-failure` dengan delay 10 detik

---

## 📝 Log & Troubleshooting

### Log Files

| Log | Lokasi |
|---|---|
| **Installation log** | `/var/log/apex_install.log` |
| **Tomcat log** | `/opt/tomcat/logs/catalina.out` |
| **ORDS log** | `/home/oracle/logs/` |

### Troubleshooting Umum

**ORDS tidak merespons setelah instalasi:**
```bash
# Cek status Tomcat
sudo systemctl status tomcat

# Cek log Tomcat
sudo tail -100 /opt/tomcat/logs/catalina.out

# Cek ORDS manual
curl -I http://localhost:8080/ords/
```

**Database tidak berjalan:**
```bash
# Cek status database
sudo systemctl status oracle-free-23ai

# Restart database
sudo systemctl restart oracle-free-23ai
```

**Re-deploy ORDS WAR:**
```bash
sudo systemctl stop tomcat
sudo rm -rf /opt/tomcat/webapps/ords*
sudo cp /path/to/ords.war /opt/tomcat/webapps/
sudo chown tomcat:tomcat /opt/tomcat/webapps/ords.war
sudo systemctl start tomcat
```

---

## 🔒 Keamanan

Script ini menerapkan beberapa langkah hardening:

- ✅ Hapus default webapps Tomcat (`docs`, `examples`, `host-manager`)
- ✅ Tomcat berjalan sebagai user non-root dedicated (`tomcat`)
- ✅ Shell user tomcat di-set ke `/sbin/nologin`
- ✅ Permission direktori Tomcat dibatasi (`750`)
- ✅ Support HTTPS reverse proxy via header `X-Forwarded-Proto`
- ✅ Trusted origins dikonfigurasi untuk external domain

> [!WARNING]
> Untuk environment **production**, pastikan:
> - Ganti semua password default dengan password yang kuat
> - Gunakan reverse proxy (Nginx/Apache) dengan HTTPS/TLS di depan Tomcat
> - Batasi akses port 8080 hanya dari reverse proxy (firewall)
> - Hapus webapps `ROOT` dan `manager` jika tidak diperlukan

---

## 📄 Lisensi

Distribusi dan penggunaan script ini tunduk pada lisensi masing-masing komponen:
- **Oracle Database 23ai Free** — [Oracle Free Use Terms and Conditions](https://www.oracle.com/downloads/licenses/oracle-free-license.html)
- **Oracle APEX** — Termasuk dalam lisensi Oracle Database
- **ORDS** — Termasuk dalam lisensi Oracle Database
- **Apache Tomcat** — [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
