# # # # # # # # # # # # # # # # # # # # #
# This script:
# creates metadata for aspects of the study design
# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----

## Import libraries ----
library("tidyverse")
library("here")

## create output directories ----
fs::dir_create(here("lib", "design"))

# rounding threshold

threshold <- 6

# number of matching rounds to perform
n_matching_rounds <- 6


# define key dates ----

study_dates <- lst(
  over12 = lst(
    start_date1 = "2021-09-20", # start of vaccine eligibility for non-high-risk 12-15 year olds monday 20 september 2021, adult pfizer dose licensed
    end_date1 = "2021-12-26", # end of recruitment (14 weeks later)
    followupend_date1 = "2022-07-24", # end of follow-up
    start_date2 = "2021-12-13", # 12 weeks after the start of vaccine eligibility for non-high-risk 12-15 year olds monday 20 september 2021, adult pfizer dose licensed
    end_date2 = "2022-03-14", # end of recruitment (14 weeks later)
    followupend_date2 = "2022-04-10", # end of follow-up
  ),
  under12 = lst(
    start_date1 = "2022-04-04", # start of vaccine eligibility for non-high-risk 5-11 year olds monday 4 APril 2022, child pfizer dose licensed
    end_date1 = "2022-07-10", # end of recruitment (14 weeks later)
    followupend_date1 = "2022-07-24", # end of follow-up
    start_date2 = "2022-06-27", # 12 weeks after the start of vaccine eligibility for non-high-risk 5-11 year olds monday 4 APril 2022, child pfizer dose licensed
    end_date2 = "2022-09-26", # end of recruitment (14 weeks later)
    followupend_date2 = "2022-10-10", # end of follow-up
  ),
  testend_date = "2022-03-31", # last day of public testing in England
)

extract_increment <- 14

study_dates$over12$control_extract_dates1 <- as.Date(study_dates$over12$start_date1) + (0:26) * extract_increment
study_dates$under12$control_extract_dates1 <- as.Date(study_dates$under12$start_date1) + (0:26) * extract_increment
study_dates$over12$control_extract_dates2 <- as.Date(study_dates$over12$start_date2) + (0:26) * extract_increment
study_dates$under12$control_extract_dates2 <- as.Date(study_dates$under12$start_date2) + (0:26) * extract_increment
# write to json so that both R and python (study defs) can easily pick up
jsonlite::write_json(study_dates, path = here("lib", "design", "study-dates.json"), auto_unbox = TRUE, pretty = TRUE)

# define study parameters used in study definition
study_params <- lst(

  # over 12 params
  over12 = lst(
    minage = 12,
    maxage = 15,
    treatment = "pfizerA",
    product_name = "COVID-19 mRNA Vaccine Comirnaty 30micrograms/0.3ml dose conc for susp for inj MDV (Pfizer)"
  ),

  # under 12 params
  under12 = lst(
    minage = 5,
    maxage = 11,
    treatment = "pfizerC",
    product_name = "COVID-19 mRNA Vaccine Comirnaty Children 5-11yrs 10mcg/0.2ml dose conc for disp for inj MDV (Pfizer)"
  )
)

# write to json so that both R and python (study defs) can easily pick up
jsonlite::write_json(study_params, path = here("lib", "design", "study-params.json"), auto_unbox = TRUE, pretty = TRUE)


# define outcomes ----

