/****************************************************************************************
SPBUN (SPBU Nelayan) - Data generation PESISIR_SAMPLE

Disusun oleh: Atha (PSE)
Tujuan: Analisis #4
****************************************************************************************/

version 17
clear all
set more off
set linesize 255
set maxvar 32767

/****************************************************************************************
A. PATHS 
****************************************************************************************/

* Project root
* Mohon '...' diganti menyesuaikan path anda
global ROOT "..."

* Core inputs used by SPBUN-Analysis4 logic
global spbun_csv    "$ROOT/Realisasi SPBUN 2024-2025(2024).csv"
global kel_latlon   "$ROOT/kelurahan_lat_long.csv"
global podes_main   "$ROOT/Podes/podes2024_desa_02..dta"
global podes_pesisir "$ROOT/Podes/Podes kab kota pesisir laut.dta"

* Instrument point datasets (nearest distance instruments)
global pelabuhan_data "$ROOT/TBBM-TPI-PPI/Data_FIX/pelabuhan_data.csv"
global tbbm_data      "$ROOT/TBBM-TPI-PPI/Data_FIX/TBBM_Cleaned_Geocoded.xlsx"
global tpi_data       "$ROOT/TBBM-TPI-PPI/Data_FIX/tpi_google_v1_master_deduped.xlsx"

* Feasibility / Payback Period (PP) dataset (site-level)
global pp_xlsx "$ROOT/v4_Model_All Fuel 12Bulan SG6.34.xlsx"

* Outputs
global outdir "$ROOT/Output/iv2sls_pesisir"
cap mkdir "$outdir"

cap log close
log using "$outdir/run_spbun_iv2sls_pesisir.log", replace text

/****************************************************************************************
B. PACKAGES
****************************************************************************************/
cap which geodist
if _rc ssc install geodist, replace

/****************************************************************************************
C. HELPERS
****************************************************************************************/

capture program drop _std_iddesa10
program define _std_iddesa10
    syntax varname
    capture confirm numeric variable `varlist'
    if !_rc tostring `varlist', replace format("%010.0f")
    replace `varlist' = trim(`varlist')
    replace `varlist' = subinstr(`varlist'," ","",.)
    replace `varlist' = subinstr(`varlist',".","",.)
    replace `varlist' = subinstr(`varlist',",","",.)
    replace `varlist' = substr("0000000000"+`varlist', strlen("0000000000"+`varlist')-9, 10)
    assert strlen(`varlist')==10
end

capture program drop _std_spbun_no
program define _std_spbun_no
    syntax varname
    capture confirm numeric variable `varlist'
    if !_rc tostring `varlist', replace format("%18.0f")
    replace `varlist' = trim(`varlist')
    replace `varlist' = subinstr(`varlist'," ","",.)
    replace `varlist' = subinstr(`varlist',".","",.)
    replace `varlist' = subinstr(`varlist',",","",.)
    replace `varlist' = subinstr(`varlist',"#","",.)
    replace `varlist' = ustrregexra(`varlist', "[^0-9A-Za-z]", "")
end

* Convert 1/2 yes-no variables to 1/0
capture program drop _yn12_to01
program define _yn12_to01
    syntax varlist
    foreach v of varlist `varlist' {
        cap confirm numeric variable `v'
        if _rc continue
        quietly summarize `v' if !missing(`v'), meanonly
        if (r(min)>=1 & r(max)<=2) {
            replace `v' = (`v'==1) if inlist(`v',1,2)
        }
    }
end

