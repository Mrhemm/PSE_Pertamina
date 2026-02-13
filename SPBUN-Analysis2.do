/****************************************************************************************
SPBUN (SPBU Nelayan) exposure → welfare outcomes (PODES village + SUSENAS household)
Baseline: SPBUN only (extend later for SPBU / SPBUN+SPBU)

Disusun oleh: Atha (PSE)
Tujuan: Analisis #2 
****************************************************************************************/

version 17
clear all
set more off
set linesize 255
set maxvar 32767

/****************************************************************************************
A. PATHS
****************************************************************************************/
* Mohon '...' diganti menyesuaikan path anda
global spbun_csv "..."
global kel_latlon "..."

global podes_main    "..."
global podes_pesisir "..."

global outdir "..."
cap mkdir "$outdir"

cap log close
log using "$outdir/run_spbun_podes_susenas.log", replace text

/****************************************************************************************
B. PACKAGES
****************************************************************************************/
cap which reghdfe
if _rc ssc install reghdfe, replace
cap which ftools
if _rc ssc install ftools, replace
cap which geodist
if _rc ssc install geodist, replace
cap which gtools
if _rc ssc install gtools, replace

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
cap confirm variable iddesa
if _rc rename iddesa iddesa
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
E. BUILD SPBUN SITE DATASET FROM CSV (coords + volumes + quota + rr)
****************************************************************************************/
tempfile spbun_site
import delimited "$spbun_csv", clear varnames(1) case(preserve) stringcols(_all)

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

* swap if obviously reversed
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

* volume (robust): destring likely volume cols, then rowtotal
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
keep site_id lat_s lon_s vol_s quota_s rr_s w1 wvol wrr
save `spbun_site', replace

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

/****************************************************************************************
G. VILLAGE-LEVEL EXPOSURE MEASURES
****************************************************************************************/
tempfile vill_core vill_bins site_bins2 vill_exposure vill_exposure_only

use "$outdir/podes_vill.dta", clear
keep iddesa kab r101 r102 lat_v lon_v
save `vill_core', replace

use `vill_core', clear
drop if missing(lat_v) | missing(lon_v)
gen int latbin = floor(lat_v/`binsz')
gen int lonbin = floor(lon_v/`binsz')
save `vill_bins', replace

use `spbun_site_coded', clear
keep site_id lat_s lon_s w1 wvol wrr vol_s rr_s r101 r102 kab
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

bys iddesa: egen double D_v = min(dkm)
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
    * w1
    cap drop Ker`h'_w1_pos lnKer`h'_w1
    gen byte   Ker`h'_w1_pos = (Ker`h'_w1 > 0) if !missing(Ker`h'_w1)
    gen double lnKer`h'_w1    = ln(1 + Ker`h'_w1)

    * wvol
    cap drop Ker`h'_wvol_pos lnKer`h'_wvol
    gen byte   Ker`h'_wvol_pos = (Ker`h'_wvol > 0) if !missing(Ker`h'_wvol)
    gen double lnKer`h'_wvol    = ln(1 + Ker`h'_wvol)

    * wrr
    cap drop Ker`h'_wrr_pos lnKer`h'_wrr
    gen byte   Ker`h'_wrr_pos = (Ker`h'_wrr > 0) if !missing(Ker`h'_wrr)
    gen double lnKer`h'_wrr    = ln(1 + Ker`h'_wrr)
}

keep iddesa D_v A_v_log A_v_inv ///
    C*_w1 C*_wvol C*_wrr ///
    Ker*_w1 Ker*_wvol Ker*_wrr ///
    Ker*_w1_pos Ker*_wvol_pos Ker*_wrr_pos ///
    lnKer*_w1 lnKer*_wvol lnKer*_wrr
save `vill_exposure', replace

use `vill_exposure', clear
keep iddesa D_v A_v_log A_v_inv ///
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

/****************************************************************************************
H. PODES ONLY: PCA-ready categorical/ordinal outcome construction
****************************************************************************************/

* --------------------------------------------------------------------------------------
* 0) SPBUN-target label (full sample; no filtering)
* --------------------------------------------------------------------------------------
cap drop spbun_target
gen byte spbun_target = 0
foreach v in r308b1a r308b1b r308b1c {
    cap confirm numeric variable `v'
    if !_rc replace spbun_target = 1 if `v'==1
}
label define spbun_target_lbl 0 "Non-target" 1 "Target (tangkap/budidaya/garam)", replace
label values spbun_target spbun_target_lbl

* --------------------------------------------------------------------------------------
* 1) Helpers
* --------------------------------------------------------------------------------------

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



* --------------------------------------------------------------------------------------
* 2) Wbasic: basic facilities (categorical/ordinal inputs)
* --------------------------------------------------------------------------------------

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


* --------------------------------------------------------------------------------------
* 3) Util: utilities / infra
* --------------------------------------------------------------------------------------

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

* --------------------------------------------------------------------------------------
* 4) Edu: education
* --------------------------------------------------------------------------------------
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

