/****************************************************************************************
SPBUN (SPBU Nelayan) exposure → welfare outcomes (PODES village + SUSENAS household)
Baseline: SPBUN only (extend later for SPBU / SPBUN+SPBU)

Disusun oleh: Atha (PSE)
Tujuan: Analisis #3
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
I. PROBABILISTIC MODELS (TARGETING / UTILIZATION) -- NO BRACES, SEPARATION-SAFE
****************************************************************************************/

* --------------------
* 0) Radius
* --------------------
local R 10

* Exposure variants (borrowed from SPBUN-Analysis2 naming):
* - A_v_log  : -ln(1 + D_v) so higher = closer (recommended distance metric)
* - C5_w1    : count/weight of SPBUN within 5 km
* - C10_w1   : count/weight within 10 km
* - C15_w1   : count/weight within 15 km
* - Ker5_w1  : kernel-weighted exposure with bandwidth 5 km (exp(-d/5))
* - Ker10_w1 : kernel-weighted exposure with bandwidth 10 km (exp(-d/10))
* - Ker20_w1 : kernel-weighted exposure with bandwidth 20 km (exp(-d/20))
* Choose which ones to use in Model 1 (edit these locals only):
local EXP_DIST   "A_v_log"
local EXP_COUNT  "C10_w1"
local EXP_KERNEL "Ker10_w1"
local EXPOSURES  "A_v_log C5_w1 C10_w1 C15_w1 Ker5_w1_pos Ker10_w1_pos"

* --------------------
* 1) Target combo outcome (bitmask) + collapsed multinomial for stability
* --------------------
cap drop tg_tangkap tg_budidaya tg_garam y_combo y_any y_combo3
gen byte tg_tangkap  = .
gen byte tg_budidaya = .
gen byte tg_garam    = .

cap confirm numeric variable r308b1a
if _rc==0 replace tg_tangkap  = (r308b1a==1) if !missing(r308b1a)

cap confirm numeric variable r308b1b
if _rc==0 replace tg_budidaya = (r308b1b==1) if !missing(r308b1b)

cap confirm numeric variable r308b1c
if _rc==0 replace tg_garam    = (r308b1c==1) if !missing(r308b1c)

gen byte y_combo = tg_tangkap + 2*tg_budidaya + 4*tg_garam if ///
    !missing(tg_tangkap) & !missing(tg_budidaya) & !missing(tg_garam)

label define y_combo_lbl 0 "None" 1 "Tangkap" 2 "Budidaya" 3 "Tangkap+Budidaya" ///
                       4 "Tambak garam" 5 "Tangkap+Garam" 6 "Budidaya+Garam" ///
                       7 "Tangkap+Budidaya+Garam", replace
label values y_combo y_combo_lbl

gen byte y_any = (y_combo>0) if !missing(y_combo)
label define y_any_lbl 0 "Non-target" 1 "Target", replace
label values y_any y_any_lbl

* Collapse to reduce sparse-category instability for mlogit:
* 0=None, 1=Tangkap-only, 2=Tangkap+Budidaya 3=Other/mixed (any budidaya/garam or mixed)
gen byte y_combo3 = .
replace y_combo3 = 0 if y_combo==0
replace y_combo3 = 1 if y_combo==1
replace y_combo3 = 2 if y_combo==3
replace y_combo3 = 3 if inlist(y_combo,2,4,5,6,7)
label define y_combo3_lbl 0 "None" 1 "Tangkap-only" 2 "Tangkap+Budidaya" 3 "Other/mixed", replace
label values y_combo3 y_combo3_lbl

* --------------------
* 2) Utilization outcome: DO NOT overwrite r308a; build r308a_bin safely
* --------------------
cap drop r308a_bin y_use
gen byte r308a_bin = .
cap confirm numeric variable r308a
if _rc==0 {
    quietly summarize r308a if !missing(r308a), meanonly
    if (r(min)>=1 & r(max)<=2) replace r308a_bin = (r308a==1) if inlist(r308a,1,2)
    else replace r308a_bin = r308a if inlist(r308a,0,1)
}
gen byte y_use = r308a_bin if inlist(r308a_bin,0,1)
label define y_use_lbl 0 "No" 1 "Yes", replace
label values y_use y_use_lbl

