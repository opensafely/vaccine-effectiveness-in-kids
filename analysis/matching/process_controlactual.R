# # # # # # # # # # # # # # # # # # # # #
# This script:
# imports data on matched controls with the correct index_date
# filters matches which turned out to be invalid
# outputs a summary
#
# The script must be accompanied by three arguments:
# `cohort` - over12s or under12s
# `matching_round` - the matching round (1,2,3,...)
# `vaxn` - the treatment vaccination (1,2,3,...)
# # # # # # # # # # # # # # # # # # # # #


# Preliminaries ----


## Import libraries ----
library("tidyverse")
library("lubridate")
library("here")
library("glue")
library("arrow")
library("MatchIt")

## import local functions and parameters ---

source(here("analysis", "design.R"))

source(here("lib", "functions", "utility.R"))


# import command-line arguments ----

args <- commandArgs(trailingOnly = TRUE)


if (length(args) == 0) {
  # use for interactive testing
  removeobjects <- FALSE
  cohort <- "over12"
  vaxn <- as.integer("2")
  matching_round <- as.integer("2")
} else {
  removeobjects <- TRUE
  cohort <- args[[1]]
  vaxn <- as.integer(args[[2]])
  matching_round <- as.integer(args[[3]])
}

## get cohort-specific parameters study dates and parameters ----

dates <- map(study_dates[[cohort]], as.Date)
params <- study_params[[cohort]]

matching_round_date <- dates[[c(glue("control_extract_dates{vaxn}"))]][matching_round]

# get vaccine dose specific matching variable
caliper_variables <- caliper_variables[[glue("vax{vaxn}")]]
exact_variables <- exact_variables[[glue("vax{vaxn}")]]


## create output directory ----
fs::dir_create(ghere("output", cohort, "vax{vaxn}", "matchround{matching_round}", "actual"))


# Import and process data ----

## trial info for potential matches in round X
data_potential_matchstatus <- read_rds(ghere("output", cohort, "vax{vaxn}", "matchround{matching_round}", "potential", "data_potential_matchstatus.rds")) %>% filter(matched == 1L)

# use externally created dummy data if not running in the server
if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")) {

  # ideally in future this will check column existence and types from metadata,
  # rather than from a cohort-extractor-generated dummy data

  data_studydef_dummy <- read_feather(ghere("output", cohort, "vax{vaxn}", "matchround{matching_round}", "extract", "input_controlpotential.feather")) %>%
    # because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"), as.Date))

  # just reuse previous extraction for dummy run, dummy_control_potential1.feather
  # and change a few variables to simulate new index dates
  data_custom_dummy <- read_feather(ghere("lib", "dummydata", "dummy_control_potential1_{cohort}_{vaxn}.feather")) %>%
    filter(patient_id %in% data_potential_matchstatus[(data_potential_matchstatus$treated == 0L), ]$patient_id) %>%
    mutate(
      region = if_else(runif(n()) < 0.05, sample(x = unique(region), size = n(), replace = TRUE), region),
    )

  not_in_studydef <- names(data_custom_dummy)[!(names(data_custom_dummy) %in% names(data_studydef_dummy))]
  not_in_custom <- names(data_studydef_dummy)[!(names(data_studydef_dummy) %in% names(data_custom_dummy))]


  if (length(not_in_custom) != 0) {
    stop(
      paste(
        "These variables are in studydef but not in custom: ",
        paste(not_in_custom, collapse = ", ")
      )
    )
  }

  if (length(not_in_studydef) != 0) {
    stop(
      paste(
        "These variables are in custom but not in studydef: ",
        paste(not_in_studydef, collapse = ", ")
      )
    )
  }

  # reorder columns
  data_studydef_dummy <- data_studydef_dummy[, names(data_custom_dummy)]

  unmatched_types <- cbind(
    map_chr(data_studydef_dummy, ~ paste(class(.), collapse = ", ")),
    map_chr(data_custom_dummy, ~ paste(class(.), collapse = ", "))
  )[(map_chr(data_studydef_dummy, ~ paste(class(.), collapse = ", ")) != map_chr(data_custom_dummy, ~ paste(class(.), collapse = ", "))), ] %>%
    as.data.frame() %>%
    rownames_to_column()


  if (nrow(unmatched_types) > 0) {
    stop(
      # unmatched_types
      "inconsistent typing in studydef : dummy dataset\n",
      apply(unmatched_types, 1, function(row) paste(paste(row, collapse = " : "), "\n"))
    )
  }

  data_extract <- data_custom_dummy %>%
    # these variables are not included in the dummy data so join them on here
    # they're joined in the study def using `with_values_from_file`
    left_join(data_potential_matchstatus %>% filter(treated == 0L), by = c("patient_id"))
} else {
  data_extract <- read_feather(ghere("output", cohort, "matchround{matching_round}", "extract", glue("input_controlactual.feather"))) %>%
    # because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"), as.Date)) %>%
    mutate(treated = 0L) %>%
    # these variables are not included in the dummy data so join them on here
    # they're joined in the study def using `with_values_from_file`
    left_join(data_potential_matchstatus %>% filter(treated == 0L), by = c("patient_id", "treated", "trial_date", "match_id"))
}

