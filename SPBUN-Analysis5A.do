/****************************************************************************************
SPBUN (SPBU Nelayan) exposure → welfare outcomes (Using Ker5_w1)

Disusun oleh: Atha (PSE)
Tujuan: Analisis #5 
****************************************************************************************/

version 17
clear all
set more off
set linesize 255

/****************************************************************************************
A. PATHS
****************************************************************************************/
* Mohon '...' diganti menyesuaikan path anda
global ROOT "..."

global DATA_COAST "$ROOT/Output/iv2sls_pesisir/podes_vill_spbun_pca_iv.dta"
global DATA_ALL   "$ROOT/Output/iv2sls/podes_vill_spbun_pca_iv.dta"

global outdir "$ROOT/Output/tsls"
cap mkdir "$outdir"
cap mkdir "$outdir/tables"
cap mkdir "$outdir/village_values"
cap mkdir "$outdir/logs"

/****************************************************************************************
B. TOGGLES
****************************************************************************************/
global RUN_COAST 1
global RUN_ALL   0

global DO_M0 1
global DO_M1 1
global DO_M2 1
global DO_M3 1

cap log close
if ($DO_M0==1 | $DO_M1==1 | $DO_M2==1 | $DO_M3==1) {
    log using "$outdir/logs/Ker5_V1_run_iv_suite.log", replace text
}
else {
	log using "$outdir/logs/Ker5_V2_run_iv_suite.log", replace text
}

/****************************************************************************************
C. PACKAGES
****************************************************************************************/
cap which ftools
if _rc ssc install ftools, replace

cap which reghdfe
if _rc ssc install reghdfe, replace

cap which ivreghdfe
if _rc ssc install ivreghdfe, replace

cap which ivreg2
if _rc ssc install ivreg2, replace

cap which esttab
if _rc ssc install estout, replace

cap which esttab
if _rc ssc install spwmatrix, replace

/****************************************************************************************
D. SETTINGS 
****************************************************************************************/
global ID    "iddesa"
global FE    "kab"
global CLUST "kab"

/****************************************************************************************
E. INIT
****************************************************************************************/
tempfile VMASTER1X1
global VMASTER1X1 "`VMASTER1X1'"

clear
set obs 0

gen str32 $ID = ""
gen str10  sample  = ""
gen str18  outcome = ""
gen str12  spec    = ""
gen double Ker5_used= .
gen double W_hat   = .
gen double uhat    = .
gen double beta_vill = .
gen double A_contrib = .

save "$VMASTER1X1", replace

tempfile VMASTER2X1
global VMASTER2X1 "`VMASTER2X1'"

clear
set obs 0

gen str32 $ID = ""
gen str10  sample  = ""
gen str18  outcome = ""
gen str12  spec    = ""
gen double Ker5_used= .
gen double W_hat   = .
gen double uhat    = .
gen double beta_vill = .
gen double A_contrib = .

save "$VMASTER2X1", replace

/****************************************************************************************
F. FLAGS
****************************************************************************************/

* Default all run-switch globals to 0 if they are undefined/empty
if "$DO_M0" == "" {
    global DO_M0 0
}
if "$DO_M1" == "" {
    global DO_M1 0
}
if "$DO_M2" == "" {
    global DO_M2 0
}
if "$DO_M3" == "" {
    global DO_M3 0
}

if "$RUN_COAST" == "" {
    global RUN_COAST 0
}
if "$RUN_ALL" == "" {
    global RUN_ALL 0
}

