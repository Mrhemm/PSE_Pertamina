/****************************************************************************************
SPBUN (SPBU Nelayan) exposure → welfare outcomes (PODES village + SUSENAS household)
Baseline: SPBUN only (extend later for SPBU / SPBUN+SPBU)

Disusun oleh: Atha (PSE)
Tujuan: Analisis #1 (baseline) untuk melihat indikasi awal/prognostik dan mengonfirmasi
kecurigaan/hipotesis awal berdasarkan Research Questions (RQ) dasar sebelum masuk ke
pemodelan yang lebih kompleks (SPBU / SPBUN+SPBU, robustness grid, heterogeneity penuh).
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
global sus41 "..."
global sus42 "..."
global sus43 "..."

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
     r508* r509*

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
tempfile vill_core vill_bins site_bins2 vill_exposure

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

foreach R in 5 10 15 {
    gen byte in`R' = (dkm<=`R')
    bys iddesa: egen double C`R'_w1   = total(cond(in`R', w1,   0))
    bys iddesa: egen double C`R'_wvol = total(cond(in`R', wvol, 0))
    bys iddesa: egen double C`R'_wrr  = total(cond(in`R', wrr,  0))
}
foreach h in 5 10 20 {
    bys iddesa: egen double Ker`h'_w1   = total(w1  *exp(-dkm/`h'))
    bys iddesa: egen double Ker`h'_wvol = total(wvol*exp(-dkm/`h'))
    bys iddesa: egen double Ker`h'_wrr  = total(wrr *exp(-dkm/`h'))
}

bys iddesa: keep if _n==1
keep iddesa D_v A_v_log A_v_inv C*_w1 C*_wvol C*_wrr Ker*_w1 Ker*_wvol Ker*_wrr
save `vill_exposure', replace

* merge exposures back; fill 0 for count/kernel; cap missing distance to max+1 (so untreated not dropped)
use `vill_core', clear
merge 1:1 iddesa using `vill_exposure', nogen keep(master match)

quietly summarize D_v if !missing(D_v)
local Dmax = r(max)

foreach v of varlist C*_w1 C*_wvol C*_wrr Ker*_w1 Ker*_wvol Ker*_wrr {
    replace `v' = 0 if missing(`v') & !missing(lat_v) & !missing(lon_v)
}

replace D_v = `Dmax' + 1 if missing(D_v) & !missing(lat_v) & !missing(lon_v) & `Dmax'<.
replace A_v_log = -ln(1 + D_v) if missing(A_v_log) & !missing(D_v)
replace A_v_inv = 1/(1 + D_v)  if missing(A_v_inv) & !missing(D_v)

save `vill_exposure', replace

/****************************************************************************************
H. PODES: OUTCOMES (PCA) + BASELINE MODELS
****************************************************************************************/
use "$outdir/podes_vill.dta", clear
merge 1:1 iddesa using `vill_exposure', nogen keep(master match)

cap confirm numeric variable r308a
if !_rc gen byte Coast = (r308a==1) if !missing(r308a)
else gen byte Coast = .

cap confirm numeric variable r308b1a
cap confirm numeric variable r308b1b
gen byte Fish_strict = .
replace Fish_strict = (Coast==1) & (r308b1a==1 | r308b1b==1) if !missing(Coast)

gen byte Fish_loose = .
cap confirm numeric variable r308b1c
cap confirm numeric variable r308b1d
cap confirm numeric variable r308b1e
replace Fish_loose = (Coast==1) | (r308b1a==1 | r308b1b==1 | r308b1c==1 | r308b1d==1 | r308b1e==1) if !missing(Coast)

cap confirm variable r710
if !_rc {
    cap destring r710, replace ignore(",")
    gen double lnpov = ln(1 + r710)
}

local Wbasic ""
capture ds r501* r502* r503*, has(type numeric)
if !_rc local Wbasic "`r(varlist)'"
if "`Wbasic'"!="" {
    cap noisily pca `Wbasic', components(1) correlation
    if !_rc {
        cap drop Wbasic_pca1 Wbasic_z
        predict double Wbasic_pca1 if e(sample), score
        egen double Wbasic_z = std(Wbasic_pca1)
    }
}

local Wutil ""
capture ds r508* r509*, has(type numeric)
if !_rc local Wutil "`r(varlist)'"
if "`Wutil'"!="" {
    cap noisily pca `Wutil', components(1) correlation
    if !_rc {
        cap drop Util_pca1 Util_z
        predict double Util_pca1 if e(sample), score
        egen double Util_z = std(Util_pca1)
    }
}

local Wedu ""
capture ds r701*, has(type numeric)
if !_rc local Wedu "`r(varlist)'"
if "`Wedu'"!="" {
    cap noisily pca `Wedu', components(1) correlation
    if !_rc {
        cap drop Edu_pca1 Edu_z
        predict double Edu_pca1 if e(sample), score
        egen double Edu_z = std(Edu_pca1)
    }
}

local Whlth ""
capture ds r711*, has(type numeric)
if !_rc local Whlth "`r(varlist)'"
if "`Whlth'"!="" {
    foreach v of local Whlth {
        cap drop ln_`v'
        gen double ln_`v' = ln(1+`v')
    }
    capture ds ln_r711*, has(type numeric)
    if !_rc {
        local Whlthln "`r(varlist)'"
        cap noisily pca `Whlthln', components(1) correlation
        if !_rc {
            cap drop Hlth_pca1 Hlth_z
            predict double Hlth_pca1 if e(sample), score
            egen double Hlth_z = std(Hlth_pca1)
        }
    }
}

local Xgeo ""
foreach v in r308a r308b1a r308b1b r308b1c r308b1d r308b1e {
    cap confirm numeric variable `v'
    if !_rc local Xgeo "`Xgeo' `v'"
}

local Xenv ""
foreach v in r309a r309b r309d r309e r310 {
    cap confirm numeric variable `v'
    if !_rc local Xenv "`Xenv' `v'"
}
cap confirm string variable r309c
if !_rc {
    cap drop r309c_cat
    encode r309c, gen(r309c_cat)
    local Xenv "`Xenv' i.r309c_cat"
}

local Xecon ""
foreach v in r403a r403c1 r403c2 r105 {
    cap confirm numeric variable `v'
    if !_rc local Xecon "`Xecon' `v'"
}
local Xv "`Xgeo' `Xenv' `Xecon'"

local Tv "A_v_log"

local EST_MAIN ""
cap confirm variable Wbasic_z
if !_rc {
    cap noisily reghdfe Wbasic_z `Tv' `Xv', absorb(kab) vce(cluster kab)
    if !_rc {
        estimates store rq1
        local EST_MAIN "`EST_MAIN' rq1"
    }
}
cap confirm variable lnpov
if !_rc {
    cap noisily reghdfe lnpov `Tv' `Xv', absorb(kab) vce(cluster kab)
    if !_rc {
        estimates store rq2
        local EST_MAIN "`EST_MAIN' rq2"
    }
}
cap confirm variable Util_z
if !_rc {
    cap noisily reghdfe Util_z `Tv' `Xv', absorb(kab) vce(cluster kab)
    if !_rc {
        estimates store rq5
        local EST_MAIN "`EST_MAIN' rq5"
    }
}
cap confirm variable Edu_z
if !_rc {
    cap noisily reghdfe Edu_z `Tv' `Xv', absorb(kab) vce(cluster kab)
    if !_rc {
        estimates store rq6
        local EST_MAIN "`EST_MAIN' rq6"
    }
}
cap confirm variable Hlth_z
if !_rc {
    cap noisily reghdfe Hlth_z `Tv' `Xv', absorb(kab) vce(cluster kab)
    if !_rc {
        estimates store rq7
        local EST_MAIN "`EST_MAIN' rq7"
    }
}
cap confirm variable Wbasic_z
if !_rc {
    cap noisily reghdfe Wbasic_z c.`Tv'##i.Fish_strict `Xv', absorb(kab) vce(cluster kab)
    if !_rc estimates store rq1_het
}

/****************************************************************************************
I. SUSENAS: HH OUTCOMES + MERGE DISTRICT TREATMENT
****************************************************************************************/
tempfile Tk hhcount hh_gas sus_hh

* I1) District-level SPBUN intensity from coded site data
use `spbun_site_coded', clear
rename *, lower

cap confirm numeric variable r101
if _rc {
    di as err "spbun_site_coded missing r101."
    exit 111
}
cap confirm numeric variable r102
if _rc {
    di as err "spbun_site_coded missing r102."
    exit 111
}

drop if missing(r101) | missing(r102)

collapse (count) spbun_n=site_id ///
        (sum)   Volume_k=vol_s ///
        (sum)   Quota_k=quota_s, by(r101 r102)

gen double RR_k = .
replace RR_k = Volume_k/Quota_k if Quota_k>0 & !missing(Volume_k)
save `Tk', replace

* I2) District weights from SUSENAS Block 43
use "$sus43", clear
rename *, lower

cap confirm numeric variable r101
if _rc exit 111
cap confirm numeric variable r102
if _rc exit 111

local wvar ""
foreach cand in wert bobot weight wgt fwt pwt {
    cap confirm numeric variable `cand'
    if !_rc & "`wvar'"=="" local wvar "`cand'"
}
if "`wvar'"=="" {
    cap ds *wert* *bobot* *weight* *wgt* *fwt* *pwt*, has(type numeric)
    if !_rc local wvar : word 1 of `r(varlist)'
}
if "`wvar'"=="" {
    cap ds *wert* *bobot* *weight* *wgt* *fwt* *pwt*, has(type string)
    if !_rc {
        local wvar : word 1 of `r(varlist)'
        cap destring `wvar', replace ignore(",")
    }
}
cap confirm numeric variable `wvar'
if _rc {
    di as err "Cannot find usable SUSENAS weight variable in sus43."
    exit 111
}
cap drop wgt
rename `wvar' wgt

collapse (sum) HH_w = wgt, by(r101 r102)
save `hhcount', replace

* I3) Merge HH weight to Tk and build intensity per weighted-HH
use `Tk', clear
merge 1:1 r101 r102 using `hhcount', nogen keep(master match)

gen double VolumePerHH_k = .
replace VolumePerHH_k = Volume_k / HH_w if HH_w>0 & !missing(Volume_k)
save `Tk', replace

/****************************************************************************************
I4. SUS42: build NonFood (and optional Gas/Solar) per HH
****************************************************************************************/
use "$sus42", clear
rename *, lower

cap confirm numeric variable r101
if _rc exit 111
cap confirm numeric variable r102
if _rc exit 111

* detect HH keys and standardize names to: urut wi1 wi2
local k1 "urut"
local k2 "wi1"
local k3 "wi2"

cap confirm variable `k1'
if _rc {
    cap ds *urut*, has(type numeric)
    if !_rc local k1 : word 1 of `r(varlist)'
    else {
        cap ds *urut*, has(type string)
        if !_rc local k1 : word 1 of `r(varlist)'
    }
}
cap confirm variable `k2'
if _rc {
    cap ds *wi1*, has(type numeric)
    if !_rc local k2 : word 1 of `r(varlist)'
    else {
        cap ds *wi1*, has(type string)
        if !_rc local k2 : word 1 of `r(varlist)'
    }
}
cap confirm variable `k3'
if _rc {
    cap ds *wi2*, has(type numeric)
    if !_rc local k3 : word 1 of `r(varlist)'
    else {
        cap ds *wi2*, has(type string)
        if !_rc local k3 : word 1 of `r(varlist)'
    }
}

cap confirm variable `k1'
if _rc exit 111
cap confirm variable `k2'
if _rc exit 111
cap confirm variable `k3'
if _rc exit 111

* normalize key types
cap confirm string variable `k1'
if !_rc cap destring `k1', replace ignore(" ,")
cap confirm string variable `k2'
if !_rc cap destring `k2', replace ignore(" ,")
cap confirm string variable `k3'
if !_rc cap destring `k3', replace ignore(" ,")

if "`k1'"!="urut" rename `k1' urut
if "`k2'"!="wi1"  rename `k2' wi1
if "`k3'"!="wi2"  rename `k3' wi2

* detect COICOP var
local coicopvar "coicop"
cap confirm variable `coicopvar'
if _rc {
    cap ds *coicop*, has(type numeric)
    if !_rc local coicopvar : word 1 of `r(varlist)'
    else {
        cap ds *coicop*, has(type string)
        if !_rc local coicopvar : word 1 of `r(varlist)'
    }
}
cap confirm variable `coicopvar'
if _rc {
    di as err "sus42: cannot find COICOP variable."
    exit 111
}

* detect monthly exp var (SEBULAN-like)
local expvar "sebulan"
cap confirm variable `expvar'
if _rc {
    cap ds *sebulan*, has(type numeric)
    if !_rc local expvar : word 1 of `r(varlist)'
    else {
        cap ds *sebulan*, has(type string)
        if !_rc {
            local expvar : word 1 of `r(varlist)'
            cap destring `expvar', replace ignore(",")
        }
    }
}
cap confirm numeric variable `expvar'
if _rc {
    di as err "sus42: cannot find numeric monthly expenditure variable (SEBULAN-like)."
    exit 111
}

* >>> OPTIONAL: fill these with actual codes if you want Gas/Solar
local COICOP_GAS   ""
local COICOP_SOLAR ""

gen double nonfood_item = `expvar'

gen byte is_gas = 0
gen byte is_solar = 0

* Gas/Solar only if codes provided
local do_gas = ("`COICOP_GAS'"!="")
local do_solar = ("`COICOP_SOLAR'"!="")

capture confirm numeric variable `coicopvar'
if !_rc {
    if `do_gas'   replace is_gas   = inlist(`coicopvar', `COICOP_GAS')
    if `do_solar' replace is_solar = inlist(`coicopvar', `COICOP_SOLAR')
}
else {
    cap tostring `coicopvar', replace
    if `do_gas'   replace is_gas   = inlist(`coicopvar', `"`COICOP_GAS'"')
    if `do_solar' replace is_solar = inlist(`coicopvar', `"`COICOP_SOLAR'"')
}

gen double gas_m   = .
gen double solar_m = .
if `do_gas'   replace gas_m   = cond(is_gas==1,   `expvar', 0)
if `do_solar' replace solar_m = cond(is_solar==1, `expvar', 0)

collapse (sum) GasExp=gas_m SolarExp=solar_m NonFoodExp=nonfood_item, ///
    by(r101 r102 urut wi1 wi2)

gen double lnGas   = ln(1 + GasExp)   if !missing(GasExp)
gen double lnSolar = ln(1 + SolarExp) if !missing(SolarExp)

save `hh_gas', replace

/****************************************************************************************
I5. SUS43: HH dataset + merge hh_gas + merge Tk; set untreated districts to 0
****************************************************************************************/
use "$sus43", clear
rename *, lower

cap confirm numeric variable r101
if _rc exit 111
cap confirm numeric variable r102
if _rc exit 111

* weight -> wgt
cap confirm numeric variable wgt
if _rc {
    local wvar ""
    foreach cand in wert bobot weight wgt fwt pwt {
        cap confirm numeric variable `cand'
        if !_rc & "`wvar'"=="" local wvar "`cand'"
    }
    if "`wvar'"=="" {
        cap ds *wert* *bobot* *weight* *wgt* *fwt* *pwt*, has(type numeric)
        if !_rc local wvar : word 1 of `r(varlist)'
    }
    cap confirm numeric variable `wvar'
    if _rc exit 111
    cap drop wgt
    rename `wvar' wgt
}

* standardize keys to urut wi1 wi2 (same as hh_gas)
local k1 "urut"
local k2 "wi1"
local k3 "wi2"

cap confirm variable `k1'
if _rc {
    cap ds *urut*, has(type numeric)
    if !_rc local k1 : word 1 of `r(varlist)'
    else {
        cap ds *urut*, has(type string)
        if !_rc local k1 : word 1 of `r(varlist)'
    }
}
cap confirm variable `k2'
if _rc {
    cap ds *wi1*, has(type numeric)
    if !_rc local k2 : word 1 of `r(varlist)'
    else {
        cap ds *wi1*, has(type string)
        if !_rc local k2 : word 1 of `r(varlist)'
    }
}
cap confirm variable `k3'
if _rc {
    cap ds *wi2*, has(type numeric)
    if !_rc local k3 : word 1 of `r(varlist)'
    else {
        cap ds *wi2*, has(type string)
        if !_rc local k3 : word 1 of `r(varlist)'
    }
}