# trial_date, match_id, matched, control
#

data_processed <-
  data_extract %>%
  mutate(
    sex = fct_case_when(
      sex == "F" ~ "Female",
      sex == "M" ~ "Male",
      # sex == "I" ~ "Inter-sex",
      # sex == "U" ~ "Unknown",
      TRUE ~ NA_character_
    ),
    prior_tests_cat = cut(prior_covid_test_frequency, breaks = c(0, 1, 3, Inf), labels = c("0", "1-2", "3+"), right = FALSE),
    region = fct_collapse(
      region,
      `East of England` = "East",
      `London` = "London",
      `Midlands` = c("West Midlands", "East Midlands"),
      `North East and Yorkshire` = c("Yorkshire and The Humber", "North East"),
      `North West` = "North West",
      `South East` = "South East",
      `South West` = "South West"
    ),

    # latest covid event before study start
    anycovid_0_date = pmax(postest_0_date, covidemergency_0_date, covidadmitted_0_date, na.rm = TRUE),
    prior_covid_infection = (!is.na(postest_0_date)) | (!is.na(covidadmitted_0_date)) | (!is.na(primary_care_covid_case_0_date)),
    vax_date = case_when(
      vaxn == 1 ~ covid_vax_any_1_date,
      vaxn == 2 ~ covid_vax_any_2_date,
    ),
    vax1_date = covid_vax_any_1_date,
    vax2_date = covid_vax_any_2_date,
    #vax1_day = as.integer(vax1_date-dates[[glue("start_date{vaxn}")]])
  )

# Define selection criteria ----
data_criteria <- data_processed %>%
  transmute(
    patient_id,
    has_age = !is.na(age),
    has_sex = !is.na(sex) & !(sex %in% c("I", "U")),
    has_imd = imd_Q5 != "Unknown",
    # has_ethnicity = !is.na(ethnicity_combined),
    has_region = !is.na(region),
    no_recentcovid30 = is.na(anycovid_0_date) | ((trial_date - anycovid_0_date) > 30),
    include = (
      has_age & has_sex & has_imd & # has_ethnicity &
        has_region &
        no_recentcovid30
    ),
  )


data_control <- data_criteria %>%
  filter(include) %>%
  select(patient_id) %>%
  left_join(data_processed, by = "patient_id") %>%
  droplevels()


data_treated <-
  left_join(
    data_potential_matchstatus %>% 
      filter(treated == 1L),
    read_rds(ghere("output", cohort, "vax{vaxn}", "treated", "data_treatedeligible.rds")) %>%
      # remove all outcome variables that appear in variables_outcome.py
      select(-any_of(events_lookup$event_var), -any_of(c("test_count", "postest_count"))),
    by = "patient_id"
  )




# check matching

matching_candidates <-
  bind_rows(data_treated, data_control) %>%
  arrange(treated, match_id, trial_date)

# print missing values
matching_candidates_missing <- map(matching_candidates, ~ any(is.na(.x)))
sort(names(matching_candidates_missing[unlist(matching_candidates_missing)]))