/****************************************************************************************
G. CORE RUNNER
****************************************************************************************/
#delimit cr
capture program drop _run_one_sample
program define _run_one_sample
    syntax, DATASET(string) TAG(string)

    use "`dataset'", clear

    *----------------------------
    * Guards
    *----------------------------
    cap confirm variable $ID
    cap confirm variable $FE
    cap confirm variable lat_v
    local rc_lat = _rc
    cap confirm variable lon_v
    local rc_lon = _rc
    if (`rc_lat' | `rc_lon') {
        noi di as err "WARNING: Missing coords lat_v/lon_v (spatial blocks may skip)."
    }

    cap drop spid
    cap drop spid
	egen long spid = group($ID)
	label var spid "Spatial unit id derived from $ID"


    *----------------------------
    * 0) Ensure exposure + instruments exist (or build from distances)
    *----------------------------
    cap confirm variable Ker5_w1
    if _rc {
        cap confirm variable D_spbun
        if _rc {
            di as err "Missing Ker5_w1 and D_spbun; cannot construct exposure."
            exit 198
        }
        gen double Ker5_w1 = -ln(1 + D_spbun) if !missing(D_spbun)
    }

    cap confirm variable Z_pel
    if _rc {
        cap confirm variable D_pel_iv
        if _rc {
            di as err "Missing Z_pel and D_pel_iv; cannot construct instrument."
            exit 198
        }
        gen double Z_pel = -ln(1 + D_pel_iv) if !missing(D_pel_iv)
    }

    cap confirm variable Z_tbbm
    if _rc {
        cap confirm variable D_tbbm_iv
        if _rc {
            di as err "Missing Z_tbbm and D_tbbm_iv; cannot construct instrument."
            exit 198
        }
        gen double Z_tbbm = -ln(1 + D_tbbm_iv) if !missing(D_tbbm_iv)
    }

    cap confirm variable Z_tpi
    if _rc {
        cap confirm variable D_tpi_iv
        if _rc {
            di as err "Missing Z_tpi and D_tpi_iv; cannot construct instrument."
            exit 198
        }
        gen double Z_tpi = -ln(1 + D_tpi_iv) if !missing(D_tpi_iv)
    }

    cap confirm variable C5_w1
    if !_rc {
        cap drop A0_5 A5_10 A10_15
        gen double A0_5   = C5_w1 if !missing(C5_w1)
        gen double A5_10  = (C10_w1 - C5_w1)  if !missing(C10_w1, C5_w1)
        gen double A10_15 = (C15_w1 - C10_w1) if !missing(C15_w1, C10_w1)
        replace A5_10  = 0 if A5_10  < 0 & !missing(A5_10)
        replace A10_15 = 0 if A10_15 < 0 & !missing(A10_15)
    }

    *----------------------------
    * 1) Outcomes available
    *----------------------------
    local YLIST_S ""
    foreach y in Wbasic_z lnpov_z {
        cap confirm variable `y'
        if !_rc {
            local YLIST_S "`YLIST_S' `y'"
        }
    }

    *--------------------------------
    * 2) Controls
    *--------------------------------

    * A) Clean categorical
    local CATVARS "r308b1d r308b1e r309a r309b r309d r309e r310 r403a r403c1 r403c2"

    tempvar __es
    gen byte `__es' = !missing(Ker5_w1, Z_tpi, Z_tbbm, Z_pel, kab)

    foreach v of local CATVARS {
        cap confirm numeric variable `v'
        if _rc continue

        cap drop `v'_c
        clonevar `v'_c = `v'

        preserve
            keep if `__es'
            keep kab `v'_c
            drop if missing(kab) | missing(`v'_c)
            contract kab `v'_c
            bysort `v'_c: gen n_kab = _N
            levelsof `v'_c if n_kab<=1, local(rare)
        restore

        if "`rare'" != "" {
            noi di as txt "Recode rare levels in `v'_c (<=1 kab cluster) -> 99: `rare'"
            recode `v'_c (`rare' = 99)

            local lbl : value label `v'
            if "`lbl'" != "" {
                cap label define `lbl' 99 "Other/rare", add
                cap label values `v'_c `lbl'
            }
            else {
                cap label define `v'_lbl 99 "Other/rare", replace
                cap label values `v'_c `v'_lbl
            }
        }
    }

    * B) Base categorical controls 
    local X_S_base_cat "i.r308b1d_c i.r308b1e_c i.r309a_c i.r309b_c i.r309d_c i.r309e_c i.r310_c i.r403a_c i.r403c1_c i.r403c2_c"
    local X_S_cat ""
    foreach term of local X_S_base_cat {
        local base = subinstr("`term'","i.","",.)
        cap confirm variable `base'
        if !_rc local X_S_cat "`X_S_cat' `term'"
    }

    * C) PCA-breakdown controls 
    local X_edu_b  ""
    cap ds r701*_b, has(type numeric)
    if !_rc local X_edu_b "`r(varlist)'"

    local X_hlth_b ""
    cap ds r711*_b, has(type numeric)
    if !_rc local X_hlth_b "`r(varlist)'"

    local X_util_b ""
    cap ds r509c*_b, has(type numeric)
    if !_rc local X_util_b "`r(varlist)'"

    * D) Control-set variants for M1 grid
    local X_none    ""
    local X_base    "`X_S_cat'"
    local X_edu     "`X_S_cat' `X_edu_b'"
    local X_hlth    "`X_S_cat' `X_hlth_b'"
    local X_util    "`X_S_cat' `X_util_b'"
    local X_edu_nb  "`X_edu_b'"
    local X_hlth_nb "`X_hlth_b'"
    local X_util_nb "`X_util_b'"
    local X_full    "`X_S_cat' `X_other' `X_edu_b' `X_hlth_b' `X_util_b'"
    local X_S "`X_full'"
    local X_S : list uniq X_S

    * IV options: use partial(`X_S') to stabilize cluster-robust VCE + allow overid/Hansen J
    local IVOPTS "absorb($FE) vce(cluster $CLUST) resid"
    local PARTOPTS ""
    if "`X_S'" != "" local PARTOPTS "partial(`X_S')"


    /****************************************************************************************
    M0. FIRST STAGE
    ****************************************************************************************/
    if $DO_M0 == 1 {
        noi di as txt "-> Ker5 V1 M0 First stage (`tag')"
        qui reghdfe Ker5_w1 Z_pel Z_tbbm Z_tpi `X_S', absorb($FE) vce(cluster $CLUST)
        est store M0_`tag'
        esttab M0_`tag' using "$outdir/tables/Ker5_V1_M0_firststage_`tag'.rtf", replace ///
            se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
            title("Ker5 M0 First stage v1: Ker5_w1 on Z + X + FE (`tag')") ///
            scalars(N r2) compress
    }
	
	if $DO_M0 == 0 {
        noi di as txt "-> Ker5 V2 M0 First stage (`tag')"
        qui reghdfe Ker5_w1 Z_pel Z_tbbm Z_tpi `X_S', absorb($FE) vce(cluster $CLUST)
        est store M0_`tag'
        esttab M0_`tag' using "$outdir/tables/Ker5_V2_M0_firststage_`tag'.rtf", replace ///
            se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
            title("Ker5 M0 First stage v2: Ker5_w1 on Z + X + FE (`tag')") ///
            scalars(N r2) compress
    }

    /****************************************************************************************
    M1. IV-2SLS 
	****************************************************************************************/
    if $DO_M1 == 1 {

        local M1SPECS "edu hlth util base none edu_nb hlth_nb util_nb"

        foreach Y of local YLIST_S {

            foreach s of local M1SPECS {
                local scode ""
                if "`s'" == "edu"     local scode "IVH_EDU"
                if "`s'" == "hlth"    local scode "IVH_HLTH"
                if "`s'" == "util"    local scode "IVH_UTIL"
                if "`s'" == "base"    local scode "IVH_BASE"
                if "`s'" == "none"    local scode "IVH_NONE"
                if "`s'" == "edu_nb"  local scode "IVH_EDU_NB"
                if "`s'" == "hlth_nb" local scode "IVH_HLTH_NB"
                if "`s'" == "util_nb" local scode "IVH_UTIL_NB"
                if "`scode'" == "" continue

                local X_this "`X_`s''"
                local PART_this ""
                if "`X_this'" != "" local PART_this "partial(`X_this')"

                noi di as txt "-> Ker5 M1 Homog IV v1: `Y' (`tag') [ `scode' ]"

                cap noisily ivreghdfe `Y' (Ker5_w1 = Z_pel Z_tbbm Z_tpi) `X_this', `IVOPTS' `PART_this'
				
				local tshort = upper(substr("`tag'",1,1))
				if "`tag'" == "COAST" local tshort "C"
				if "`tag'" == "ALL"   local tshort "A"

				local ycode = upper(substr("`Y'",1,2))
				if "`Y'" == "Wbasic_z"      local ycode "WB"
				if "`Y'" == "lnpov_z"       local ycode "LP"

				local sshort ""
				if "`s'" == "edu"     local sshort "E"
				if "`s'" == "hlth"    local sshort "H"
				if "`s'" == "util"    local sshort "U"
				if "`s'" == "base"    local sshort "B"
				if "`s'" == "none"    local sshort "N"
				if "`s'" == "edu_nb"  local sshort "e"
				if "`s'" == "hlth_nb" local sshort "h"
				if "`s'" == "util_nb" local sshort "u"

				local estname = "Ker5_v1_m1`sshort'`tshort'`ycode'"
				est store `estname'

				esttab `estname' using "$outdir/tables/V1_M1_iv_homog_`tag'_`Y'_`scode'.rtf", replace ///
					se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
					title("Ker5 M1 Homog IV (`scode') v1: `Y' on Ker5_w1 (`tag')") ///
					scalars(N r2) compress

				cap drop W_hat uhat beta_vill A_contrib
				predict double W_hat if e(sample), xb
				predict double uhat  if e(sample), resid
				gen double beta_vill = _b[Ker5_w1] if e(sample)
				gen double A_contrib = beta_vill * Ker5_w1 if e(sample) & !missing(Ker5_w1)

				preserve
					keep $ID Ker5_w1 W_hat uhat beta_vill A_contrib
					cap confirm string variable $ID
					if _rc {
						tostring $ID, replace usedisplayformat format(%18.0g)
					}
					replace $ID = trim($ID)
					gen str10  sample  = "`tag'"
					gen str18  outcome = "`Y'"
					gen str12  spec    = "`scode'"
					rename Ker5_w1 Ker5_used
					append using "$VMASTER1X1"
					save "$VMASTER1X1", replace
				restore
                
                * Run heterogeneity only for FULL controls (IVX4)
                if "`s'" == "full" & "`H_S'" != "" {

                    noi di as txt "-> Ker5 M1 Hetero IV v1: `Y' (`tag') [ IVX4 ] with H = `H_S'"

                    local AENDO "Ker5_w1"
                    local ZALL  "Z_pel Z_tbbm Z_tpi"
                    local HMAIN ""

                    foreach h of local H_S {

                        cap drop A_X_`h'
                        gen double A_X_`h' = Ker5_w1 * `h' if !missing(Ker5_w1, `h')
                        local AENDO "`AENDO' A_X_`h'"

                        foreach z in Z_pel Z_tbbm Z_tpi {
                            cap drop Z_X_`z'_`h'
                            gen double Z_X_`z'_`h' = `z' * `h' if !missing(`z', `h')
                            local ZALL "`ZALL' Z_X_`z'_`h'"
                        }

                        local HMAIN "`HMAIN' c.`h'"
                    }

                    * FULL controls for heterogeneity
                    local X_this "`X_full'"
                    local PART_this ""
                    if "`X_this'" != "" local PART_this "partial(`X_this')"

                    cap noisily ivreghdfe `Y' (`AENDO' = `ZALL') `X_this' `HMAIN', `IVOPTS' `PART_this'

					local tshort = upper(substr("`tag'",1,1))
					if "`tag'" == "COAST" local tshort "C"
					if "`tag'" == "ALL"   local tshort "A"

					local ycode = upper(substr("`Y'",1,2))
					if "`Y'" == "Wbasic_z"      local ycode "WB"
					if "`Y'" == "lnpov_z"       local ycode "LP"

					local estname = "Ker5_v1_m1X4`tshort'`ycode'"
					est store `estname'

					esttab `estname' using "$outdir/tables/Ker5_V1_M1_iv_hetero_`tag'_`Y'_IVX4.rtf", replace ///
						se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
						title("Ker5 M1 Hetero IV (IVX4) v1: `Y' on Ker5_w1 + A×H (`tag')") ///
						scalars(N r2) compress

					cap drop W_hat uhat beta_vill A_contrib
					predict double W_hat if e(sample), xb
					predict double uhat  if e(sample), resid

					gen double beta_vill = _b[Ker5_w1] if e(sample)
					foreach h of local H_S {
						replace beta_vill = beta_vill + (_b[A_X_`h'] * `h') if e(sample) & !missing(`h')
					}
					gen double A_contrib = beta_vill * Ker5_w1 if e(sample) & !missing(Ker5_w1)

					preserve
						cap drop Ker5_used
						gen double Ker5_used = Ker5_w1 if e(sample) & !missing(Ker5_w1)
						keep $ID Ker5_used W_hat uhat beta_vill A_contrib `H_S'
						cap confirm string variable $ID
						if _rc {
							tostring $ID, replace usedisplayformat format(%18.0g)
						}
						replace $ID = trim($ID)

						gen str10  sample  = "`tag'"
						gen str18  outcome = "`Y'"
						gen str12  spec    = "IVX4"

						append using "$VMASTER1X1"
						save "$VMASTER1X1", replace
					restore
                    
                }
            }
        }
    }
	
	if $DO_M1 == 0 {

        local M1SPECS "edu hlth util base none edu_nb hlth_nb util_nb"

        foreach Y of local YLIST_S {

            foreach s of local M1SPECS {
                local scode ""
                if "`s'" == "edu"     local scode "IVH_EDU"
                if "`s'" == "hlth"    local scode "IVH_HLTH"
                if "`s'" == "util"    local scode "IVH_UTIL"
                if "`s'" == "base"    local scode "IVH_BASE"
                if "`s'" == "none"    local scode "IVH_NONE"
                if "`s'" == "edu_nb"  local scode "IVH_EDU_NB"
                if "`s'" == "hlth_nb" local scode "IVH_HLTH_NB"
                if "`s'" == "util_nb" local scode "IVH_UTIL_NB"
                if "`scode'" == "" continue

                local X_this "`X_`s''"
                local PART_this ""
                if "`X_this'" != "" local PART_this "partial(`X_this')"

                noi di as txt "-> Ker5 M1 Homog IV v2: `Y' (`tag') [ `scode' ]"

                cap noisily ivreghdfe `Y' (Ker5_w1 = Z_pel Z_tbbm Z_tpi) `X_this', `IVOPTS' `PART_this'
				
				local tshort = upper(substr("`tag'",1,1))
				if "`tag'" == "COAST" local tshort "C"
				if "`tag'" == "ALL"   local tshort "A"

				local ycode = upper(substr("`Y'",1,2))
				if "`Y'" == "Wbasic_z"      local ycode "WB"
				if "`Y'" == "lnpov_z"       local ycode "LP"

				local sshort ""
				if "`s'" == "edu"     local sshort "E"
				if "`s'" == "hlth"    local sshort "H"
				if "`s'" == "util"    local sshort "U"
				if "`s'" == "base"    local sshort "B"
				if "`s'" == "none"    local sshort "N"
				if "`s'" == "edu_nb"  local sshort "e"
				if "`s'" == "hlth_nb" local sshort "h"
				if "`s'" == "util_nb" local sshort "u"

				local estname = "Ker5_v2_m1`sshort'`tshort'`ycode'"
				est store `estname'

				esttab `estname' using "$outdir/tables/Ker5_V2_M1_iv_homog_`tag'_`Y'_`scode'.rtf", replace ///
					se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
					title("Ker5 M1 Homog IV (`scode') v2: `Y' on Ker5_w1 (`tag')") ///
					scalars(N r2) compress

				cap drop W_hat uhat beta_vill A_contrib
				predict double W_hat if e(sample), xb
				predict double uhat  if e(sample), resid
				gen double beta_vill = _b[Ker5_w1] if e(sample)
				gen double A_contrib = beta_vill * Ker5_w1 if e(sample) & !missing(Ker5_w1)

				preserve
					keep $ID Ker5_w1 W_hat uhat beta_vill A_contrib
					cap confirm string variable $ID
					if _rc {
						tostring $ID, replace usedisplayformat format(%18.0g)
					}
					replace $ID = trim($ID)
					gen str10  sample  = "`tag'"
					gen str18  outcome = "`Y'"
					gen str12  spec    = "`scode'"
					rename Ker5_w1 Ker5_used
					append using "$VMASTER2X1"
					save "$VMASTER2X1", replace
				restore
                
                * Run heterogeneity only for FULL controls (IVX4)
                if "`s'" == "full" & "`H_S'" != "" {

                    noi di as txt "-> Ker5 M1 Hetero IV v2: `Y' (`tag') [ IVX4 ] with H = `H_S'"

                    local AENDO "Ker5_w1"
                    local ZALL  "Z_pel Z_tbbm Z_tpi"
                    local HMAIN ""

                    foreach h of local H_S {

                        cap drop A_X_`h'
                        gen double A_X_`h' = Ker5_w1 * `h' if !missing(Ker5_w1, `h')
                        local AENDO "`AENDO' A_X_`h'"

                        foreach z in Z_pel Z_tbbm Z_tpi {
                            cap drop Z_X_`z'_`h'
                            gen double Z_X_`z'_`h' = `z' * `h' if !missing(`z', `h')
                            local ZALL "`ZALL' Z_X_`z'_`h'"
                        }

                        local HMAIN "`HMAIN' c.`h'"
                    }

                    * FULL controls for heterogeneity
                    local X_this "`X_full'"
                    local PART_this ""
                    if "`X_this'" != "" local PART_this "partial(`X_this')"

                    cap noisily ivreghdfe `Y' (`AENDO' = `ZALL') `X_this' `HMAIN', `IVOPTS' `PART_this'

					local tshort = upper(substr("`tag'",1,1))
					if "`tag'" == "COAST" local tshort "C"
					if "`tag'" == "ALL"   local tshort "A"

					local ycode = upper(substr("`Y'",1,2))
					if "`Y'" == "Wbasic_z"      local ycode "WB"
					if "`Y'" == "lnpov_z"       local ycode "LP"

					local estname = "Ker5_v2_m1X4`tshort'`ycode'"
					est store `estname'

					esttab `estname' using "$outdir/tables/Ker5_V2_M1_iv_hetero_`tag'_`Y'_IVX4.rtf", replace ///
						se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
						title("Ker5 M1 Hetero IV (IVX4) v2: `Y' on Ker5_w1 + A×H (`tag')") ///
						scalars(N r2) compress

					cap drop W_hat uhat beta_vill A_contrib
					predict double W_hat if e(sample), xb
					predict double uhat  if e(sample), resid

					gen double beta_vill = _b[Ker5_w1] if e(sample)
					foreach h of local H_S {
						replace beta_vill = beta_vill + (_b[A_X_`h'] * `h') if e(sample) & !missing(`h')
					}
					gen double A_contrib = beta_vill * Ker5_w1 if e(sample) & !missing(Ker5_w1)

					preserve
						cap drop Ker5_used
						gen double Ker5_used = Ker5_w1 if e(sample) & !missing(Ker5_w1)
						keep $ID Ker5_used W_hat uhat beta_vill A_contrib `H_S'
						cap confirm string variable $ID
						if _rc {
							tostring $ID, replace usedisplayformat format(%18.0g)
						}
						replace $ID = trim($ID)

						gen str10  sample  = "`tag'"
						gen str18  outcome = "`Y'"
						gen str12  spec    = "IVX4"

						append using "$VMASTER2X1"
						save "$VMASTER2X1", replace
					restore
                    
                }
            }
        }
    }
	