* --------------------
* 3) SPBUN access: build VARIANTS (OR), not all at once
* --------------------
local Xspbun_dist ""
cap confirm numeric variable `EXP_DIST'
if _rc==0 local Xspbun_dist "c.`EXP_DIST'"
else {
    * Fallback if chosen EXP_DIST is unavailable
    cap confirm numeric variable D_v
    if _rc==0 local Xspbun_dist "c.D_v"
}

local Xspbun_count ""
cap confirm numeric variable `EXP_COUNT'
if _rc==0 local Xspbun_count "c.`EXP_COUNT'"
else {
    * Fallback to radius-count exposure
    cap confirm numeric variable C`R'_w1
    if _rc==0 local Xspbun_count "c.C`R'_w1"
}

local Xspbun_kernel ""
cap confirm numeric variable `EXP_KERNEL'
if _rc==0 local Xspbun_kernel "c.`EXP_KERNEL'"

* Treatment = any SPBUN within R
cap drop T_spbun_inR
gen byte T_spbun_inR = .
cap confirm numeric variable C`R'_w1
if _rc==0 replace T_spbun_inR = (C`R'_w1>0) if !missing(C`R'_w1)
label define T_spbun_inR_lbl 0 "No SPBUN within R" 1 ">=1 SPBUN within R", replace
label values T_spbun_inR T_spbun_inR_lbl

* --------------------
* 4) PCA blocks 
* --------------------
local Xpca ""
foreach v in Wbasic_z Edu_z Hlth_z lnpov Util_z {
    cap confirm numeric variable `v'
    if _rc==0 local Xpca "`Xpca' c.`v'"
}

* --------------------
* 5) Controls (IMPORTANT: exclude r308a/r308a_bin from RHS for y_any/y_use)
* --------------------
local Xctrl ""
foreach v in r308b1d r308b1e r309a r309b r309d r309e r310 r403a r403c1 r403c2 r105 {
    cap confirm numeric variable `v'
    if _rc==0 local Xctrl "`Xctrl' c.`v'"
}

cap confirm variable r309c_cat
if _rc==0 local Xctrl "`Xctrl' i.r309c_cat"