* --------------------------------------------------------------------------------------
* 5) Hlth: health
* --------------------------------------------------------------------------------------
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

* --------------------------------------------------------------------------------------
* 6) Poverty proxy (keep separate)
* --------------------------------------------------------------------------------------
cap drop lnpov
cap confirm numeric variable r710
if !_rc {
    gen double lnpov = ln(1+r710) if !missing(r710)
    cap drop lnpov_b
    _bin0q4 lnpov, gen(lnpov_b)
}

* --------------------------------------------------------------------------------------
* 7) PCA (1 component each) + z-score
* --------------------------------------------------------------------------------------
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

/****************************************************************************************
I. MODEL BLOCK 
****************************************************************************************/

* ------------------------------------------------------------
* 0) Ensure kab exists (same convention as Analysis1)
* ------------------------------------------------------------
cap confirm variable kab
if _rc {
    cap confirm numeric variable r101
    cap confirm numeric variable r102
    if !_rc egen long kab = group(r101 r102), label
}

* ------------------------------------------------------------
* 0b) Standardize cluster id: nama_kab (numeric)
* ------------------------------------------------------------
cap confirm variable nama_kab
if _rc {
    * If nama_kab not present, fall back to kab grouping
    cap confirm variable kab
    if !_rc gen long nama_kab = kab
}

cap confirm variable nama_kab
if !_rc {
    cap confirm numeric variable nama_kab
    if _rc {
        encode nama_kab, gen(__nama_kab_id)
        drop nama_kab
        rename __nama_kab_id nama_kab
    }
}

* One convention everywhere
global CL "nama_kab"

* ------------------------------------------------------------
* 1) Heterogeneity flag (same as Analysis1)
* ------------------------------------------------------------
cap drop Coast Fish_strict Fish_loose

cap confirm numeric variable r308a
if !_rc gen byte Coast = (r308a==1) if !missing(r308a)
else gen byte Coast = .

gen byte Fish_strict = .
cap confirm numeric variable r308b1a
cap confirm numeric variable r308b1b
if !_rc replace Fish_strict = (Coast==1) & (r308b1a==1 | r308b1b==1) if !missing(Coast)

gen byte Fish_loose = .
cap confirm numeric variable r308b1c
cap confirm numeric variable r308b1d
cap confirm numeric variable r308b1e
if !_rc replace Fish_loose = (Coast==1) | (r308b1a==1 | r308b1b==1 | r308b1c==1 | r308b1d==1 | r308b1e==1) if !missing(Coast)

* ------------------------------------------------------------
* 2) Controls (same as Analysis1)
* ------------------------------------------------------------
* NOTE: use factor-variable notation for categorical PODES controls
* Only keep continuous variables as c.var (default if numeric)

local Xgeo ""
foreach v in r308a r308b1a r308b1b r308b1c r308b1d r308b1e {
    cap confirm variable `v'
    if !_rc local Xgeo "`Xgeo' i.`v'"
}

local Xenv ""
foreach v in r309a r309b r309d r309e r310 {
    cap confirm variable `v'
    if !_rc local Xenv "`Xenv' i.`v'"
}
cap confirm variable r309c_cat
if !_rc local Xenv "`Xenv' i.r309c_cat"

local Xecon ""
foreach v in r403a r403c1 r403c2 {
    cap confirm variable `v'
    if !_rc local Xecon "`Xecon' i.`v'"
}
cap confirm variable r105
if !_rc local Xecon "`Xecon' c.r105"

local Xv "`Xgeo' `Xenv' `Xecon'"

* ------------------------------------------------------------
* 3) Treatment (main)
* ------------------------------------------------------------
local Tv "A_v_log"

* ------------------------------------------------------------
* 4) Village-level baseline models (same as Analysis1)
* ------------------------------------------------------------
estimates clear
local EST_MAIN ""

cap confirm variable Wbasic_z
if !_rc {
    cap noisily reghdfe Wbasic_z `Tv' `Xv', absorb($CL) vce(cluster $CL)
    if !_rc { estimates store rq1; local EST_MAIN "`EST_MAIN' rq1" }
}

cap confirm variable lnpov
if !_rc {
    cap noisily reghdfe lnpov `Tv' `Xv', absorb($CL) vce(cluster $CL)
    if !_rc { estimates store rq2; local EST_MAIN "`EST_MAIN' rq2" }
}

cap confirm variable Util_z
if !_rc {
    cap noisily reghdfe Util_z `Tv' `Xv', absorb($CL) vce(cluster $CL)
    if !_rc { estimates store rq5; local EST_MAIN "`EST_MAIN' rq5" }
}

cap confirm variable Edu_z
if !_rc {
    cap noisily reghdfe Edu_z `Tv' `Xv', absorb($CL) vce(cluster $CL)
    if !_rc { estimates store rq6; local EST_MAIN "`EST_MAIN' rq6" }
}

