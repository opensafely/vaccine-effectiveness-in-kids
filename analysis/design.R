# # # # # # # # # # # # # # # # # # # # #
# This script:
# creates metadata for aspects of the study design
# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----

## Import libraries ----
library('tidyverse')
library('here')
## create output directories ----
fs::dir_create(here("lib", "design"))

# define key dates ----

study_dates <- lst(
  index_date = "2021-09-20", # index date for dates as "time since index date" format
  over12start_date = "2021-09-20", #start of recruitment monday 20 september pfizer licensed for for over 12yo in england
  over12end_date = "2021-12-20", # end of recruitment (13 weeks later)
  #pfizerfollowend_date = "2021-12-31", # end of follow-up

  under12start_date = "2022-04-04", #start of recruitment monday 4 april moderna licensed for for under 12yo in england
  under12end_date = "2022-07-04", # end of recruitment (13 weeks later)
  #modernafollowend_date = "2021-12-31", # end of follow-up

  studyend_date = "2022-07-13", # end of follow-up

  lastvax2_date = "2022-06-01", # don't recruit anyone with second vaccination after this date

  firstover12_date = "2021-09-20", # first pfizer vaccination in national roll-out
  firsunder12_date = "2022-04-04", # first az vaccination in national roll-out
)


jsonlite::write_json(study_dates, path = here("lib", "design", "study-dates.json"), auto_unbox=TRUE, pretty =TRUE)

# define outcomes ----

events_lookup <- tribble(
  ~event, ~event_var, ~event_descr,

  # other
  "test", "covid_test_date", "SARS-CoV-2 test",

  # effectiveness
  "postest", "positive_test_date", "Positive SARS-CoV-2 test",
  "covidemergency", "covidemergency_date", "COVID-19 A&E attendance",
  "covidadmitted", "covidadmitted_date", "COVID-19 hospitalisation",
  "noncovidadmitted", "noncovidadmitted_date", "Non-COVID-19 hospitalisation",
  "covidadmittedproxy1", "covidadmittedproxy1_date", "COVID-19 hospitalisation (A&E proxy)",
  "covidadmittedproxy2", "covidadmittedproxy2_date", "COVID-19 hospitalisation (A&E proxy v2)",
  "covidcc", "covidcc_date", "COVID-19 critical care",
  "coviddeath", "coviddeath_date", "COVID-19 death",
  "noncoviddeath", "noncoviddeath_date", "Non-COVID-19 death",
  "death", "death_date", "Any death",

  # safety
  "admitted", "admitted_unplanned_1_date", "Unplanned hospitalisation",
  "emergency", "emergency_date", "A&E attendance",
)

write_rds(events_lookup, here("lib", "design", "event-variables.rds"))



treatement_lookup <-
  tribble(
    ~treatment, ~treatment_descr,
    "pfizer", "BNT162b2",
    "az", "ChAdOx1-S",
    "moderna", "mRNA-1273",
    "pfizer-pfizer", "BNT162b2",
    "az-az", "ChAdOx1-S",
    "moderna-moderna", "mRNA-1273"
  )

write_rds(treatment_lookup, here("lib", "design", "treatment-lookup.rds"))


postbaselinedays<-14
# where to split follow-up time after recruitment
postbaselinecuts <- c(postbaselinedays*0,postbaselinedays*1,postbaselinedays*2,postbaselinedays*3,postbaselinedays*4,postbaselinedays*5,postbaselinedays*6,postbaselinedays*7)
write_rds(postbaselinecuts, here("lib", "design", "postbaselinecuts.rds"))

# what matching variables
exact_variables <- c(

  "ageband",
  "cev_cv",
  "vax12_type",
  #"vax2_week",
  "region",
  #"sex",
  #"cev_cv",

  #"multimorb",
  "prior_covid_infection",
  #"immunosuppressed",
  #"status_hospplanned"
  NULL
)
write_rds(exact_variables, here("lib", "design", "exact_variables.rds"))

caliper_variables <- c(
  age = 1,
  vax2_day = 7,
  NULL
)
write_rds(caliper_variables, here("lib", "design", "caliper_variables.rds"))

matching_variables <- c(exact_variables, names(caliper_variables))
write_rds(matching_variables, here("lib", "design", "matching_variables.rds"))

# cut-off for rolling 7 day average, that determines recruitment period
recruitment_period_cutoff <- 50
write_rds(recruitment_period_cutoff, here("lib", "design", "recruitment_period_cutoff.rds"))