// * --------------------
// * 6) Model 1: Access-driven (run distance-variant and count-variant separately)
// * --------------------
// estimates clear
// local EST_PROB ""
//
// * (A) mlogit on collapsed outcome for stability
// cap noisily mlogit y_combo3 `Xspbun_dist' `Xpca' `Xctrl', baseoutcome(0) vce(cluster kab)
// if _rc==0 { estimates store m1_mlogit3_dist; local EST_PROB "`EST_PROB' m1_mlogit3_dist" }
//
// cap noisily mlogit y_combo3 `Xspbun_count' `Xpca' `Xctrl', baseoutcome(0) vce(cluster kab)
// if _rc==0 { estimates store m1_mlogit3_count; local EST_PROB "`EST_PROB' m1_mlogit3_count" }
//
// * (B) y_any: restrict to coastal sample to avoid separation (if r308a_bin exists)
// local IFCOAST ""
// cap confirm numeric variable r308a_bin
// if _rc==0 local IFCOAST "if r308a_bin==1"
//
// cap noisily logit  y_any `Xspbun_dist' `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
// if _rc==0 { estimates store m1_logit_any_dist; local EST_PROB "`EST_PROB' m1_logit_any_dist" }
//
// cap noisily probit y_any `Xspbun_dist' `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
// if _rc==0 { estimates store m1_probit_any_dist; local EST_PROB "`EST_PROB' m1_probit_any_dist" }
//
// cap noisily logit  y_any `Xspbun_count' `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
// if _rc==0 { estimates store m1_logit_any_count; local EST_PROB "`EST_PROB' m1_logit_any_count" }
//
// cap noisily probit y_any `Xspbun_count' `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
// if _rc==0 { estimates store m1_probit_any_count; local EST_PROB "`EST_PROB' m1_probit_any_count" }
//
// * (C) y_use: ONLY if y_use exists and has variation; do NOT include r308a on RHS
// cap confirm numeric variable y_use
// if _rc==0 {
//     quietly tab y_use, missing
//     cap noisily logit  y_use `Xspbun_dist' `Xpca' `Xctrl', vce(cluster kab)
//     if _rc==0 { estimates store m1_logit_use_dist; local EST_PROB "`EST_PROB' m1_logit_use_dist" }
//
//     cap noisily logit  y_use `Xspbun_count' `Xpca' `Xctrl', vce(cluster kab)
//     if _rc==0 { estimates store m1_logit_use_count; local EST_PROB "`EST_PROB' m1_logit_use_count" }
// }
//
// cap noi logit y_any `Xspbun_dist' `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
// if _rc==0 estimates store m1_logit_any_dist
//
// * --------------------
// * 7) Model 2: mlogit for PCA baseline
// * --------------------
// // cap drop Env_pca1 Env_z
// cap noisily pca r309a r309b r309d r309e r310, components(1) correlation
// local rc_pca = _rc
// // if `rc_pca'==0 cap predict double Env_pca1 if e(sample), score
// // if `rc_pca'==0 egen double Env_z = std(Env_pca1)
//
// // cap confirm numeric variable Env
// if _rc==0 {
//     cap noisily logit y_any `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
//     if _rc==0 { estimates store m2_logit_any_env; local EST_PROB "`EST_PROB' m2_logit_any_env" }
//
//     cap noisily mlogit y_combo3 `Xpca' `Xctrl', baseoutcome(0) vce(cluster kab)
//     if _rc==0 { estimates store m2_mlogit3_env; local EST_PROB "`EST_PROB' m2_mlogit3_env" }
// }
// * Excluded:
// * - c.Env_z
//
// cap noi probit y_any `Xspbun_dist' `Xpca' `Xctrl' `IFCOAST', vce(cluster kab)
// if _rc==0 estimates store m1_probit_any_dist
//
* --------------------
* 8) Model 3: Hurdle (treatment then outcome among treated) + welfare impact
* --------------------

* Base output + subfolders
* Mohon '...' diganti menyesuaikan path anda
local outbase "..."
local out_hurdle "`outbase'/hurdle"
local out_np     "`outbase'/non-param"
capture mkdir "`outbase'"
capture mkdir "`out_hurdle'"
capture mkdir "`out_np'"

* Core sets
global Xpca        "Wbasic_z lnpov Edu_z Hlth_z Util_z"
global Xctrl       "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2"
global Xspbun_dist "C5_w1 C10_w1 C15_w1"

* Cluster id
global CL "nama_kab"

* (A) Ensure hurdle components exist
// cap confirm variable Ker5_w1
// if _rc {
//     di as error "Ker5_w1 not found."
//     exit 198
// }
//
// cap confirm variable S_k5
// if _rc {
//     gen byte S_k5 = (Ker5_w1 > 0) if !missing(Ker5_w1)
//     label var S_k5 "Hurdle selection: Ker5_w1>0"
// }
//
// cap confirm variable lnKer5_w1
// if _rc {
//     gen double lnKer5_w1 = ln(1 + Ker5_w1) if !missing(Ker5_w1)
//     label var lnKer5_w1 "ln(1+Ker5_w1)"
// }
//
// cap noisily tab S_k5
// cap noisily summ Ker5_w1 lnKer5_w1, detail