end
	/****************************************************************************************
    M2. REDUCED FORM
    ****************************************************************************************/
    if $DO_M2 == 1 {
        foreach Y of local YLIST_S {
            noi di as txt "-> Ker5 M2 Reduced form v1: `Y' (`tag')"
            cap noisily reghdfe `Y' Z_pel Z_tbbm Z_tpi `X_S', absorb($FE) vce(cluster $CLUST)
            if !_rc {
                est store M2_`tag'_`Y'
                esttab M2_`tag'_`Y' using "$outdir/tables/Ker5_V1_M2_reducedform_`tag'_`Y'.rtf", replace ///
                    se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
                    title("Ker5 M2 Reduced form: `Y' on Z + X + FE (`tag')") ///
                    scalars(N r2) compress
            }
        }
    }
	
	if $DO_M2 == 0 {
        foreach Y of local YLIST_S {
            noi di as txt "-> Ker5 M2 Reduced form v2: `Y' (`tag')"
            cap noisily reghdfe `Y' Z_pel Z_tbbm Z_tpi `X_S', absorb($FE) vce(cluster $CLUST)
            if !_rc {
                est store M2_`tag'_`Y'
                esttab M2_`tag'_`Y' using "$outdir/tables/Ker5_V2_M2_reducedform_`tag'_`Y'.rtf", replace ///
                    se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
                    title("Ker5 M2 Reduced form v2: `Y' on Z + X + FE (`tag')") ///
                    scalars(N r2) compress
            }
        }
    }

    /****************************************************************************************
    M3. NAIVE OLS (benchmark)
    ****************************************************************************************/
    if $DO_M3 == 1 {
        foreach Y of local YLIST_S {
            noi di as txt "-> Ker5 M3 OLS v1: `Y' (`tag')"
            cap noisily reghdfe `Y' Ker5_w1 `X_S', absorb($FE) vce(cluster $CLUST)
            if !_rc {
                est store M3_`tag'_`Y'
                esttab M3_`tag'_`Y' using "$outdir/tables/Ker5_V1_M3_ols_`tag'_`Y'.rtf", replace ///
                    se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
                    title("Ker5 M3 OLS v1: `Y' on Ker5_w1 + X + FE (`tag')") ///
                    scalars(N r2) compress
            }
        }
    }
	
	if $DO_M3 == 0 {
        foreach Y of local YLIST_S {
            noi di as txt "-> Ker5 M3 OLS v2: `Y' (`tag')"
            cap noisily reghdfe `Y' Ker5_w1 `X_S', absorb($FE) vce(cluster $CLUST)
            if !_rc {
                est store M3_`tag'_`Y'
                esttab M3_`tag'_`Y' using "$outdir/tables/Ker5_V2_M3_ols_`tag'_`Y'.rtf", replace ///
                    se b(%9.4f) se(%9.4f) star(* 0.10 ** 0.05 *** 0.01) ///
                    title("Ker5 M3 OLS v2: `Y' on Ker5_w1 + X + FE (`tag')") ///
                    scalars(N r2) compress
            }
        }
    }


