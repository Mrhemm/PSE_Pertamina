/****************************************************************************************
SPBUN – Location Match, Nearest-Village Poverty Attach, and P(tidak layak | MDI, poverty)
****************************************************************************************/

version 17
clear all
set more off
set linesize 255

* ----------------------------
* 0) PATHS
* ----------------------------
* Mohon '...' diganti menyesuaikan path anda
global BASE_DIR     "..."
global SPBUN_XLSX   "$BASE_DIR/lokasi_spbu-n.xlsx"
global PODES_DTA    "$BASE_DIR/Output/podes_modelA_ready.dta"
global SURV_XLSX    "$BASE_DIR/01Survival-mode"
global MIXED_XLSX   "$BASE_DIR/02Mix-mode"
global EQUI_XLSX    "$BASE_DIR/00Equitable-mode"

global OUTDIR       "$BASE_DIR/Output/MDI-Check"
cap mkdir 			"$OUTDIR"

tempfile spbun_loc villages surv spbun_near merged_final

* ----------------------------
* 1) SPBUN location master (match by SPBUN id)
* ----------------------------
tempfile spbun_site
import excel "$SPBUN_XLSX", sheet("Data") firstrow clear

capture confirm variable Koordinat
rename Koordinat titik_koordinat

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

gen long site_id = NoLembagaPenyalur
keep site_id lat_s lon_s 
save `spbun_loc', replace

* ----------------------------
* 2) SURVIVAL (viability + MDI), keyed by SPBUN id
* ----------------------------
import excel using "$SURV_XLSX", sheet("Summary_Model1") firstrow clear
rename NomorSPBUN spbun_id

local vlay ""
ds, has(type numeric)
foreach v in `r(varlist)' {
    if strpos(lower("`v'"), "layak") & strpos(lower("`v'"), "tidak") local vlay "`v'"
}
rename `vlay' layak_flag
gen byte tidak_layak = (layak_flag==0) if !missing(layak_flag)

cap confirm var MDI
rename MDI mdi_in
rename spbun_id site_id

keep site_id tidak_layak layak_flag mdi_in TotalCAPEX WACC PP
save `surv', replace

* ----------------------------
* 3) VILLAGE (PODES): coords + poverty index (lnpov)
* ----------------------------
use "$PODES_DTA", clear
keep iddesa lat_v lon_v lnpov nama_prov nama_kab nama_kec nama_desa
drop if missing(iddesa) | missing(lat_v) | missing(lon_v) | missing(lnpov)
save `villages', replace

* ----------------------------
* 4) Attach nearest-village poverty to each SPBUN (1 closest point)
* ----------------------------
cap which geonear
if _rc ssc install geonear, replace

use `spbun_loc', clear
drop if site_id==5885103
save `spbun_loc', replace

geonear site_id lat_s lon_s using `villages', ///
    neighbors(iddesa lat_v lon_v) nearcount(1) wide

rename nid iddesa
rename km_to_nid dist_km

keep site_id lat_s lon_s iddesa dist_km
tempfile spbun_nn
save `spbun_nn', replace

use `villages', clear
keep iddesa lnpov
rename lnpov lnpov_near
tempfile vill_pov
save `vill_pov', replace

use `spbun_nn', clear
merge m:1 iddesa using `vill_pov', keep(match master) nogen
save `spbun_near', replace

* ----------------------------
* 5) Merge nearest-poverty with SURVIVAL (viability + MDI)
* ----------------------------
use `spbun_near', clear
merge 1:1 site_id using `surv', keep(match master) nogenerate
drop if PP == .
save `merged_final', replace

* ----------------------------
* 6) Probability of "tidak layak" given high MDI and poverty
* ----------------------------
keep if !missing(tidak_layak, mdi_in, lnpov_near)

logit tidak_layak c.lnpov_near##i.mdi_in, vce(robust)
estimates store M1

* lock estimation sample
gen byte sample_M1 = e(sample)
label var sample_M1 "Estimation sample for M1"

* poverty points (within estimation sample)
quietly summ lnpov_near if sample_M1, detail
local p25 = r(p25)
local p50 = r(p50)
local p75 = r(p75)

* (A) Predicted probabilities by mdi at p25/p50/p75
margins mdi_in if sample_M1, at(lnpov_near=(`p25' `p50' `p75')) post
estimates store Marg_prob

* (B) Discrete change mdi at p25/p50/p75
estimates restore M1
margins if sample_M1, dydx(mdi_in) at(lnpov_near=(`p25' `p50' `p75')) post
estimates store Marg_dydx

* simple descriptive check
bys mdi_in: summ tidak_layak if sample_M1

* predictions for export
estimates restore M1
predict double phat_M1 if sample_M1, pr
label var phat_M1 "Predicted P(tidak layak) from logit"

* ----------------------------
* Export RTF outputs (logit + margins tables)
* ----------------------------
cap which esttab
if _rc {
    cap ssc install estout, replace
}

cap which esttab
if !_rc {
    esttab M1 using "$OUTDIR/logit_tidaklayak.rtf", replace ///
        b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
        stats(N ll, fmt(%9.0g %9.3f) labels("N" "LogLik")) ///
        title("Logit: P(SPBUN tidak layak) ~ poverty (nearest) x High MDI")

    esttab Marg_prob using "$OUTDIR/margins_pr_tidaklayak.rtf", replace ///
        cells("b(fmt(4)) se(fmt(4))") ///
        title("Margins: Pr(tidak_layak) by High MDI at p25/p50/p75 of lnpov_near")

    esttab Marg_dydx using "$OUTDIR/margins_dydx_highmdi.rtf", replace ///
        cells("b(fmt(4)) se(fmt(4))") ///
        title("Margins: dydx(mdi_in) at p25/p50/p75 of lnpov_near")
}
else {
    di as err "esttab not available; RTF tables not written. Try: ssc install estout"
}