* (B) Hurdle + two-part + welfare impact
// cap log close _all
// log using "`out_hurdle'/model3_hurdle_master.log", replace text
//
// churdle exponential Ker5_w1 ///
//     Wbasic_z lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl, ///
//     select($Xctrl i.y_combo3 i.r101) ll(0)
// estimates store HURDLE_exp_K5
//
// logit S_k5 ///
//     $Xctrl i.y_combo3 i.r101, vce(cluster $CL)
// estimates store TP_A_logit_Sk5
//
// cap drop phat_k5
// predict double phat_k5, pr
//
// reg lnKer5_w1 ///
//     Wbasic_z lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl if S_k5==1, vce(cluster $CL)
// estimates store TP_B_lnint_k5
//
// reg Wbasic_z ///
//     lnKer5_w1 lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store IMPACT_RF_Wbasic_lnK5
//
// reg Wbasic_z ///
//     Ker5_w1 lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store IMPACT_RF_Wbasic_K5
//
// reg Ker5_w1 ///
//     Wbasic_z lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store IMPACT_RF_Wbasic_K5
//
// reg lnKer5_w1 ///
//     $Xctrl i.y_combo3 i.r101, vce(cluster $CL)
// estimates store CF_FS_lnK5
//
// cap drop uhat_lnK5
// predict double uhat_lnK5, resid
//
// reg Wbasic_z ///
//     lnKer5_w1 uhat_lnK5 lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store CF_SS_Wbasic_lnK5
//
// reg lnKer5_w1 ///
//     Wbasic_z uhat_lnK5 lnpov Edu_z Hlth_z i.y_combo3 i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store CF_SS_Wbasic_lnK5
//
// reg Wbasic_z ///
//     c.lnKer5_w1##i.y_combo3 lnpov Edu_z Hlth_z i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store HET_Wbasic_lnK5
//
// reg c.lnKer5_w1##i.y_combo3 ///
//     Wbasic_z lnpov Edu_z Hlth_z i.r101 ///
//     $Xctrl, vce(cluster $CL)
// estimates store HET_Wbasic_lnK5
//
// margins y_combo3, dydx(lnKer5_w1)
//
// foreach T in Wbasic_z lnpov Edu_z Hlth_z {
//     reg  Ker5_w1 ///
//         `T' i.y_combo3 i.r101 ///
//         $Xctrl, vce(cluster $CL)
//     estimates store IMPACT_RF_`T'
// }
//
// log close

* --------------- BLOCK PRE-CHURDLE MODELS ----------------
cap confirm local out_hurdle
* Mohon '...' diganti menyesuaikan path anda
if _rc local out_hurdle "..."

local basepre "lnpov"
local PCA_FULL "Edu_z Wbasic_z Hlth_z Util_z"

local PRELIST PRE0 PRE_S1 PRE_S2 PRE_S3 PRE_S4 ///
             PRE_P12 PRE_P13 PRE_P14 PRE_P23 PRE_P24 PRE_P34 ///
             PRE_T123 PRE_T124 PRE_T134 PRE_T234 ///
             PRE_ALL

local PRE0 "`basepre'"

local PRE_S1 "`basepre' Edu_z"
local PRE_S2 "`basepre' Wbasic_z"
local PRE_S3 "`basepre' Hlth_z"
local PRE_S4 "`basepre' Util_z"

local PRE_P12 "`basepre' Edu_z Wbasic_z"
local PRE_P13 "`basepre' Edu_z Hlth_z"
local PRE_P14 "`basepre' Edu_z Util_z"
local PRE_P23 "`basepre' Wbasic_z Hlth_z"
local PRE_P24 "`basepre' Wbasic_z Util_z"
local PRE_P34 "`basepre' Hlth_z Util_z"

local PRE_T123 "`basepre' Edu_z Wbasic_z Hlth_z"
local PRE_T124 "`basepre' Edu_z Wbasic_z Util_z"
local PRE_T134 "`basepre' Edu_z Hlth_z Util_z"
local PRE_T234 "`basepre' Wbasic_z Hlth_z Util_z"

local PRE_ALL "`basepre' `PCA_FULL'"