cap confirm variable Hlth_z
if !_rc {
    cap noisily reghdfe Hlth_z `Tv' `Xv', absorb($CL) vce(cluster $CL)
    if !_rc { estimates store rq7; local EST_MAIN "`EST_MAIN' rq7" }
}

* Optional heterogeneity (only if Fish_strict exists)
cap confirm variable Fish_strict
if !_rc {
    cap confirm variable Wbasic_z
    if !_rc {
        cap noisily reghdfe Wbasic_z c.`Tv'##i.Fish_strict `Xv', absorb($CL) vce(cluster $CL)
        if !_rc estimates store rq1_het
    }
}

********************************************************************************
* 5) Household-level models 
********************************************************************************
local Tk_base "VolumePerHH_k"
local Zh "HHSize Urban"
cap confirm variable HHSize
if _rc local Zh : subinstr local Zh "HHSize" "", all
cap confirm variable Urban
if _rc local Zh : subinstr local Zh "Urban" "", all

cap confirm numeric variable `Tk_base'
if !_rc {

    cap confirm variable lnGas
    if !_rc {
        cap noisily reghdfe lnGas `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster $CL)
        if !_rc estimates store rq10_gas
    }

    cap confirm variable lnSolar
    if !_rc {
        cap noisily reghdfe lnSolar `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster $CL)
        if !_rc estimates store rq10_solar
    }

    cap confirm variable lnNonFoodPC
    if !_rc {
        cap noisily reghdfe lnNonFoodPC `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster $CL)
        if !_rc estimates store rq11
    }

    foreach y in ln_kalori_kap ln_prote_kap ln_lemak_kap ln_karbo_kap {
        cap confirm variable `y'
        if !_rc {
            cap noisily reghdfe `y' `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster $CL)
            if !_rc estimates store rq12_`y'
        }
    }
}

********************************************************************************
* 6) Robustness grids (village): for ALL outcomes, across exposure definitions
********************************************************************************
local exposures "A_v_log C5_w1 C10_w1 C15_w1 Ker5_w1 Ker10_w1 Ker20_w1"
local outcomes  "Wbasic_z Util_z Edu_z Hlth_z lnpov"

foreach y of local outcomes {
    cap confirm variable `y'
    if !_rc {

        foreach T of local exposures {
            cap confirm numeric variable `T'
            if !_rc {
                cap noisily reghdfe `y' `T' `Xv', absorb($CL) vce(cluster $CL)
                if !_rc estimates store rb_`y'_`T'
            }
        }

    }
}

****************************************************************************************
* OUTPUT TABLES: robustness tables per outcome (treatment-only rows)
****************************************************************************************
cap which esttab
if _rc ssc install estout, replace

foreach y of local outcomes {

    local RBLIST ""
    foreach T of local exposures {
        cap estimates describe rb_`y'_`T'
        if !_rc local RBLIST "`RBLIST' rb_`y'_`T'"
    }

    di as txt "`y' RBLIST = `RBLIST'"

    if "`RBLIST'" != "" {
		* NOTE: with factor-variable controls (i.var), coefficient names become 1.var, 2.var, ...
		* To keep tables stable, report treatment coefficients only.
		cap noisily esttab `RBLIST' using "$outdir/results_robust_`y'.rtf", replace ///
			keep(`exposures') order(`exposures') ///
			b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
			stats(N r2_a, labels("N" "Adj. R2")) ///
			compress nogaps varwidth(24) modelwidth(12)
    }
}

*keep(`exposures' `Xv') order(`exposures' `Xv')

****************************************************************************************
* 7) Nonparametric screening (distributional targeting evidence)
*    - Bivariate only; not causal. Output logged to Output folder.
****************************************************************************************

cap log close _all
log using "$outdir/nonparametric_screening_analysis2.trf", replace text

* Binary exposure based on Ker5_w1 (if available)
cap confirm variable Ker5_w1
if !_rc {
    cap drop S_k5
    gen byte S_k5 = (Ker5_w1 > 0) if !missing(Ker5_w1)
    label define S_k5_lab 0 "No SPBUN exposure" 1 "Has SPBUN exposure", replace
    label values S_k5 S_k5_lab

    * Welfare outcomes (village)
    local welfare "lnpov Wbasic_z Util_z Edu_z Hlth_z"

    foreach y of local welfare {
        cap confirm variable `y'
        if !_rc {
            di as txt "---- ranksum: `y' by S_k5 ----"
            cap noisily ranksum `y', by(S_k5)
        }
    }

    * Placement covariates: chi-square association with exposure
    local placecats "r308a r308b1a r308b1b r308b1c r308b1d r308b1e r309a r309b r309d r309e r310 r403a r403c1 r403c2 r101"
    foreach v of local placecats {
        cap confirm variable `v'
        if !_rc {
            di as txt "---- chi2: `v' x S_k5 ----"
            cap noisily tab `v' S_k5, chi2 row col
        }
    }
}
else {
    di as error "Ker5_w1 not found; skipping nonparametric screening."
}

log close
