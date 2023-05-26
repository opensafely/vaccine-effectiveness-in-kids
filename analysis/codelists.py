from cohortextractor import (codelist, codelist_from_csv, combine_codelists)


covid_icd10 = codelist_from_csv(
    "codelists/opensafely-covid-identification.csv",
    system="icd10",
    column="icd10_code",
)

covid_emergency = codelist(
    ["1240751000000100"],
    system="snomed",
)


covid_primary_care_positive_test = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-probable-covid-positive-test.csv",
    system="ctv3",
    column="CTV3ID",
)

covid_primary_care_code = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-probable-covid-clinical-code.csv",
    system="ctv3",
    column="CTV3ID",
)

covid_primary_care_sequelae = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-probable-covid-sequelae.csv",
    system="ctv3",
    column="CTV3ID",
)

covid_primary_care_probable_combined = combine_codelists(
    covid_primary_care_positive_test,
    covid_primary_care_code,
    covid_primary_care_sequelae,
)
covid_primary_care_suspected_covid_advice = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-suspected-covid-advice.csv",
    system="ctv3",
    column="CTV3ID",
)
covid_primary_care_suspected_covid_had_test = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-suspected-covid-had-test.csv",
    system="ctv3",
    column="CTV3ID",
)
covid_primary_care_suspected_covid_isolation = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-suspected-covid-isolation-code.csv",
    system="ctv3",
    column="CTV3ID",
)
covid_primary_care_suspected_covid_nonspecific_clinical_assessment = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-suspected-covid-nonspecific-clinical-assessment.csv",
    system="ctv3",
    column="CTV3ID",
)
covid_primary_care_suspected_covid_exposure = codelist_from_csv(
    "codelists/opensafely-covid-identification-in-primary-care-exposure-to-disease.csv",
    system="ctv3",
    column="CTV3ID",
)
primary_care_suspected_covid_combined = combine_codelists(
    covid_primary_care_suspected_covid_advice,
    covid_primary_care_suspected_covid_had_test,
    covid_primary_care_suspected_covid_isolation,
    covid_primary_care_suspected_covid_exposure,
)



ethnicity = codelist_from_csv(
    "codelists/opensafely-ethnicity-snomed-0removed.csv",
    system="snomed",
    column="snomedcode",
    category_column="Grouping_6",
)

## PRIMIS
# Patients in long-stay nursing and residential care
carehome = codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-longres.csv", 
    system="snomed", 
    column="code",
)


# High Risk from COVID-19 code
shield = codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-shield.csv",
    system="snomed",
    column="code",
)

# Lower Risk from COVID-19 codes
nonshield = codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-nonshield.csv",
    system="snomed",
    column="code",
)


### Adding relevant PRIMIS codes to generate at risk group
immdx_cov_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-immdx_cov.csv",
    system="snomed",
    column="code",
)

immrx_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-immrx.csv",
    system="snomed",
    column="code",
)

dxt_chemo_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-dxt_chemo_cod.csv",
    system="snomed",
    column="code",
)

ckd_cov_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-ckd_cov.csv",
    system="snomed",
    column="code",
)

ckd15_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-ckd15.csv",
    system="snomed",
    column="code",
)

ckd35_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-ckd35.csv",
    system="snomed",
    column="code",
)

astadm_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-astadm.csv",
    system="snomed",
    column="code",
)

ast_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-ast.csv",
    system="snomed",
    column="code",
)

astrxm1_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-astrxm1.csv",
    system="snomed",
    column="code",
)

astrxm2_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-astrxm2.csv",
    system="snomed",
    column="code",
)

resp_cov_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-resp_cov.csv",
    system="snomed",
    column="code",
)

diab_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-diab.csv",
    system="snomed",
    column="code",
)

dmres_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-dmres.csv",
    system="snomed",
    column="code",
)

addis_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-addis_cod.csv",
    system="snomed",
    column="code",
)
gdiab_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-gdiab_cod.csv",
    system="snomed",
    column="code",
)

preg_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-preg.csv",
    system="snomed",
    column="code",
)

pregdel_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-pregdel.csv",
    system="snomed",
    column="code",
)

cld_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-cld.csv",
    system="snomed",
    column="code",
)

cns_cov_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-cns_cov.csv",
    system="snomed",
    column="code",
)

chd_cov_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-chd_cov.csv",
    system="snomed",
    column="code",
)

spln_cov_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-spln_cov.csv",
    system="snomed",
    column="code",
)

learndis_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-learndis.csv",
    system="snomed",
    column="code",
)

sev_mental_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-sev_mental.csv",
    system="snomed",
    column="code",
)

smhres_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-smhres.csv",
    system="snomed",
    column="code",
)

hhld_imdef_cod=codelist_from_csv(
    "codelists/primis-covid19-vacc-uptake-hhld_imdef.csv",
    system="snomed",
    column="code",
) 

discharged_to_hospital = codelist(
    ["306706006", "1066331000000109", "1066391000000105"],
    system="snomed",
)

fractures_icd10 = codelist_from_csv(
    "codelists/opensafely-fractures.csv",
    system="icd10",
    column="code"
)

fractures_snomedECDS = codelist(
  [
    "371162008","81639003","430984009","66112004","60667009","269062008","207938004",
    "207957008","13695006","207974008","766775007","91037003","33173003","29749002",
    "43295006","302222008","111640008","71555008","53627009","29045004","208322000",
    "208371005","9468002","208394006","208403005","704213001","24424003","359817006",
    "25415003","428151000","80756009","447139008","447395005","413877007","42188001",
    "64665009","342070009","81576005","371161001","111609001","40613008","87225004",
    "45910007","269070003","207949005","207965006","207977001","767262002","15474008",
    "111637008","47864008","89294002","302232001","42945005","37449000","81966000",
    "34578006","208341002","29014003","1370007","208420009","704236005","21698002",
    "361118003","28576007","428019004","111643005","446979005","447017008","414943006",
    "481870042","4948002","367527001", "74395007", "95851007"
  ],
  system="snomed"
)