* ---- ONE BIG LOG FOR CHURDLE GRID RUNS ----
cap log close _all
local biglog "`out_hurdle'/CHURDLE_GRID_ALL.log"
log using "`biglog'", replace text
di as txt "==== START CHURDLE GRID RUN: `c(current_date)' `c(current_time)' ===="

* BLOCK 1.1.1: Exploratory churdle grid (vary specs) - Exponential
local dep_hurdle "Ker5_w1"

local selbase "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2"
local addsel  "i.y_combo3 i.r101"
local ll      0

local SEL1 "`selbase'"
local SEL2 "`selbase' `addsel'"
local SEL3 "`selbase' `basepre'"
local SEL4 "`selbase' `PCA_FULL'"

capture postutil clear
tempname P0
tempfile churdle_results11_pca
postfile `P0' str12 dep str40 pretag str200 pre str40 seltag str300 sel double llf int rc using `churdle_results11_pca', replace

foreach y of local dep_hurdle {
    cap confirm variable `y'
    if _rc continue

    foreach pretag of local PRELIST {
        local preX ``pretag''
        local ptag = subinstr("`pretag'","PRE_","",.)

        foreach seltag in SEL1 SEL2 SEL3 SEL4 {
            local selX ``seltag''
            local stag = subinstr("`seltag'","SEL","S",.)

            local preLab = cond("`preX'"=="","(none)","`preX'")
            local selLab = cond("`selX'"=="","(none)","`selX'")

            di as txt "---- [EXP] y=`y' pretag=`pretag' seltag=`seltag' ----"
            di as txt "RUN: churdle exponential `y' `preLab', select(`selLab') ll(`ll')"
            capture noisily churdle exponential `y' `preX', select(`selX') ll(`ll')
            local rc = _rc

            if `rc'==0 {
                quietly scalar __ll = e(ll)
                post `P0' ("`y'") ("`pretag'") ("`preLab'") ("`seltag'") ("`selLab'") (__ll) (`rc')

                local ytag = substr("`y'",1,6)
                local estname "CHX_`ytag'_`ptag'_`stag'"
                cap estimates drop `estname'
                estimates store `estname'
            }
            else {
                post `P0' ("`y'") ("`pretag'") ("`preLab'") ("`seltag'") ("`selLab'") (.) (`rc')
                di as error "FAILED (rc=`rc')"
            }

            di as txt ""
        }
    }
}
postclose `P0'

* BLOCK 1.1.2: Exploratory churdle grid (vary specs) - Lognormal
local dep_hurdle "Ker5_w1"
local basepre   "lnpov"
local addpre    "Edu_z Wbasic_z Hlth_z Util_z"
local selbase   "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2"
local addsel    "i.y_combo3 i.r101"
local ll        0

capture postutil clear
tempname P1
tempfile churdle_results12
postfile `P1' str12 dep str80 pre str120 sel double llf int rc using `churdle_results12', replace

foreach y of local dep_hurdle {
    cap confirm variable `y'
    if _rc continue

    local PRE1 "`basepre' `addpre'"
    local PRE2 "`basepre'"
    local PRE3 "`addpre'"
    local PRE4 ""

    local SEL1 "`selbase'"
    local SEL2 "`selbase' `addsel'"
    local SEL3 "`selbase' `basepre'"
    local SEL4 "`selbase' `addpre'"

    foreach pretag in PRE1 PRE2 PRE3 PRE4 {
        local preX ``pretag''
        local ptag = subinstr("`pretag'","PRE","P",.)    // PRE1->P1 etc

        foreach seltag in SEL1 SEL2 SEL3 SEL4 {
            local selX ``seltag''
            local stag = subinstr("`seltag'","SEL","S",.)

            local preLab = cond("`preX'"=="","(none)","`preX'")
            local selLab = cond("`selX'"=="","(none)","`selX'")

            di as txt "---- [LN] y=`y' pretag=`pretag' seltag=`seltag' ----"
            di as txt "RUN: churdle lognormal `y' `preLab', select(`selLab') ll(`ll')"
            capture noisily churdle lognormal `y' `preX', select(`selX') ll(`ll')
            local rc = _rc

            if `rc'==0 {
                quietly scalar __ll = e(ll)
                post `P1' ("`y'") ("`preLab'") ("`selLab'") (__ll) (`rc')

                local ytag = substr("`y'",1,6)
                local estname "CHN_`ytag'_`ptag'_`stag'"
                cap estimates drop `estname'
                estimates store `estname'
            }
            else {
                post `P1' ("`y'") ("`preLab'") ("`selLab'") (.) (`rc')
                di as error "FAILED (rc=`rc')"
            }

            di as txt ""
        }
    }
}
postclose `P1'

* BLOCK 1.2.1: Exploratory welfare churdle grid - Exponential
local dep_welfare "Edu_z Wbasic_z Hlth_z Util_z lnpov"
local basepres "Ker5_w1"
local controls "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2 i.y_combo3 i.r101"
local vceopt "vce(cluster $CL)"
local ll 0

capture postutil clear
tempname P2
tempfile churdle_results21
postfile `P2' str12 dep str24 seldep str200 pre str200 sel double llf int rc using `churdle_results21', replace

