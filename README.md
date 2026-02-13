# Analisis Dampak SPBU Nelayan (SPBUN)

Repositori ini berisi pipeline analisis lengkap untuk mengevaluasi dampak **SPBU Nelayan (SPBUN)** terhadap kesejahteraan desa dan rumah tangga, menggunakan data **PODES** (Potensi Desa) dan **SUSENAS**.

> **Catatan Penting**: Mohon semua path `"..."` pada file `.do` dan notebook diganti menyesuaikan path anda sebelum menjalankan kode.

---

## Repositori Terkait: PSE_Pertamina2 (Kalkulator Margin & Evaluator Dampak Interaktif)

Terdapat repositori kedua yang memuat **kalkulator margin** dan **evaluator dampak interaktif** berbasis data yang dihitung dan dievaluasi di repositori ini:

**[https://github.com/Mrhemm/PSE_Pertamina2.git](https://github.com/Mrhemm/PSE_Pertamina2.git)**

Repositori tersebut bersifat **privat** dan hanya dapat diakses oleh pihak **Pertamina**. Untuk mendapatkan akses, silakan hubungi **PSE (Pusat Studi Ekonomi)** melalui kontak resmi.

---

## Struktur File

### File Stata (.do)

| File | Deskripsi |
|---|---|
| `SPBUN-Analysis1.do` | Analisis baseline #1: indikasi awal/prognostik RQ dasar (PODES + SUSENAS) |
| `SPBUN-Analysis2.do` | Analisis #2: PCA outcomes, robustness grid, nonparametric screening |
| `SPBUN-Analysis3.do` | Analisis #3: model probabilistik (targeting/utilisasi), churdle grid, OLS grid |
| `SPBUN-Analysis4.do` | Analisis #4: IV-2SLS suite dengan exposure `A_v_log` |
| `SPBUN-Analysis4A.do` | Analisis #4: data generation full sample (podes + exposure + PCA + IV) |
| `SPBUN-Analysis4B.do` | Analisis #4: data generation pesisir sample |
| `SPBUN-Analysis5A.do` | Analisis #5: IV-2SLS suite dengan exposure `Ker5_w1` |
| `SPBUN-Analysis5B.do` | Analisis #5: IV-2SLS suite dengan exposure `Ker10_w1` |
| `MDI-Check.do` | Location match, nearest-village poverty attach, P(tidak layak \| MDI, poverty) |

### Notebook Python (.ipynb)

| File | Deskripsi |
|---|---|
| `FULL_Cleaning.ipynb` | Pipeline pembersihan dan persiapan data |
| `FULL_Exploratory.ipynb` | Analisis eksplorasi data (EDA) |
| `FULL_Modelling.ipynb` | Pipeline model spasial M4–M7 (SLX, SDM, SEM) |

---

## Cara Memulai

### 1. Sesuaikan Path

Semua file `.do` memiliki bagian **A. PATHS** di awal file. Ganti semua `"..."` dengan path yang sesuai di komputer Anda.

Contoh pada file yang menggunakan `global ROOT`:
```stata
* Mohon '...' diganti menyesuaikan path anda
global ROOT "/path/ke/folder/PSE_Pertamina"
```

Contoh pada file yang menggunakan path individual:
```stata
* Mohon '...' diganti menyesuaikan path anda
global sus41 "/path/ke/susenas24mar_41.dta"
global sus42 "/path/ke/susenas24mar_42.dta"
...
```

### 2. Dependensi Stata

Paket Stata yang dibutuhkan akan terinstall otomatis saat menjalankan file `.do`:
- `reghdfe`, `ftools`, `geodist`, `gtools`
- `ivreghdfe`, `ivreg2`
- `estout` (esttab)
- `geonear` (untuk MDI-Check)

### 3. Dependensi Python

Untuk notebook, install dari project root:
```bash
pip install pandas numpy scipy statsmodels linearmodels libpysal esda spreg geopandas matplotlib
```

### 4. Urutan Eksekusi

**Tahap 1: Persiapan Data**
1. Jalankan `SPBUN-Analysis4A.do` (full sample) dan `SPBUN-Analysis4B.do` (pesisir sample) untuk membuat dataset analysis-ready.

**Tahap 2: Analisis Baseline Stata**
2. Jalankan `SPBUN-Analysis1.do` s/d `SPBUN-Analysis3.do` untuk baseline dan robustness.
3. Jalankan `SPBUN-Analysis4.do` (IV-2SLS dengan `A_v_log`).
4. Jalankan `SPBUN-Analysis5A.do` (IV-2SLS dengan `Ker5_w1`).
5. Jalankan `SPBUN-Analysis5B.do` (IV-2SLS dengan `Ker10_w1`).

**Tahap 3: Model Spasial Python**
6. Buka `FULL_Modelling.ipynb` dan jalankan semua sel (pastikan kernel cwd = project root `PSE_Pertamina`).

**Tahap 4: Kelayakan**
7. Jalankan `MDI-Check.do` untuk analisis probabilitas kelayakan SPBUN.

---

## Data Input yang Dibutuhkan

### Dataset Utama
- **PODES 2024**: `podes2024_desa_02..dta` (data potensi desa)
- **PODES Pesisir**: `Podes kab kota pesisir laut.dta`
- **SUSENAS Maret 2024**: `susenas24mar_41.dta`, `susenas24mar_42.dta`, `susenas24mar_43.dta`
- **SPBUN CSV**: `Realisasi SPBUN 2024-2025(2024).csv` (lokasi & realisasi SPBUN)
- **Kelurahan Lat/Long**: `kelurahan_lat_long.csv` (koordinat fallback)

### Dataset Instrumen (untuk IV-2SLS)
- **Pelabuhan**: `pelabuhan_data.csv`
- **TBBM**: `TBBM_Cleaned_Geocoded.xlsx`
- **TPI**: `tpi_google_v1_master_deduped.xlsx`

---

## Output

### Dari Stata
Semua output disimpan di folder `Output/`:
- `Output/` — hasil Analysis1–3 (tabel regresi, robustness, log)
- `Output/probabilistic/` — hasil Analysis3 (churdle, OLS grid)
- `Output/iv2sls/` — dataset analysis-ready full sample + IV
- `Output/iv2sls_pesisir/` — dataset analysis-ready pesisir sample + IV
- `Output/tsls/tables/` — tabel IV-2SLS (first stage, homog IV, reduced form, OLS)
- `Output/tsls/village_values/` — village-level predictions & residuals (untuk Python)
- `Output/hurdle/` — hasil churdle grid
- `Output/MDI-Check/` — hasil analisis kelayakan SPBUN

### Dari Python (FULL_Modelling.ipynb)
- `outputs/tables/` — ringkasan CSV, tabel koefisien
- `outputs/figures/` — Moran scatterplot, coefficient plot, diagnostik
- `outputs/maps/` — peta PNG (outcome, exposure, LISA, simulasi)

---

## Desain Eksperimen (FULL_Modelling.ipynb)

Pipeline spasial M4–M7 berjalan pada grid berikut:
- **Sampel**: `COAST` (pesisir) dan `ALL` (semua desa)
- **Exposure**: `A_v_log`, `Ker5_w1`, `Ker10_w1`
- **Outcome**: `Wbasic_z` dan `lnpov_z`

Setiap blok model menghasilkan: **3 exposure × 2 sampel × 2 outcome = 12 run**.

### M4 — Diagnostik Autokorelasi Spasial
- Moran's I pada outcome (`Wbasic_z`, `lnpov_z`)
- Moran's I pada residual baseline (dari Stata `uhat`)

### M5 — SLX (Spatial Lag of X)
- Model: `y = β*A + θ*(W*A) + Γ*X + ε`
- Moran's I residual post-fit

### M6 — SDM (Spatial Durbin Model) dengan IV
- First stage: `A_hat` dari instrumen `Z_pel`, `Z_tbbm`, `Z_tpi`
- Model: `y = ρ*(W*y) + β*A_hat + θ*(W*A_hat) + Γ*X + u`
- Dampak langsung / tidak langsung / total via `S = (I - ρW)^(-1)`

### M7 — SEM + Ring-Threshold Robustness
- Ring exposure: `A0_5`, `A5_10`, `A10_15` (0–5 km, 5–10 km, 10–15 km)
- SEM: `ε = λWε + ξ`

---

## Variabel Kunci

### Identifikasi & Geografi
- `iddesa` — ID desa (10 digit)
- `lat_v`, `lon_v` — koordinat desa (derajat desimal)
- `kab` — kode kabupaten (FE dan clustering key)

### Outcome
- `Wbasic_z` — z-score PCA fasilitas dasar
- `lnpov_z` — z-score kemiskinan (dibalik: higher = less poor)

### Exposure
- `A_v_log` — `-ln(1 + D_spbun)`, semakin tinggi = semakin dekat SPBUN
- `Ker5_w1` — kernel-weighted exposure (bandwidth 5 km)
- `Ker10_w1` — kernel-weighted exposure (bandwidth 10 km)

### Instrumen (IV)
- `Z_pel` — `-ln(1 + D_pel)` (jarak ke pelabuhan ikan terdekat)
- `Z_tbbm` — `-ln(1 + D_tbbm)` (jarak ke TBBM terdekat)
- `Z_tpi` — `-ln(1 + D_tpi)` (jarak ke TPI terdekat)

---

## Catatan Alignment Stata–Python

- Gunakan `kab` sebagai FE key dan clustering key (sesuai desain `absorb` + `cluster` di Stata).
- Set instrumen tetap: `Z_pel`, `Z_tbbm`, `Z_tpi`.
- Gunakan `uhat` dari ekspor Stata untuk residual Moran baseline (menghindari mismatch FE/SE).
- Jangan mengubah nama kolom; pertahankan `iddesa`, `kab`, `lat_v`, `lon_v`, dan nama outcome/exposure dari Stata.

---

## Kontak

Untuk akses repositori **PSE_Pertamina2** (kalkulator margin & evaluator dampak interaktif) atau pertanyaan lain terkait penelitian ini, silakan hubungi **PSE (Pusat Studi Energi)**:

Disusun oleh: **Atha Bintang Wahyu M. — Tim Kajian Ekonomi PSE**
