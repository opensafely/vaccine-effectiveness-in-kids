# # # # # # # # # # # # # # # # # # # # #
# Purpose: Get initial information on severity of carditis events
#  - import matched data

#  - The script must be accompanied by two arguments:
#    `cohort` - over12s or under12s
#    `outcome` - the dependent variable

# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----


## Import libraries ----
library("tidyverse")
library("here")
library("glue")
library("survival")


## import local functions and parameters ---

source(here("analysis", "design.R"))
source(here("lib", "functions", "utility.R"))
source(here("lib", "functions", "survival.R"))


# import command-line arguments ----

args <- commandArgs(trailingOnly = TRUE)


if (length(args) == 0) {
  # use for interactive testing
  removeobjects <- FALSE
  cohort <- "over12"
  vaxn <- as.integer("2")
} else {
  removeobjects <- TRUE
  cohort <- args[[1]]
  vaxn <- as.integer(args[[2]])
}

## get cohort-specific parameters study dates and parameters ----

dates <- map(study_dates[[cohort]], as.Date)
params <- study_params[[cohort]]

# derive symbolic arguments for programming with

# create output directories ----

output_dir <- ghere("output", cohort, "vax{vaxn}", "carditis_severity")
fs::dir_create(output_dir)


data_matched <- read_rds(ghere("output", cohort, "vax{vaxn}", "match", "data_matched.rds"))

## import baseline data, restrict to matched individuals and derive time-to-event variables
data_matched_myocarditis <-
  data_matched %>%
  select(
    # select only variables needed for models to save space
    patient_id, treated, trial_date, match_id,
    controlistreated_date,
    vax_date,
    death_date, dereg_date, coviddeath_date, noncoviddeath_date,
    myocarditis_date,
    emergency_date,
    admitted_unplanned_date,
    emergencyhosp_date,
  ) %>%
  mutate(
    
    # follow-up time is up to and including censor date
    censor_date = pmin(
      dereg_date,
      # vax2_date-1, # -1 because we assume vax occurs at the start of the day
      death_date,
      dates[[c(glue("followupend_date{vaxn}"))]],
      trial_date + maxfup - 1,
      na.rm = TRUE
    ),
    matchcensor_date = pmin(censor_date, controlistreated_date - 1, na.rm = TRUE), # new censor date based on whether control gets treated or not
    myocarditis_outcome = censor_indicator(myocarditis_date, matchcensor_date),
    emergency_outcome = censor_indicator(emergency_date, matchcensor_date),
    admitted_unplanned_outcome = censor_indicator(admitted_unplanned_date, matchcensor_date),
    emergencyhosp_outcome = censor_indicator(emergencyhosp_date, matchcensor_date),
    death_outcome = censor_indicator(death_date, matchcensor_date),
  ) %>%
  filter(myocarditis_outcome==T) 

myocarditis_dates <-
  data_matched_myocarditis %>%
  select(
    # select only variables needed for models to save space
    patient_id, 
    treated,
    myocarditis_date,
  )

write_csv(myocarditis_dates, fs::path(output_dir, "myocarditis_dates.csv"))

severity_myocarditis <- 
  data_matched_myocarditis %>%
  summarise(myocarditis = sum(myocarditis_outcome),
    across(
    ends_with("outcome"),
    ~ sum(.x) / myocarditis * 100
  ))

write_csv(severity_myocarditis, fs::path(output_dir, "myocarditis_severity.csv"))


## import baseline data, restrict to matched individuals and derive time-to-event variables
data_matched_pericarditis <-
  data_matched %>%
  select(
    # select only variables needed for models to save space
    patient_id, treated, trial_date, match_id,
    controlistreated_date,
    vax_date,
    death_date, dereg_date, coviddeath_date, noncoviddeath_date,
    pericarditis_date,
    emergency_date,
    admitted_unplanned_date,
    emergencyhosp_date,
  ) %>%
  mutate(
    
    # follow-up time is up to and including censor date
    censor_date = pmin(
      dereg_date,
      # vax2_date-1, # -1 because we assume vax occurs at the start of the day
      death_date,
      dates[[c(glue("followupend_date{vaxn}"))]],
      trial_date + maxfup - 1,
      na.rm = TRUE
    ),
    matchcensor_date = pmin(censor_date, controlistreated_date - 1, na.rm = TRUE), # new censor date based on whether control gets treated or not
    pericarditis_outcome = censor_indicator(pericarditis_date, matchcensor_date),
    emergency_outcome = censor_indicator(emergency_date, matchcensor_date),
    admitted_unplanned_outcome = censor_indicator(admitted_unplanned_date, matchcensor_date),
    emergencyhosp_outcome = censor_indicator(emergencyhosp_date, matchcensor_date),
    death_outcome = censor_indicator(death_date, matchcensor_date),
  ) %>%
  filter(pericarditis_outcome==T) 

pericarditis_dates <-
  data_matched_pericarditis %>%
  select(
    # select only variables needed for models to save space
    patient_id, 
    treated,
    pericarditis_date,
  )

write_csv(pericarditis_dates, fs::path(output_dir, "pericarditis_dates.csv"))

severity_pericarditis <-
  data_matched_pericarditis %>%
  summarise(pericarditis = sum(pericarditis_outcome),
            across(
              ends_with("outcome"),
              ~ sum(.x) / pericarditis * 100
            ))
write_csv(severity_pericarditis, fs::path(output_dir, "pericarditis_severity.csv"))