cap confirm string variable `k1'
if !_rc cap destring `k1', replace ignore(" ,")
cap confirm string variable `k2'
if !_rc cap destring `k2', replace ignore(" ,")
cap confirm string variable `k3'
if !_rc cap destring `k3', replace ignore(" ,")

if "`k1'"!="urut" rename `k1' urut
if "`k2'"!="wi1"  rename `k2' wi1
if "`k3'"!="wi2"  rename `k3' wi2

merge 1:1 r101 r102 urut wi1 wi2 using `hh_gas', nogen keep(master match)
merge m:1 r101 r102 using `Tk', nogen keep(master match)

* set untreated districts to 0 (keep controls)
foreach v in spbun_n Volume_k Quota_k RR_k HH_w VolumePerHH_k {
    cap confirm variable `v'
    if !_rc replace `v' = 0 if missing(`v')
}

* HH size
cap confirm numeric variable r301
if !_rc gen double HHSize = r301
else {
    cap ds *r301*, has(type numeric)
    if !_rc {
        local hhs : word 1 of `r(varlist)'
        gen double HHSize = `hhs'
    }
}

cap confirm numeric variable r105
if !_rc gen byte Urban = (r105==1) if !missing(r105)

cap confirm numeric variable NonFoodExp
if _rc {
    di as err "NonFoodExp not found after merging hh_gas."
    exit 111
}