events_lookup <- tribble(
  ~event, ~event_var, ~event_descr,

  # other
  "test", "covid_test_date", "SARS-CoV-2 test",
  "dereg", "dereg_date", "Deregistration",
  "primary_care_covid_case", "primary_care_covid_case_date", "Primary care COVID-19",

  # effectiveness
  "postest", "postest_date", "Positive SARS-CoV-2 test",
  "covidemergency", "covidemergency_date", "COVID-19 A&E attendance",
  "covidemergencyhosp", "covidemergencyhosp_date", "Admission from COVID-19 A&E",
  "covidadmitted", "covidadmitted_date", "COVID-19 hospitalisation",
  # "noncovidadmitted", "noncovidadmitted_date", "Non-COVID-19 hospitalisation",
  "covidadmittedproxy1", "covidadmittedproxy1_date", "COVID-19 hospitalisation (A&E proxy)",
  "covidadmittedproxy2", "covidadmittedproxy2_date", "COVID-19 hospitalisation (A&E proxy v2)",
  "covidcritcare", "covidcritcare_date", "COVID-19 critical care",
  "coviddeath", "coviddeath_date", "COVID-19 death",
  "noncoviddeath", "noncoviddeath_date", "Non-COVID-19 death",
  "death", "death_date", "Any death",


  # safety
  # "emergencyhosp", "emergencyhosp_date", "Admission from A&E",
  "emergency", "emergency_date", "A&E attendance",
  "admitted_unplanned", "admitted_unplanned_date", "Unplanned hospitalisation",
  "pericarditis", "pericarditis_date", "A&E attendance or hospital admittance with pericarditis",
  "myocarditis", "myocarditis_date", "A&E attendance or hospital admittance with myocarditis",
  "fracture", "fracture_date", "Fracture",
  "fractureemergency", "fractureemergency_date", "Fracture A&E attendance",
  "fractureadmitted", "fractureadmitted_date", "Fracture hospitalisation",
  "fracturedeath", "fracturedeath_date", "Fracture death",
  "outcome_vax_2", "outcome_vax_2_date", "Second vax",
)


## lookups to convert coded variables to full, descriptive variables ----

recoder <-
  lst(
    subgroups = c(
      `Main` = "all",
      `Prior SARS-CoV-2 infection` = "prior_covid_infection"
    ),
    status = c(
      `Unmatched` = "unmatched",
      `Matched` = "matched"
    ),
    treated = c(
      `Unvaccinated` = "0",
      `Vaccinated` = "1"
    ),
    outcome = set_names(events_lookup$event, events_lookup$event_descr),
    all = c(` ` = "all"),
    prior_covid_infection = c(
      `No prior SARS-CoV-2 infection` = "FALSE",
      `Prior SARS-CoV-2 infection` = "TRUE"
    ),
  )


fup_params <- lst(
  # length of baseline period
  baselinedays = 14,
  # length of follow-up period
  postbaselinedays = 14,
  # number of follow-up periods
  postbaselineperiods = 9,
  # where to split follow-up time after recruitment
  postbaselinecuts = c(0, baselinedays, baselinedays + (1:postbaselineperiods) * postbaselinedays),
  # maximum follow-up
  maxfup = max(postbaselinecuts),
  # the following params are for covidtests only
  # number of prebaseline periods to summarise test behaviour
  prebaselineperiods = 3,
  covidtestcuts = c(seq(-prebaselineperiods * postbaselinedays, -postbaselinedays, postbaselinedays), postbaselinecuts),
  # number of recurring events for the covidtests study definition
  n_any = 10,
  n_pos = 5
)

jsonlite::write_json(fup_params, path = here("lib", "design", "fup-params.json"), auto_unbox = TRUE, pretty = TRUE)


# split into named objects until scripts updated
for (i in 1:length(fup_params)) {
  assign(names(fup_params)[i], fup_params[[i]])
}




# matching variables ----

# exact variables
exact_variables <- lst(
  vax1 = c(
    "age_aug21",
    "region",
    "sex",
    "prior_covid_infection",
    "prior_tests_cat",
    "imd_Q5",
    "vax_compliant_exl_mmr",
    "type_MMR",
    NULL
  ),
  vax2 = c(
    "age_aug21",
    "region",
    "sex",
    "prior_covid_infection",
    "prior_tests_cat",
    "imd_Q5",
    "vax_compliant_exl_mmr",
    "type_MMR",
    NULL
  )
)

# caliper variables
caliper_variables <- lst(
  vax1 = c(
    NULL
  ),
  vax2 = c(
    vax1_date = 7,
    NULL
  )
)
matching_variables <- c(exact_variables, names(caliper_variables))
