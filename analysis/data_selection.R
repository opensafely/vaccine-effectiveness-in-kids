
# # # # # # # # # # # # # # # # # # # # #
# This script:
# imports processed data
# filters out people who are excluded from the main analysis
# outputs inclusion/exclusions flowchart data
# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----

## Import libraries ----
library('tidyverse')
library('here')
library('glue')

source(here("lib", "functions", "utility.R"))

## import command-line arguments ----
args <- commandArgs(trailingOnly=TRUE)

## create output directories ----
fs::dir_create(here("output", "data"))


## import globally defined study dates and convert to "Date"
study_dates <-
  jsonlite::read_json(path=here("lib", "design", "study-dates.json")) %>%
  map(as.Date)


## Import processed data ----

data_processed <- read_rds(here("output", "data", "data_processed.rds"))


# Define selection criteria ----
data_criteria <- data_processed %>%
  transmute(
    patient_id,
    has_age = !is.na(age),
    has_sex = !is.na(sex) & !(sex %in% c("I", "U")),
    has_imd = imd_Q5 != "Unknown",
    has_ethnicity = !is.na(ethnicity_combined),
    has_region = !is.na(region),
    #has_msoa = !is.na(msoa),
    isnot_hscworker = !hscworker,
    isnot_carehomeresident = !care_home_combined,
    isnot_endoflife = !endoflife,
    isnot_housebound = !housebound,
    vax1_afterfirstvaxdate = case_when(
      (vax1_type=="pfizer") & (vax1_date >= study_dates$firstpfizer_date) ~ TRUE,
      (vax1_type=="az") & (vax1_date >= study_dates$firstaz_date) ~ TRUE,
      (vax1_type=="moderna") & (vax1_date >= study_dates$firstmoderna_date) ~ TRUE,
      TRUE ~ FALSE
    ),
    vax2_beforelastvaxdate = !is.na(vax2_date) & (vax2_date <= study_dates$lastvax2_date),
    vax3_notbeforestartdate = case_when(
      (vax3_type=="pfizer") & (vax3_date < study_dates$pfizerstart_date) ~ FALSE,
      #(vax3_type=="az") & (vax1_date >= study_dates$azstart_date) ~ TRUE,
      (vax3_type=="moderna") & (vax3_date < study_dates$modernastart_date) ~ FALSE,
      TRUE ~ TRUE
    ),
    vax3_beforeenddate = case_when(
      (vax3_type=="pfizer") & (vax3_date <= study_dates$pfizerend_date) & !is.na(vax3_date) ~ TRUE,
      #(vax3_type=="az") & (vax1_date <= study_dates$azend_date) & !is.na(vax3_date) ~ TRUE,
      (vax3_type=="moderna") & (vax3_date <= study_dates$modernaend_date) & !is.na(vax3_date) ~ TRUE,
      TRUE ~ FALSE
    ),
    vax12_homologous = vax1_type==vax2_type,
    has_vaxgap12 = vax2_date >= (vax1_date+17), # at least 17 days between first two vaccinations
    has_vaxgap23 = vax3_date >= (vax2_date+17) | is.na(vax3_date), # at least 17 days between second and third vaccinations
    has_knownvax1 = vax1_type %in% c("pfizer", "az"),
    has_knownvax2 = vax2_type %in% c("pfizer", "az"),
    has_expectedvax3type = vax3_type %in% c("pfizer", "moderna"),

    jcvi_group_6orhigher = jcvi_group %in% as.character(1:6),

    include = (
      #jcvi_group_6orhigher & # temporary until more data available
      vax1_afterfirstvaxdate &
      vax2_beforelastvaxdate &
      vax3_notbeforestartdate &
      has_age & has_sex & has_imd & has_ethnicity & has_region &
      has_vaxgap12 & has_vaxgap23 & has_knownvax1 & has_knownvax2 & vax12_homologous &
      isnot_hscworker &
      isnot_carehomeresident & isnot_endoflife &
      isnot_housebound
    ),
  )

data_cohort <- data_criteria %>%
  filter(include) %>%
  select(patient_id) %>%
  left_join(data_processed, by="patient_id") %>%
  droplevels()

write_rds(data_cohort, here("output", "data", "data_cohort.rds"), compress="gz")
arrow::write_feather(data_cohort, here("output", "data", "data_cohort.feather"))

data_flowchart <- data_criteria %>%
  transmute(
    c0 = vax1_afterfirstvaxdate & vax2_beforelastvaxdate & vax3_notbeforestartdate,
    #c1_1yearfup = c0_all & (has_follow_up_previous_year),
    c1 = c0 & (has_age & has_sex & has_imd & has_ethnicity & has_region),
    c2 = c1 & (has_vaxgap12 & has_vaxgap23 & has_knownvax1 & has_knownvax2 & vax12_homologous),
    c3 = c2 & (isnot_hscworker ),
    c4 = c3 & (isnot_carehomeresident & isnot_endoflife & isnot_housebound),
    c5 = c4 & vax3_beforeenddate & has_expectedvax3type
  ) %>%
  summarise(
    across(.fns=sum)
  ) %>%
  pivot_longer(
    cols=everything(),
    names_to="criteria",
    values_to="n"
  ) %>%
  mutate(
    n_exclude = lag(n) - n,
    pct_exclude = n_exclude/lag(n),
    pct_all = n / first(n),
    pct_step = n / lag(n),
    crit = str_extract(criteria, "^c\\d+"),
    criteria = fct_case_when(
      crit == "c0" ~ "Aged 18+ with 2nd dose on or before 31 Aug 2021", # paste0("Aged 18+\n with 2 doses on or before ", format(study_dates$lastvax2_date, "%d %b %Y")),
      crit == "c1" ~ "  with no missing demographic information",
      crit == "c2" ~ "  with homologous primary vaccination course of pfizer or AZ",
      crit == "c3" ~ "  and not a HSC worker",
      crit == "c4" ~ "  and not a care/nursing home resident, end-of-life or housebound",
      crit == "c5" ~ "  and vaccinated within the study period",
      TRUE ~ NA_character_
    )
  )
write_csv(data_flowchart, here("output", "data", "flowchart.csv"))