* Fix lat/lon stored in scaled integers / sentinel values
capture program drop _fix_latlon_scale
program define _fix_latlon_scale
    version 15
    syntax varlist(min=2 max=2 numeric)
    local lat : word 1 of `varlist'
    local lon : word 2 of `varlist'

    * drop obvious sentinels / garbage
    replace `lat' = . if !missing(`lat') & abs(`lat') > 1e12
    replace `lon' = . if !missing(`lon') & abs(`lon') > 1e12

    * rescale microdegrees (degrees * 1e7)
    replace `lat' = `lat'/1e7 if !missing(`lat') & abs(`lat') > 90  & abs(`lat') <= 9e8
    replace `lon' = `lon'/1e7 if !missing(`lon') & abs(`lon') > 180 & abs(`lon') <= 18e8

    * swap if reversed
    gen byte __swap = (abs(`lat')>90 & abs(`lon')<=90) if !missing(`lat') & !missing(`lon')
    tempvar __tmp
    gen double `__tmp' = `lat'
    replace `lat' = `lon'   if __swap==1
    replace `lon' = `__tmp' if __swap==1
    drop __swap `__tmp'

    * drop invalid coords
    drop if missing(`lat') | missing(`lon')
    drop if abs(`lat')>90 | abs(`lon')>180
end

* Bin a numeric variable into 0 + quantiles among non-zero (ordinal 0..4)
capture program drop _bin0q4
program define _bin0q4
    syntax varname(numeric), gen(name)
    tempvar q
    cap drop `gen'
    gen byte `gen' = .
    replace `gen' = 0 if `varlist'==0 & !missing(`varlist')

    quietly count if `varlist'>0 & !missing(`varlist')
    if (r(N)>=30) {
        xtile `q' = `varlist' if `varlist'>0 & !missing(`varlist'), nq(4)
        replace `gen' = `q' if `varlist'>0 & !missing(`varlist')
        label define `gen'_lbl 0 "0" 1 "Q1" 2 "Q2" 3 "Q3" 4 "Q4", replace
    }
    else if (r(N)>0) {
        xtile `q' = `varlist' if `varlist'>0 & !missing(`varlist'), nq(2)
        replace `gen' = cond(`q'==1,1,4) if `varlist'>0 & !missing(`varlist')
        label define `gen'_lbl 0 "0" 1 "Low" 4 "High", replace
    }
    else {
        label define `gen'_lbl 0 "0", replace
    }

    label values `gen' `gen'_lbl
end

* Helper: 2-pass min-distance (bin-join) to avoid missingness (robust to empty joins)
capture program drop _mindist_2pass
program define _mindist_2pass
    syntax, IDVAR(name) LATVAR(name) LONVAR(name) USING(string) ///
        OUTVAR(name) [BINSZ1(real 1) RING1(integer 6) BINSZ2(real 2) RING2(integer 7)]

    tempfile V P1 P2 D1 D2 MISS

    * Village base (coords only)
    preserve
        keep `idvar' `latvar' `lonvar'
        drop if missing(`latvar') | missing(`lonvar')
        save `V', replace
    restore

    * ---------------- PASS 1 ----------------
    preserve
        use "`using'", clear
        keep pid lat_p lon_p
        drop if missing(lat_p) | missing(lon_p)
        gen int latbin = floor(lat_p/`binsz1')
        gen int lonbin = floor(lon_p/`binsz1')
        local K1 = (2*`ring1'+1)
        local E1 = `K1'*`K1'
        expand `E1'
        bys pid: gen int __g = _n-1
        gen int dlat = floor(__g/`K1') - `ring1'
        gen int dlon = mod(__g,`K1') - `ring1'
        gen int latbin2 = latbin + dlat
        gen int lonbin2 = lonbin + dlon
        drop __g dlat dlon latbin lonbin
        rename latbin2 latbin
        rename lonbin2 lonbin
        save `P1', replace
    restore

    preserve
        use `V', clear
        gen int latbin = floor(`latvar'/`binsz1')
        gen int lonbin = floor(`lonvar'/`binsz1')
        joinby latbin lonbin using `P1'
        quietly count
        if r(N)>0 {
            geodist `latvar' `lonvar' lat_p lon_p, gen(__dkm)
            bys `idvar': egen double `outvar' = min(__dkm)
            keep `idvar' `outvar'
            duplicates drop `idvar', force
            save `D1', replace
        }
        else {
            use `V', clear
            keep `idvar'
            gen double `outvar' = .
            duplicates drop `idvar', force
            save `D1', replace
        }
    restore

    merge 1:1 `idvar' using `D1', nogen

    * ---------------- PASS 2 ----------------
    quietly count if missing(`outvar') & !missing(`latvar') & !missing(`lonvar')
    if r(N) > 0 {

        preserve
            keep if missing(`outvar') & !missing(`latvar') & !missing(`lonvar')
            keep `idvar' `latvar' `lonvar'
            save `MISS', replace
        restore

        preserve
            use "`using'", clear
            keep pid lat_p lon_p
            drop if missing(lat_p) | missing(lon_p)
            gen int latbin = floor(lat_p/`binsz2')
            gen int lonbin = floor(lon_p/`binsz2')
            local K2 = (2*`ring2'+1)
            local E2 = `K2'*`K2'
            expand `E2'
            bys pid: gen int __g = _n-1
            gen int dlat = floor(__g/`K2') - `ring2'
            gen int dlon = mod(__g,`K2') - `ring2'
            gen int latbin2 = latbin + dlat
            gen int lonbin2 = lonbin + dlon
            drop __g dlat dlon latbin lonbin
            rename latbin2 latbin
            rename lonbin2 lonbin
            save `P2', replace
        restore

        preserve
            use `MISS', clear
            gen int latbin = floor(`latvar'/`binsz2')
            gen int lonbin = floor(`lonvar'/`binsz2')
            joinby latbin lonbin using `P2'
            quietly count
            if r(N)>0 {
                geodist `latvar' `lonvar' lat_p lon_p, gen(__dkm)
                bys `idvar': egen double __d2 = min(__dkm)
                keep `idvar' __d2
                duplicates drop `idvar', force
                save `D2', replace
            }
            else {
                use `MISS', clear
                keep `idvar'
                gen double __d2 = .
                duplicates drop `idvar', force
                save `D2', replace
            }
        restore

        merge 1:1 `idvar' using `D2', nogen
        replace `outvar' = __d2 if missing(`outvar') & !missing(__d2)
        drop __d2
    }
end


/****************************************************************************************
D. BUILD "$outdir/podes_vill.dta"  (MAIN + PESISIR + coords fallback)
****************************************************************************************/
tempfile MAIN PES kelcoords

* D1) MAIN
use "$podes_main", clear

cap confirm variable IDDESA
if _rc {
    cap confirm variable iddesa
    if !_rc rename iddesa IDDESA
    cap confirm variable IdDesa
    if !_rc rename IdDesa IDDESA
    cap confirm variable Iddesa
    if !_rc rename Iddesa IDDESA
}
cap confirm variable IDDESA
if _rc {
    di as err "MAIN: cannot find village id variable (IDDESA/iddesa)."
    describe, short
    exit 111
}

cap confirm numeric variable IDDESA
if !_rc tostring IDDESA, replace format("%010.0f")

replace IDDESA = trim(IDDESA)
replace IDDESA = subinstr(IDDESA," ","",.)
replace IDDESA = subinstr(IDDESA,".","",.)
replace IDDESA = subinstr(IDDESA,",","",.)
replace IDDESA = substr("0000000000"+IDDESA, strlen("0000000000"+IDDESA)-9, 10)
assert strlen(IDDESA)==10

rename *, lower
rename iddesa iddesa
_std_iddesa10 iddesa

duplicates drop iddesa, force
save `MAIN', replace

* D2) PESISIR (prefix p_)
use "$podes_pesisir", clear
rename *, lower

cap confirm variable iddesa
if _rc {
    di as err "PESISIR: iddesa not found."
    describe, short
    exit 111
}
_std_iddesa10 iddesa

keep iddesa r307b_lat r307b_long ///
     r308* r309* r310 ///
     r402* r403* ///
     r501* r502* r503* ///
     r507* r508* r509* ///
     r510* r511* r514* r515*

duplicates drop iddesa, force
ds iddesa, not
local pesvars `r(varlist)'
foreach v of local pesvars {
    rename `v' p_`v'
}
save `PES', replace

* D3) MERGE MAIN + PESISIR; fill missing from p_*
use `MAIN', clear
merge 1:1 iddesa using `PES', nogen keep(master match)

capture ds p_*
if !_rc {
    local plist `r(varlist)'
    foreach pv of local plist {
        local tv = substr("`pv'",3,.)
        capture confirm variable `tv'
        if _rc {
            rename `pv' `tv'
        }
        else {
            capture confirm numeric variable `tv'
            if !_rc {
                replace `tv' = `pv' if missing(`tv') & !missing(`pv')
            }
            else {
                capture confirm string variable `tv'
                if !_rc {
                    replace `tv' = `pv' if (`tv'=="") & (`pv'!="")
                }
            }
            drop `pv'
        }
    }
}

* admin codes from iddesa
capture drop r101 r102 r103 r104
gen int r101 = real(substr(iddesa,1,2))
gen int r102 = real(substr(iddesa,3,2))
gen int r103 = real(substr(iddesa,5,3))
gen int r104 = real(substr(iddesa,8,3))

capture drop kab
egen long kab = group(r101 r102), label

* coords prefer r307b_lat/long
cap confirm variable lat_v
if _rc gen double lat_v = .
cap confirm variable lon_v
if _rc gen double lon_v = .

cap confirm variable r307b_lat
if !_rc {
    cap confirm numeric variable r307b_lat
    if _rc destring r307b_lat, replace ignore(",")
    replace lat_v = r307b_lat if missing(lat_v) & !missing(r307b_lat)
}
cap confirm variable r307b_long
if !_rc {
    cap confirm numeric variable r307b_long
    if _rc destring r307b_long, replace ignore(",")
    replace lon_v = r307b_long if missing(lon_v) & !missing(r307b_long)
}
capture drop r307b_lat r307b_long

* fallback coords from kel_latlon if still missing
count if missing(lat_v) | missing(lon_v)
if r(N) > 0 {
    di as txt "Coords missing for " r(N) " villages -> fallback merge from kel_latlon..."
    preserve
        import delimited "$kel_latlon", clear varnames(1) case(preserve) stringcols(_all)

        local idv ""
        local latc ""
        local lonc ""
        foreach v of varlist _all {
            if "`idv'"==""  & strpos(lower("`v'"),"iddesa") local idv `v'
            if "`latc'"=="" & strpos(lower("`v'"),"lat")    local latc `v'
            if "`lonc'"=="" & (strpos(lower("`v'"),"lon") | strpos(lower("`v'"),"long")) local lonc `v'
        }

        if "`idv'"!="" & "`latc'"!="" & "`lonc'"!="" {
            rename `idv' iddesa
            rename `latc' lat_v2
            rename `lonc' lon_v2
            _std_iddesa10 iddesa
            destring lat_v2 lon_v2, replace ignore(",")
            keep iddesa lat_v2 lon_v2
            duplicates drop iddesa, force
            save `kelcoords', replace
        }
    restore

    capture confirm file "`kelcoords'"
    if !_rc {
        merge 1:1 iddesa using `kelcoords', nogen keep(master match)
        replace lat_v = lat_v2 if missing(lat_v) & !missing(lat_v2)
        replace lon_v = lon_v2 if missing(lon_v) & !missing(lon_v2)
        drop lat_v2 lon_v2
    }
}

save "$outdir/podes_vill.dta", replace
di as result "Saved: $outdir/podes_vill.dta"

/****************************************************************************************
E. BUILD SPBUN SITE DATASET (coords + weights + stable SPBUN number if present)
****************************************************************************************/
tempfile spbun_site
import delimited "$spbun_csv", clear varnames(1) case(preserve) stringcols(_all)

* stable SPBUN identifier
local spbunno ""
foreach v of varlist _all {
    if "`spbunno'"=="" & (strpos(lower("`v'"),"nomor") & strpos(lower("`v'"),"spbun")) local spbunno `v'
    if "`spbunno'"=="" & (strpos(lower("`v'"),"no")    & strpos(lower("`v'"),"spbun")) local spbunno `v'
    if "`spbunno'"=="" & (strpos(lower("`v'"),"kode")  & strpos(lower("`v'"),"spbun")) local spbunno `v'
}
if "`spbunno'"!="" {
    rename `spbunno' spbun_no
    _std_spbun_no spbun_no
}
else {
    gen str20 spbun_no = ""
}

* coordinates
capture confirm variable TitikKoordinat
if _rc {
    di as err "Cannot find TitikKoordinat in SPBUN CSV."
    describe
    exit 198
}
rename TitikKoordinat titik_koordinat

replace titik_koordinat = subinstr(titik_koordinat, char(34), "", .)
replace titik_koordinat = subinstr(titik_koordinat, char(39), "", .)
replace titik_koordinat = subinstr(titik_koordinat, " ", "", .)
replace titik_koordinat = "" if inlist(upper(trim(titik_koordinat)), "#N/A", "N/A", "NA", ".")

gen strL coord = titik_koordinat
split coord, parse(",") gen(_c)

foreach v of varlist _c* {
    replace `v' = trim(`v')
    replace `v' = subinstr(`v', char(160),"", .)
    replace `v' = subinstr(`v', "–", "-", .)
    replace `v' = subinstr(`v', "−", "-", .)
    replace `v' = ustrregexra(`v', "[^0-9.-]", "")
}

gen double lat_s = real(_c1)
gen double lon_s = real(_c2)
drop _c* coord

* swap if reversed
gen byte _swap = (abs(lat_s)>90 & abs(lon_s)<=90)
gen double _tmp = lat_s
replace lat_s = lon_s if _swap
replace lon_s = _tmp  if _swap
drop _swap _tmp

drop if missing(lat_s) | missing(lon_s)

* quota vars (auto-detect)
local qjbt ""
local qjbkp ""
foreach v of varlist _all {
    if "`qjbt'"==""  & strpos(lower("`v'"),"kuota") & strpos(lower("`v'"),"jbt")  local qjbt  `v'
    if "`qjbkp'"=="" & strpos(lower("`v'"),"kuota") & strpos(lower("`v'"),"jbkp") local qjbkp `v'
}
if "`qjbt'"!=""  rename `qjbt'  kuota_jbt
if "`qjbkp'"!="" rename `qjbkp' kuota_jbkp
capture destring kuota_jbt kuota_jbkp, replace ignore(",")

* volume proxy: destring likely volume cols, then rowtotal
capture ds Total* *total* *realisasi* *volume*, has(type string)
if !_rc {
    foreach v of varlist `r(varlist)' {
        capture destring `v', replace ignore(",")
    }
}
local volvars ""
capture ds Total* *total* *realisasi* *volume*, has(type numeric)
if !_rc local volvars "`r(varlist)'"

capture drop vol_s
if "`volvars'"!="" {
    egen double vol_s = rowtotal(`volvars'), missing
}
else {
    gen double vol_s = .
}

gen double quota_s = .
capture confirm variable kuota_jbt
if !_rc replace quota_s = kuota_jbt
capture confirm variable kuota_jbkp
if !_rc replace quota_s = cond(missing(quota_s), kuota_jbkp, quota_s + kuota_jbkp)

gen double rr_s = .
replace rr_s = vol_s / quota_s if quota_s>0 & !missing(vol_s)

gen double w1   = 1
gen double wvol = vol_s
gen double wrr  = rr_s

gen long site_id = _n
keep site_id spbun_no lat_s lon_s vol_s quota_s rr_s w1 wvol wrr
save `spbun_site', replace
save "$outdir/spbun_site_raw.dta", replace


/****************************************************************************************
F. ASSIGN EACH SPBUN SITE TO NEAREST VILLAGE (get r101/r102, kab)
****************************************************************************************/
tempfile spbun_site_coded villcoords site_bins site2kab
local binsz = 0.10

use `spbun_site', clear

preserve
    use "$outdir/podes_vill.dta", clear
    keep iddesa kab r101 r102 lat_v lon_v
    drop if missing(lat_v) | missing(lon_v)
    save `villcoords', replace
restore

drop if missing(lat_s) | missing(lon_s)

gen int latbin = floor(lat_s/`binsz')
gen int lonbin = floor(lon_s/`binsz')

expand 9
bys site_id: gen byte _g = _n - 1
gen int dlat = floor(_g/3) - 1
gen int dlon = mod(_g,3) - 1
gen int latbin2 = latbin + dlat
gen int lonbin2 = lonbin + dlon
drop _g dlat dlon

save `site_bins', replace

use `villcoords', clear
gen int latbin2 = floor(lat_v/`binsz')
gen int lonbin2 = floor(lon_v/`binsz')

joinby latbin2 lonbin2 using `site_bins'
geodist lat_v lon_v lat_s lon_s, gen(dkm)
bys site_id (dkm): keep if _n==1

keep site_id r101 r102 kab
save `site2kab', replace

use `spbun_site', clear
merge 1:1 site_id using `site2kab', nogen keep(master match)
save `spbun_site_coded', replace
save "$outdir/spbun_site_coded.dta", replace

tempfile spbun_pts
preserve
    use "$outdir/spbun_site_coded.dta", clear
    keep site_id lat_s lon_s
    drop if missing(lat_s) | missing(lon_s)
    rename site_id pid
    rename lat_s lat_p
    rename lon_s lon_p
    save `spbun_pts', replace
restore


/****************************************************************************************
G. VILLAGE-LEVEL EXPOSURE MEASURES (+ nearest SPBUN id)
****************************************************************************************/
tempfile vill_bins site_bins2 vill_exposure vill_exposure_only

use "$outdir/podes_vill.dta", clear
keep iddesa kab r101 r102 lat_v lon_v
drop if missing(lat_v) | missing(lon_v)
gen int latbin = floor(lat_v/`binsz')
gen int lonbin = floor(lon_v/`binsz')
save `vill_bins', replace

use `spbun_site_coded', clear
keep site_id spbun_no lat_s lon_s w1 wvol wrr vol_s rr_s r101 r102 kab
drop if missing(lat_s) | missing(lon_s)
gen int latbin = floor(lat_s/`binsz')
gen int lonbin = floor(lon_s/`binsz')

expand 9
bys site_id: gen byte _g = _n - 1
gen int dlat = floor(_g/3) - 1
gen int dlon = mod(_g,3) - 1
gen int latbin2 = latbin + dlat
gen int lonbin2 = lonbin + dlon
drop _g dlat dlon latbin lonbin
rename latbin2 latbin
rename lonbin2 lonbin
save `site_bins2', replace

use `vill_bins', clear
joinby latbin lonbin using `site_bins2'
geodist lat_v lon_v lat_s lon_s, gen(dkm)

* nearest site metadata
sort iddesa dkm
by iddesa: gen double D_v = dkm[1]
by iddesa: gen str30 _nearest_spbun_no_i = spbun_no[1]
by iddesa: gen long  _nearest_site_id_i = site_id[1]

gen double A_v_log = -ln(1 + D_v)
gen double A_v_inv = 1/(1 + D_v)

* counts within radius
foreach R in 5 10 15 {
    gen double C`R'_w1_i   = w1   * (dkm<=`R')
    gen double C`R'_wvol_i = wvol * (dkm<=`R')
    gen double C`R'_wrr_i  = wrr  * (dkm<=`R')
}

* kernel sums
foreach h in 5 10 20 {
    gen double Ker`h'_w1_i   = w1   * exp(-dkm/`h') * (dkm <= 3*`h')
    gen double Ker`h'_wvol_i = wvol * exp(-dkm/`h') * (dkm <= 3*`h')
    gen double Ker`h'_wrr_i  = wrr  * exp(-dkm/`h') * (dkm <= 3*`h')
}

collapse (min) D_v (firstnm) A_v_log A_v_inv ///
    (firstnm) nearest_spbun_no=_nearest_spbun_no_i nearest_site_id=_nearest_site_id_i ///
    (sum) ///
    C5_w1=C5_w1_i     C5_wvol=C5_wvol_i     C5_wrr=C5_wrr_i ///
    C10_w1=C10_w1_i   C10_wvol=C10_wvol_i   C10_wrr=C10_wrr_i ///
    C15_w1=C15_w1_i   C15_wvol=C15_wvol_i   C15_wrr=C15_wrr_i ///
    Ker5_w1=Ker5_w1_i   Ker5_wvol=Ker5_wvol_i   Ker5_wrr=Ker5_wrr_i ///
    Ker10_w1=Ker10_w1_i Ker10_wvol=Ker10_wvol_i Ker10_wrr=Ker10_wrr_i ///
    Ker20_w1=Ker20_w1_i Ker20_wvol=Ker20_wvol_i Ker20_wrr=Ker20_wrr_i ///
, by(iddesa)

* cap count-style measures at 3 (0,1,2,3+)
foreach R in 5 10 15 {
    replace C`R'_w1   = 3 if C`R'_w1   > 3 & !missing(C`R'_w1)
    replace C`R'_wvol = 3 if C`R'_wvol > 3 & !missing(C`R'_wvol)
    replace C`R'_wrr  = 3 if C`R'_wrr  > 3 & !missing(C`R'_wrr)
}

foreach h in 5 10 20 {
    cap drop Ker`h'_w1_pos lnKer`h'_w1
    gen byte   Ker`h'_w1_pos = (Ker`h'_w1 > 0) if !missing(Ker`h'_w1)
    gen double lnKer`h'_w1    = ln(1 + Ker`h'_w1)

    cap drop Ker`h'_wvol_pos lnKer`h'_wvol
    gen byte   Ker`h'_wvol_pos = (Ker`h'_wvol > 0) if !missing(Ker`h'_wvol)
    gen double lnKer`h'_wvol    = ln(1 + Ker`h'_wvol)

    cap drop Ker`h'_wrr_pos lnKer`h'_wrr
    gen byte   Ker`h'_wrr_pos = (Ker`h'_wrr > 0) if !missing(Ker`h'_wrr)
    gen double lnKer`h'_wrr    = ln(1 + Ker`h'_wrr)
}

keep iddesa D_v A_v_log A_v_inv nearest_spbun_no nearest_site_id ///
    C*_w1 C*_wvol C*_wrr ///
    Ker*_w1 Ker*_wvol Ker*_wrr ///
    Ker*_w1_pos Ker*_wvol_pos Ker*_wrr_pos ///
    lnKer*_w1 lnKer*_wvol lnKer*_wrr
save `vill_exposure_only', replace

use "$outdir/podes_vill.dta", clear
merge 1:1 iddesa using `vill_exposure_only', nogen keep(master match)

gen byte coord_ok  = !missing(lat_v) & !missing(lon_v)
gen byte exp_match = !missing(D_v)

* zero-fill missing exposures for villages with valid coords but no matched sites
foreach v of varlist C*_w1 C*_wvol C*_wrr Ker*_w1 Ker*_wvol Ker*_wrr ///
                   Ker*_w1_pos Ker*_wvol_pos Ker*_wrr_pos ///
                   lnKer*_w1 lnKer*_wvol lnKer*_wrr {
    replace `v' = 0 if missing(`v') & coord_ok==1
}

save `vill_exposure', replace
save "$outdir/podes_vill_exposure.dta", replace

* Restrict to pesisir villages only
cap confirm numeric variable r308a
keep if r308a==1

/****************************************************************************************
H. PCA welfare indices (Wbasic_z, Util_z, Edu_z, Hlth_z) + poverty proxy lnpov
****************************************************************************************/

* 0) SPBUN target label (full sample; no filtering)
cap drop spbun_target
gen byte spbun_target = 0
foreach v in r308b1a r308b1b r308b1c {
    cap confirm numeric variable `v'
    if !_rc replace spbun_target = 1 if `v'==1
}
label define spbun_target_lbl 0 "Non-target" 1 "Target (tangkap/budidaya/garam)", replace
label values spbun_target spbun_target_lbl

* Coast / fish dummies (optional controls/heterogeneity)
cap drop Coast Fish_strict Fish_loose
cap confirm numeric variable r308a
if !_rc gen byte Coast = (r308a==1) if !missing(r308a)
cap confirm numeric variable r308b1a
if !_rc cap confirm numeric variable r308b1b
if !_rc gen byte Fish_strict = (Coast==1 & (r308b1a==1 | r308b1b==1)) if !missing(Coast)
cap confirm numeric variable r308b1c
if !_rc gen byte Fish_loose = (Coast==1 | r308b1a==1 | r308b1b==1 | r308b1c==1 | r308b1d==1 | r308b1e==1) if !missing(r308b1d) | !missing(r308b1e) | !missing(Coast)

* 1) Wbasic
cap drop hh_light_total sh_elec elec_cat
egen double hh_light_total = rowtotal(r501a1 r501a2 r501b r501c)
replace hh_light_total = . if missing(r501a1) & missing(r501a2) & missing(r501b) & missing(r501c)

gen double sh_elec = (r501a1 + r501a2) / hh_light_total if hh_light_total>0

gen byte elec_cat = .
replace elec_cat = 3 if sh_elec>=0.90 & sh_elec<=1
replace elec_cat = 2 if sh_elec>=0.50 & sh_elec<0.90
replace elec_cat = 1 if sh_elec>0    & sh_elec<0.50
replace elec_cat = 0 if sh_elec==0

label define elec_cat_lbl 0 "0%" 1 "1-49%" 2 "50-89%" 3 ">=90%", replace
label values elec_cat elec_cat_lbl

cap drop cook_market
cap confirm numeric variable r503b
if !_rc gen byte cook_market = inlist(r503b,1,2,3,4,5,7) if !missing(r503b)

_yn12_to01 r503a1-r503a11
_yn12_to01 r502a r502b r502c

local Wbasic_in "elec_cat r502a r502b r502c cook_market r503a1-r503a11"

* 2) Util
_yn12_to01 r507* r508a r508b r509a r509b r510*

foreach v in r509c1 r509c2 r509c3 {
    cap confirm numeric variable `v'
    if !_rc _bin0q4 `v', gen(`v'_b)
}

ds r511c* r514* r515*, has(type numeric)
local util_extra "`r(varlist)'"

foreach v of local util_extra {
    quietly summarize `v' if !missing(`v'), meanonly
    if (r(min)>=1 & r(max)<=2) {
        replace `v' = (`v'==1) if inlist(`v',1,2)
    }
    else if (r(max)>20) {
        _bin0q4 `v', gen(`v'_b)
    }
}

local Wutil_in "r507* r508a r508b r509a r509b"
foreach v in r509c1 r509c2 r509c3 {
    cap confirm variable `v'_b
    if !_rc local Wutil_in "`Wutil_in' `v'_b"
}
foreach v of local util_extra {
    cap confirm variable `v'_b
    if !_rc local Wutil_in "`Wutil_in' `v'_b"
    else local Wutil_in "`Wutil_in' `v'"
}

* 3) Edu
ds r701*, has(type numeric)
local edu_raw "`r(varlist)'"
local Edu_in ""

foreach v of local edu_raw {
    quietly summarize `v' if !missing(`v'), meanonly
    if (r(min)>=1 & r(max)<=2) {
        replace `v' = (`v'==1) if inlist(`v',1,2)
        local Edu_in "`Edu_in' `v'"
    }
    else if (r(max)>20) {
        _bin0q4 `v', gen(`v'_b)
        local Edu_in "`Edu_in' `v'_b"
    }
    else {
        local Edu_in "`Edu_in' `v'"
    }
}

* 4) Hlth
ds r711*, has(type numeric)
local hlth_raw "`r(varlist)'"
local Hlth_in ""

foreach v of local hlth_raw {
    quietly summarize `v' if !missing(`v'), meanonly
    if (r(min)>=1 & r(max)<=2) {
        replace `v' = (`v'==1) if inlist(`v',1,2)
        local Hlth_in "`Hlth_in' `v'"
    }
    else if (r(max)>20) {
        _bin0q4 `v', gen(`v'_b)
        local Hlth_in "`Hlth_in' `v'_b"
    }
    else {
        cap drop ln1p_`v'
        gen double ln1p_`v' = ln(1+`v') if !missing(`v')
        _bin0q4 ln1p_`v', gen(`v'_b)
        local Hlth_in "`Hlth_in' `v'_b"
    }
}

