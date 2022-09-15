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
  over12end_date = "2021-12-19", # end of recruitment (13 weeks later)
  over12followupend_date = "2022-01-02", # end of follow-up
  
  under12start_date = "2022-04-04", #start of recruitment monday 4 april moderna licensed for for under 12yo in england
  under12end_date = "2022-07-03", # end of recruitment (13 weeks later)
  under12followupend_date = "2022-07-10", # end of follow-up

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


postbaselinedays<-14
# where to split follow-up time after recruitment
postbaselinecuts <- c(postbaselinedays*0,postbaselinedays*1,postbaselinedays*2,postbaselinedays*3,postbaselinedays*4,postbaselinedays*5,postbaselinedays*6,postbaselinedays*7)

# what matching variables
exact_variables <- c(

  "age",
  "region",
  "sex",
  "prior_covid_infection",
  NULL
)
caliper_variables <- c(
  age = 1,
  NULL
)
matching_variables <- c(exact_variables, names(caliper_variables))