# rematch ----
rematch <-
  # first join on exact variables + match_id + trial_date
  inner_join(
    x = data_treated %>% select(match_id, trial_date, all_of(c(names(caliper_variables), exact_variables))),
    y = data_control %>% select(match_id, trial_date, all_of(c(names(caliper_variables), exact_variables))),
    by = c("match_id", "trial_date", exact_variables)
  )


if (length(caliper_variables) > 0) {
  # check caliper_variables are still within caliper
  rematch <- rematch %>%
    bind_cols(
      map_dfr(
        set_names(names(caliper_variables), names(caliper_variables)),
        ~ abs(rematch[[str_c(.x, ".x")]] - rematch[[str_c(.x, ".y")]]) <= caliper_variables[.x]
      )
    ) %>%
    # dplyr::if_all not in opensafely version of dplyr so use filter_at instead
    # filter(if_all(
    #   all_of(names(caliper_variables))
    # ))
    filter_at(
      all_of(names(caliper_variables)),
      all_vars(.)
    )
}

rematch <- rematch %>%
  select(match_id, trial_date) %>%
  mutate(matched = 1)

data_successful_match <-
  matching_candidates %>%
  inner_join(rematch, by = c("match_id", "trial_date", "matched")) %>%
  mutate(
    matching_round = matching_round
  ) %>%
  arrange(trial_date, match_id, treated)


###

matchstatus_vars <- c("patient_id", "match_id", "trial_date", "matching_round", "treated", "controlistreated_date")

data_successful_matchstatus <-
  data_successful_match %>%
  # keep all variables from the processed data as they are required for adjustments in the cox model
  select(all_of(matchstatus_vars), everything())

## size of dataset
print("data_successful_match treated/untreated numbers")
table(treated = data_successful_matchstatus$treated, useNA = "ifany")


## how many matches are lost?

print(glue("{sum(data_successful_matchstatus$treated)} matched-pairs kept out of {sum(data_potential_matchstatus$treated)}
           ({round(100*(sum(data_successful_matchstatus$treated) / sum(data_potential_matchstatus$treated)),2)}%)
           "))


## pick up all previous successful matches ----

if (matching_round > 1) {
  data_matchstatusprevious <-
    read_rds(ghere("output", cohort, "vax{vaxn}", "matchround{matching_round-1}", "actual", "data_matchstatus_allrounds.rds"))

  data_matchstatus_allrounds <-
    data_successful_matchstatus %>%
    select(all_of(matchstatus_vars)) %>%
    bind_rows(data_matchstatusprevious)
} else {
  data_matchstatus_allrounds <-
    data_successful_matchstatus %>%
    select(all_of(matchstatus_vars))
}

write_rds(data_matchstatus_allrounds, ghere("output", cohort, "vax{vaxn}", "matchround{matching_round}", "actual", "data_matchstatus_allrounds.rds"), compress = "gz")


# output all control patient ids for finalmatched study definition
data_matchstatus_allrounds %>%
  mutate(
    trial_date = as.character(trial_date)
  ) %>%
  filter(treated == 0L) %>% # only interested in controls as all
  write_csv(ghere("output", cohort, "vax{vaxn}", "matchround{matching_round}", "actual", "cumulative_matchedcontrols.csv.gz"))

## size of dataset
print("data_matchstatus_allrounds treated/untreated numbers")
table(treated = data_matchstatus_allrounds$treated, useNA = "ifany")



## size of dataset
print("data_successful_match treated/untreated numbers")
table(treated = data_successful_matchstatus$treated, useNA = "ifany")


## duplicate IDs
data_matchstatus_allrounds %>%
  group_by(treated, patient_id) %>%
  summarise(n = n()) %>%
  group_by(treated) %>%
  summarise(ndups = sum(n > 1)) %>%
  print()


write_rds(data_successful_match %>% filter(treated == 0L), ghere("output", cohort, "vax{vaxn}", "matchround{matching_round}", "actual", "data_successful_matchedcontrols.rds"), compress = "gz")