* 5) Poverty proxy
cap drop lnpov
cap confirm numeric variable r710
if !_rc {
    gen double lnpov = ln(1+r710) if !missing(r710)
    cap drop lnpov_b
    _bin0q4 lnpov, gen(lnpov_b)
}

* 6) Optional environment index (Env_z)
cap drop Env_pca1 Env_z
cap noisily pca r309a r309b r309d r309e r310, components(1) correlation
if !_rc {
    predict double Env_pca1 if e(sample), score
    egen double Env_z = std(Env_pca1)
}

* 7) PCA (1 component each) + z-score
cap noisily pca `Wbasic_in', components(1) correlation
if !_rc {
    cap drop Wbasic_pca1 Wbasic_z
    predict double Wbasic_pca1 if e(sample), score
    egen double Wbasic_z = std(Wbasic_pca1)
}

cap noisily pca `Wutil_in', components(1) correlation
if !_rc {
    cap drop Util_pca1 Util_z
    predict double Util_pca1 if e(sample), score
    egen double Util_z = std(Util_pca1)
}

cap noisily pca `Edu_in', components(1) correlation
if !_rc {
    cap drop Edu_pca1 Edu_z
    predict double Edu_pca1 if e(sample), score
    egen double Edu_z = std(Edu_pca1)
}

cap noisily pca `Hlth_in', components(1) correlation
if !_rc {
    cap drop Hlth_pca1 Hlth_z
    predict double Hlth_pca1 if e(sample), score
    egen double Hlth_z = std(Hlth_pca1)
}