gen double NonFoodExpPC = NonFoodExp / HHSize if HHSize>0 & !missing(NonFoodExp)
gen double lnNonFoodPC  = ln(NonFoodExpPC) if NonFoodExpPC>0

foreach v in kalori_kap prote_kap lemak_kap karbo_kap {
    cap confirm numeric variable `v'
    if !_rc gen double ln_`v' = ln(1+`v')
}

save `sus_hh', replace

/****************************************************************************************
J. SUSENAS MODELS (province FE; cluster district; weights wgt)
****************************************************************************************/
use `sus_hh', clear

egen long kab = group(r101 r102), label

local Zh "HHSize Urban"
cap confirm variable HHSize
if _rc local Zh : subinstr local Zh "HHSize" "", all
cap confirm variable Urban
if _rc local Zh : subinstr local Zh "Urban" "", all

local Tk_base "VolumePerHH_k"
cap confirm numeric variable `Tk_base'
if _rc {
    di as err "Tk_base (`Tk_base') missing."
    exit 111
}

cap confirm variable lnGas
if !_rc {
    cap noisily reghdfe lnGas `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster kab)
    if !_rc estimates store rq10_gas
}
cap confirm variable lnSolar
if !_rc {
    cap noisily reghdfe lnSolar `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster kab)
    if !_rc estimates store rq10_solar
}
cap confirm variable lnNonFoodPC
if !_rc {
    cap noisily reghdfe lnNonFoodPC `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster kab)
    if !_rc estimates store rq11
}
foreach y in ln_kalori_kap ln_prote_kap ln_lemak_kap ln_karbo_kap {
    cap confirm variable `y'
    if !_rc {
        cap noisily reghdfe `y' `Tk_base' `Zh' [pw=wgt], absorb(r101) vce(cluster kab)
        if !_rc estimates store rq12_`y'
    }
}

/****************************************************************************************
K. ROBUSTNESS GRID: rerun village RQ1 across exposure definitions
****************************************************************************************/
use "$outdir/podes_vill.dta", clear
merge 1:1 iddesa using `vill_exposure', nogen keep(master match)

local Xgeo ""
foreach v in r308a r308b1a r308b1b r308b1c r308b1d r308b1e {
    cap confirm numeric variable `v'
    if !_rc local Xgeo "`Xgeo' `v'"
}
local Xenv ""
foreach v in r309a r309b r309d r309e r310 {
    cap confirm numeric variable `v'
    if !_rc local Xenv "`Xenv' `v'"
}
cap confirm string variable r309c
if !_rc {
    cap drop r309c_cat
    encode r309c, gen(r309c_cat)
    local Xenv "`Xenv' i.r309c_cat"
}
local Xecon ""
foreach v in r403a r403c1 r403c2 r105 {
    cap confirm numeric variable `v'
    if !_rc local Xecon "`Xecon' `v'"
}
local Xv "`Xgeo' `Xenv' `Xecon'"

cap confirm variable Wbasic_z
if _rc {
    local Wbasic ""
    capture ds r501* r502* r503*, has(type numeric)
    if !_rc local Wbasic "`r(varlist)'"
    if "`Wbasic'"!="" {
        cap noisily pca `Wbasic', components(1) correlation
        if !_rc {
            predict double Wbasic_pca1 if e(sample), score
            egen double Wbasic_z = std(Wbasic_pca1)
        }
    }
}

cap confirm variable Wbasic_z
if !_rc {
    local exposures "A_v_log C5_w1 C10_w1 C15_w1 Ker5_w1 Ker10_w1 Ker20_w1"
    foreach T of local exposures {
        cap confirm numeric variable `T'
        if !_rc {
            cap noisily reghdfe Wbasic_z `T' `Xv', absorb(kab) vce(cluster kab)
            if !_rc estimates store rb_`T'
        }
    }
}

/****************************************************************************************
L. OUTPUT TABLE
****************************************************************************************/
cap which esttab
if _rc ssc install estout, replace

local OUTLIST ""
foreach m in rq1 rq2 rq5 rq6 rq7 rq10_gas rq10_solar rq11 {
    cap estimates restore `m'
    if !_rc local OUTLIST "`OUTLIST' `m'"
}

cap noisily esttab `OUTLIST' using "$outdir/results_main.rtf", replace

log close
di as result "DONE. Outputs in: $outdir"