foreach y of local dep_welfare {
    cap confirm variable `y'
    if _rc continue

    quietly count if !missing(`y')
    if r(N)<5 continue

    foreach bp of local basepres {
        cap confirm variable `bp'
        if _rc continue

        local preX "`bp' `controls'"
        local selX "`controls'"

        di as txt "---- [WELF EXP] y=`y' seldep=`bp' ----"
        di as txt "RUN: churdle exponential `y' `preX', select(`bp' = `selX') ll(`ll') `vceopt'"
        capture noisily churdle exponential `y' `preX', select(`bp' = `selX') ll(`ll') `vceopt'
        local rc = _rc

        if `rc'==0 {
            quietly scalar __ll = e(ll)
            post `P2' ("`y'") ("`bp'") ("`preX'") ("`selX'") (__ll) (`rc')

            local ytag = substr("`y'",1,6)
            local bptag = substr("`bp'",1,6)
            local estname "CHWEX_`ytag'_`bptag'"
            cap estimates drop `estname'
            estimates store `estname'
        }
        else {
            post `P2' ("`y'") ("`bp'") ("`preX'") ("`selX'") (.) (`rc')
            di as error "FAILED (rc=`rc')"
        }

        di as txt ""
    }
}
postclose `P2'

* BLOCK 1.2.2: Exploratory welfare churdle grid - Lognormal
local dep_welfare "Edu_z Wbasic_z Hlth_z Util_z lnpov"
local basepres "Ker5_w1"
local controls "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2 i.y_combo3 i.r101"
local vceopt "vce(cluster $CL)"
local ll 0

capture postutil clear
tempname P3
tempfile churdle_results22
postfile `P3' str12 dep str24 seldep str200 pre str200 sel double llf int rc using `churdle_results22', replace

foreach y of local dep_welfare {
    cap confirm variable `y'
    if _rc continue

    quietly count if !missing(`y')
    if r(N)<5 continue

    foreach bp of local basepres {
        cap confirm variable `bp'
        if _rc continue

        local preX "`bp' `controls'"
        local selX "`controls'"

        di as txt "---- [WELF LN] y=`y' seldep=`bp' ----"
        di as txt "RUN: churdle lognormal `y' `preX', select(`bp' = `selX') ll(`ll') `vceopt'"
        capture noisily churdle lognormal `y' `preX', select(`bp' = `selX') ll(`ll') `vceopt'
        local rc = _rc

        if `rc'==0 {
            quietly scalar __ll = e(ll)
            post `P3' ("`y'") ("`bp'") ("`preX'") ("`selX'") (__ll) (`rc')

            local ytag = substr("`y'",1,6)
            local bptag = substr("`bp'",1,6)
            local estname "CHWLN_`ytag'_`bptag'"
            cap estimates drop `estname'
            estimates store `estname'
        }
        else {
            post `P3' ("`y'") ("`bp'") ("`preX'") ("`selX'") (.) (`rc')
            di as error "FAILED (rc=`rc')"
        }

        di as txt ""
    }
}
postclose `P3'

di as txt "==== END CHURDLE GRID RUN: `c(current_date)' `c(current_time)' ===="
log close