/****************************************************************************************
H. RUN SUITE 
****************************************************************************************/

if $RUN_COAST == 1 {
    _run_one_sample, dataset("$DATA_COAST") tag("COAST")
}

if $RUN_ALL == 0 {
    _run_one_sample, dataset("$DATA_ALL") tag("ALL")
}


/****************************************************************************************
I. EXPORT MASTER VILLAGE TABLE
****************************************************************************************/
use "$VMASTER1X1", clear

cap confirm variable $ID
if _rc gen str32 $ID = ""

foreach v in sample outcome spec {
    cap confirm variable `v'
    if _rc gen str18 `v' = ""
}

foreach v in Ker5_used W_hat uhat beta_vill A_contrib {
    cap confirm variable `v'
    if _rc gen double `v' = .
}

drop if missing($ID)
order $ID sample outcome spec Ker5_used W_hat uhat beta_vill A_contrib
compress

save "$outdir/village_values/Ker5_village_values_long_v1.dta", replace
export delimited using "$outdir/village_values/Ker5_village_values_long_v1.csv", replace

use "$VMASTER2X1", clear

cap confirm variable $ID
if _rc gen str32 $ID = ""

foreach v in sample outcome spec {
    cap confirm variable `v'
    if _rc gen str18 `v' = ""
}

foreach v in Ker5_used W_hat uhat beta_vill A_contrib {
    cap confirm variable `v'
    if _rc gen double `v' = .
}

drop if missing($ID)
order $ID sample outcome spec Ker5_used W_hat uhat beta_vill A_contrib
compress

save "$outdir/village_values/Ker5_village_values_long_v2.dta", replace
export delimited using "$outdir/village_values/Ker5_village_values_long_v2.csv", replace


log close