if !_rc {
	cap drop lnpov_z
	egen double lnpov_z = std(-lnpov)
}


* 8) PCA of all components
local META_IN "Wbasic_z lnpov_z"

cap drop WelfareMeta_pca1_all WelfareMeta_z_all

predict double WelfareMeta_pca1_coast if e(sample), score
egen double WelfareMeta_z_coast = std(WelfareMeta_pca1_coast) if !missing(WelfareMeta_pca1_coast)

label var WelfareMeta_pca1_coast "Meta welfare PC1 score (COAST)"
label var WelfareMeta_z_coast    "Meta welfare PC1 z-score (COAST)"

* ----------------------------
* 8) (nearest SPBUN) + SAVE (exposure + PCA + IV-ready A)
* ----------------------------
if "`spbun_pts'"=="" {
    di as err "spbun_pts tempfile not defined. Run the SPBUN points section earlier in the SAME session."
    exit 198
}
cap confirm file "`spbun_pts'"
if _rc {
    di as err "spbun_pts tempfile not found on disk. Re-run the points section earlier in the SAME session."
    exit 198
}

* recompute nearest distance (village -> SPBUN points)
cap drop D_spbun
_mindist_2pass, idvar(iddesa) latvar(lat_v) lonvar(lon_v) using("`spbun_pts'") ///
    outvar(D_spbun) binsz1(1) ring1(6) binsz2(2) ring2(7)