* ---------------- BIG LOG FOR OLS GRIDS (BLOCK 2.x) ----------------
cap log close _all
local biglog_ols "`out_hurdle'/OLS_GRID_ALL.log"
log using "`biglog_ols'", replace text
di as txt "==== START OLS GRID RUN: `c(current_date)' `c(current_time)' ===="

* BLOCK 2.1: Exploratory welfare prediction grid (Z-INDICES)
local dep_welfare "Edu_z Wbasic_z Hlth_z Util_z lnpov"
local basepres "Ker5_w1"
local controls "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2 i.y_combo3 i.r101"
local vceopt "vce(cluster $CL)"

capture postutil clear
tempname P4
tempfile ols_results1
postfile `P4' str12 dep str24 basepre str200 rhs double r2 int rc using `ols_results1', replace

foreach y of local dep_welfare {
    cap confirm variable `y'
    if _rc continue

    foreach bp of local basepres {
        cap confirm variable `bp'
        if _rc continue

        local rhs "`bp' `controls'"

        di as txt "---- [OLS 2.1] dep=`y' basepre=`bp' ----"
        di as txt "RUN: reg `y' `rhs', `vceopt'"
        capture noisily reg `y' `rhs', `vceopt'
        local rc = _rc

        if `rc'==0 {
            post `P4' ("`y'") ("`bp'") ("`rhs'") (e(r2)) (`rc')

            local ytag = substr("`y'",1,6)
            local bptag = substr("`bp'",1,6)
            local estname "OLS1_`ytag'_`bptag'"
            cap estimates drop `estname'
            estimates store `estname'
        }
        else {
            post `P4' ("`y'") ("`bp'") ("`rhs'") (.) (`rc')
            di as error "FAILED (rc=`rc')"
        }

        di as txt ""
    }
}
postclose `P4'

* BLOCK 2.2: Exploratory prediction grid (PCA-style RHS combos)
local dep_ols "Ker5_w1"

local selbase "i.r308b1d i.r308b1e i.r309a i.r309b i.r309d i.r309e i.r310 i.r403a i.r403c1 i.r403c2"
local addsel  "i.y_combo3 i.r101"
local vceopt  "vce(cluster $CL)"

local SEL1 "`selbase'"
local SEL2 "`selbase' `addsel'"
local SEL3 "`selbase' `basepre'"
local SEL4 "`selbase' `PCA_FULL'"

capture postutil clear
tempname P5
tempfile ols_results2_pca
postfile `P5' str12 dep str40 pretag str200 pre str40 seltag str300 sel str400 rhs double r2 int rc using `ols_results2_pca', replace

foreach y of local dep_ols {
    cap confirm variable `y'
    if _rc continue

    foreach pretag of local PRELIST {
        local preX ``pretag''
        local ptag = subinstr("`pretag'","PRE_","",.)

        foreach seltag in SEL1 SEL2 SEL3 SEL4 {
            local selX ``seltag''
            local stag = subinstr("`seltag'","SEL","S",.)

            local rhs "`preX' `selX'"
            local preLab = cond("`preX'"=="","(none)","`preX'")
            local selLab = cond("`selX'"=="","(none)","`selX'")

            di as txt "---- [OLS 2.2] dep=`y' pretag=`pretag' seltag=`seltag' ----"
            di as txt "RUN: reg `y' `rhs', `vceopt'"
            capture noisily reg `y' `rhs', `vceopt'
            local rc = _rc

            if `rc'==0 {
                post `P5' ("`y'") ("`pretag'") ("`preLab'") ("`seltag'") ("`selLab'") ("`rhs'") (e(r2)) (`rc')

                local ytag = substr("`y'",1,6)
                local estname "OLS2_`ytag'_`ptag'_`stag'"
                cap estimates drop `estname'
                estimates store `estname'
            }
            else {
                post `P5' ("`y'") ("`pretag'") ("`preLab'") ("`seltag'") ("`selLab'") ("`rhs'") (.) (`rc')
                di as error "FAILED (rc=`rc')"
            }

            di as txt ""
        }
    }
}
postclose `P5'

di as txt "==== END OLS GRID RUN: `c(current_date)' `c(current_time)' ===="
log close




// * --------------------
// * 9) Nonparametric tests -> MASTER LOG -> LOG file in non-param folder
// * --------------------
// cap log close _all
// log using "nonparametric_tests_master.log", replace text
//
// cap confirm variable Ker5_w1
// if _rc {
//     di as error "Ker5_w1 not found. Cannot run nonparam tests."
//     log close
//     exit 198
// }
//
// cap drop S_k5
// gen byte S_k5 = (Ker5_w1 > 0) if !missing(Ker5_w1)
// label var S_k5 "Exposed: Ker5_w1>0"
// label define S_k5_lab 0 "No SPBUN exposure" 1 "Has SPBUN exposure", replace
// label values S_k5 S_k5_lab
//
// cap drop lnKer5_w1
// gen double lnKer5_w1 = ln(1 + Ker5_w1) if !missing(Ker5_w1)
//
// cap drop k5_bin3 k5_pos
// gen byte k5_bin3 = . 
// replace k5_bin3 = 1 if !missing(Ker5_w1)
//
// quietly count if Ker5_w1 > 0 & !missing(lnKer5_w1)
// local npos = r(N)
//
// if (`npos' >= 2) {
//     xtile k5_pos = lnKer5_w1 if Ker5_w1 > 0 & !missing(lnKer5_w1), nq(2)
//     replace k5_bin3 = k5_pos + 1 if Ker5_w1 > 0 & !missing(k5_pos)
// }
// else {
//     * fallback: if too few positives, put all positives into "Low+"
//     replace k5_bin3 = 2 if Ker5_w1 > 0 & !missing(Ker5_w1)
// }
//
// label define k5b3 1 "Zero" 2 "Low+" 3 "High+", replace
// label values k5_bin3 k5b3
// label var k5_bin3 "Zero vs low/high intensity among positives (ln(1+Ker5_w1))"
//
// local welfare "lnpov Edu_z Wbasic_z Hlth_z Util_z"
//
// foreach y of local welfare {
//     cap confirm variable `y'
//     if _rc continue
//     cap noisily ranksum `y', by(S_k5)
//     cap noisily ksmirnov `y', by(S_k5)
// }
//
// foreach y of local welfare {
//     cap confirm variable `y'
//     if _rc continue
//
//     cap noisily kwallis `y', by(k5_bin3)
//
//     local step = .0001
//     if strpos("`y'", "_z") local step = .01
//
//     tempvar y_r
//     gen double `y_r' = round(`y', `step') if !missing(`y')
//
//     cap noisily nptrend `y_r', group(k5_bin3) cuzick
//     if _rc {
//         cap noisily spearman `y' k5_bin3
//     }
// }
//
// local exposure_vars "lnKer5_w1 Ker5_w1 A_v_log A_v_inv C5_w1 C10_w1 C15_w1"
// foreach x of local exposure_vars {
//     cap confirm variable `x'
//     if _rc continue
//     foreach y of local welfare {
//         cap confirm variable `y'
//         if _rc continue
//         cap noisily spearman `y' `x'
//     }
// }
//
// local placecats "r308b1d r308b1e r309a r309b r309d r309e r310 r403a r403c1 r403c2 y_combo3 r101"
// foreach v of local placecats {
//     local v0 : subinstr local v "i." "", all
//     cap confirm variable `v0'
//     if _rc continue
//     cap noisily tab `v0' S_k5, chi2 row col
//     cap noisily tab `v0' k5_bin3, chi2 row col
// }
//
// log close