* build A measures safely
cap drop A_v_log
gen double A_v_log = -ln(1 + D_spbun) if !missing(D_spbun)

cap drop A_v_inv
gen double A_v_inv = 1/(1 + D_spbun) if !missing(D_spbun)

compress
save "$outdir/podes_vill_spbun_pca.dta", replace

/****************************************************************************************
I. INSTRUMENTS (VILLAGE-LEVEL): village distance to Pelabuhan/TBBM/TPI
******************************************************************************/
*----------------------------
* 0) Guards
*----------------------------
cap which geodist
if _rc {
    di as err "geodist not installed. Run: ssc install geodist, replace"
    exit 199
}

capture program list _mindist_2pass
if _rc {
    di as err "_mindist_2pass is not defined in memory. Ensure Section C (HELPERS) runs before Section I in the SAME do-file/session."
    exit 199
}

capture program list _fix_latlon_scale
if _rc {
    di as err "_fix_latlon_scale is not defined in memory. Ensure Section C (HELPERS) runs before Section I in the SAME do-file/session."
    exit 199
}

*----------------------------
* 1) Build standardized point datasets (Pelabuhan/TBBM/TPI)
*----------------------------
tempfile pel_pts tbbm_pts tpi_pts

* ---- Pelabuhan points ----
preserve
    import delimited "$pelabuhan_data", clear varnames(1) case(preserve) stringcols(_all)

    local latcol ""
    local loncol ""
    foreach v of varlist _all {
        if "`latcol'"=="" & (strpos(lower("`v'"),"lintang") | strpos(lower("`v'"),"lat")) {
            local latcol `v'
        }
        if "`loncol'"=="" & (strpos(lower("`v'"),"bujur") | strpos(lower("`v'"),"lon") | strpos(lower("`v'"),"long")) {
            local loncol `v'
        }
    }

    if "`latcol'"=="" | "`loncol'"=="" {
        di as err "Pelabuhan: could not detect lat/lon columns."
        describe, short
        restore
        exit 198
    }

    rename `latcol' lat_p
    rename `loncol' lon_p
    destring lat_p lon_p, replace ignore(",")

    _fix_latlon_scale lat_p lon_p

    keep lat_p lon_p
    gen long pid = _n
    save `pel_pts', replace
    save "$outdir/pel_pts.dta", replace
restore

* ---- TBBM points ----
preserve
    cap noisily import excel "$tbbm_data", describe
    if _rc {
        di as err "TBBM: import excel describe failed. Check $tbbm_data path/format."
        restore
        exit 601
    }

    local ws1 = r(worksheet_1)
    import excel "$tbbm_data", sheet("`ws1'") firstrow clear

    local latcol ""
    local loncol ""
    foreach v of varlist _all {
        if "`latcol'"=="" & strpos(lower("`v'"),"lat") {
            local latcol `v'
        }
        if "`loncol'"=="" & (strpos(lower("`v'"),"lon") | strpos(lower("`v'"),"long")) {
            local loncol `v'
        }
    }

    if "`latcol'"=="" | "`loncol'"=="" {
        di as err "TBBM: could not detect lat/lon columns."
        describe, short
        restore
        exit 198
    }

    rename `latcol' lat_p
    rename `loncol' lon_p
    destring lat_p lon_p, replace ignore(",")

    _fix_latlon_scale lat_p lon_p

    keep lat_p lon_p
    gen long pid = _n
    save `tbbm_pts', replace
    save "$outdir/tbbm_pts.dta", replace
restore

* ---- TPI points ----
preserve
    cap noisily import excel "$tpi_data", describe
    if _rc {
        di as err "TPI: import excel describe failed. Check $tpi_data path/format."
        restore
        exit 601
    }

    local ws1 = r(worksheet_1)
    import excel "$tpi_data", sheet("`ws1'") firstrow clear

    local latcol ""
    local loncol ""
    foreach v of varlist _all {
        if "`latcol'"=="" & strpos(lower("`v'"),"lat") {
            local latcol `v'
        }
        if "`loncol'"=="" & (strpos(lower("`v'"),"lon") | strpos(lower("`v'"),"long")) {
            local loncol `v'
        }
    }

    if "`latcol'"=="" | "`loncol'"=="" {
        di as err "TPI: could not detect lat/lon columns."
        describe, short
        restore
        exit 198
    }

    rename `latcol' lat_p
    rename `loncol' lon_p
    destring lat_p lon_p, replace ignore(",")

    _fix_latlon_scale lat_p lon_p

    keep lat_p lon_p
    gen long pid = _n
    save `tpi_pts', replace
    save "$outdir/tpi_pts.dta", replace
restore

*----------------------------
* 2) Compute village-level IVs (village -> nearest node)
*----------------------------
use "$outdir/podes_vill_spbun_pca.dta", clear

cap confirm variable lat_v
if _rc {
    merge 1:1 iddesa using "$outdir/podes_vill.dta", nogen keep(master match) keepusing(lat_v lon_v kab)
}

cap confirm variable lon_v
if _rc {
    merge 1:1 iddesa using "$outdir/podes_vill.dta", nogen keep(master match) keepusing(lat_v lon_v kab)
}

cap confirm variable lat_v
if _rc {
    di as err "lat_v missing even after merge."
    exit 111
}

cap confirm variable lon_v
if _rc {
    di as err "lon_v missing even after merge."
    exit 111
}

cap drop D_pel_iv D_tbbm_iv D_tpi_iv

_mindist_2pass, idvar(iddesa) latvar(lat_v) lonvar(lon_v) using("`pel_pts'") ///
    outvar(D_pel_iv) binsz1(1) ring1(6) binsz2(2) ring2(7)

_mindist_2pass, idvar(iddesa) latvar(lat_v) lonvar(lon_v) using("`tbbm_pts'") ///
    outvar(D_tbbm_iv) binsz1(1) ring1(6) binsz2(2) ring2(7)

_mindist_2pass, idvar(iddesa) latvar(lat_v) lonvar(lon_v) using("`tpi_pts'") ///
    outvar(D_tpi_iv) binsz1(1) ring1(6) binsz2(2) ring2(7)

cap drop Z_pel Z_tbbm Z_tpi
gen double Z_pel  = -ln(1 + D_pel_iv)  if !missing(D_pel_iv)
gen double Z_tbbm = -ln(1 + D_tbbm_iv) if !missing(D_tbbm_iv)
gen double Z_tpi  = -ln(1 + D_tpi_iv)  if !missing(D_tpi_iv)

*----------------------------
* 3) Diagnostics: check kab-constant instruments (optional)
*----------------------------
cap confirm variable kab
if !_rc {
    foreach v in Z_pel Z_tbbm Z_tpi {
        cap drop sd_`v'
        bys kab: egen sd_`v' = sd(`v')
        di "---- `v': kab groups with sd==0 (among non-missing) ----"
        count if sd_`v'==0 & !missing(sd_`v')
    }
}

compress
save "$outdir/podes_vill_spbun_pca_iv.dta", replace

exit, clear
