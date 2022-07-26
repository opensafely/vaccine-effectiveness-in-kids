# # # # # # # # # # # # # # # # # # # # #
# This script:
# imports data on matched controls with the correct index_date
# filters matches which turned out to be invalid
# outputs a summary
#
# The script must be accompanied by two arguments:
# `agegroup` - over12s or under12s
# `matching_round` - the matching round (1,2,3,...)

# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----


# import command-line arguments ----

args <- commandArgs(trailingOnly=TRUE)


if(length(args)==0){
  # use for interactive testing
  removeobjects <- FALSE
  matching_round <- 1
  agegroup <- "over12"
} else {
  #FIXME replace with actual eventual action variables
  removeobjects <- TRUE
  agegroup <- args[[1]]
  matching_round <- args[[2]]
}

# define vaccination of interest
if(agegroup=="under12") treatment <- "pfizerC"
if(agegroup=="over12") treatment <- "pfizerA"


## Import libraries ----
library('tidyverse')
library('here')
library('arrow')
library('glue')
library('MatchIt')


## Import custom user functions from lib

source(here("lib", "functions", "utility.R"))


## import matching variables ----

#FIXME pick these up automatically from.. somewhere
exact_variables <- c("age", "sex", "region")
caliper_variables <- character()

# create output directories ----

output_dir <- here("output", "match")
fs::dir_create(output_dir)

## import globally defined study dates and convert to "Date"
study_dates <-
  jsonlite::read_json(path=here("lib", "design", "study-dates.json")) %>%
  map(as.Date)


# use externally created dummy data if not running in the server
# check variables are as they should be
if(Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")){
  
  # don't bother with proper checking, because this was done for study_definition_control
  
  
  data_custom_dummy <- read_feather(here("lib", "dummydata", "dummyinput.feather")) %>%
    mutate(
      msoa = sample(factor(c("1", "2")), size=n(), replace=TRUE) # override msoa so matching success more likely
    ) %>%
    # filter(
    #   !casecontrol
    # ) %>% 
    select(-casecontrol)
  
  data_control_wrongindex <- 
    read_rds(fs::path(output_dir, glue("data_potential_matched{matching_round}.rds"))) %>% 
    filter(treated==0L) %>%
    select(patient_id, match_id, trial_date)
  
  
  data_control <- data_control_wrongindex %>% 
    left_join(data_custom_dummy, by="patient_id")
  
} else {
  data_control <- read_feather(here("output", glue("input_match_control{matching_round}.feather"))) %>%
    #because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"),  as.Date))
}


## implement the same post-extract processing as done in data_process ----
# FIXME this needs to match processing in data_process so if data_process is updated then this should be updated too
# consider using a single script / function to do this

data_control <- data_control %>%
  mutate(
    
    sex = fct_case_when(
      sex == "F" ~ "Female",
      sex == "M" ~ "Male",
      #sex == "I" ~ "Inter-sex",
      #sex == "U" ~ "Unknown",
      TRUE ~ NA_character_
    ),
    

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
    
  )


data_treated <- read_rds(fs::path(output_dir, glue("data_potential_matched{matching_round}.rds"))) %>% filter(treated==1L)


matching_candidates <- 
  bind_rows(
    data_treated, 
    data_control %>% mutate(treated=0L)
  ) %>%
  arrange(trial_date, match_id, treated)


## Easiest thing is to rematch, with additional exact matching on "match_id" and "trial_date"
# but will be slow
# note that match id is only unique _within_ trial_date, it is not a global identifier

## alternatively, just check for any changes in matching variables in the control group.
# however for any caliper matching it becomes more complicated

# run matching algorithm
obj_matchit <-
  matchit(
    formula = treated ~ 1,
    data = matching_candidates,
    method = "nearest", distance = "glm", # these two options don't really do anything because we only want exact + caliper matching
    replace = FALSE,
    estimand = "ATT",
    exact = c("match_id", "trial_date", exact_variables), 
    # caliper = caliper_variables, std.caliper=FALSE, 
    m.order = "data", # data is sorted on (effectively random) patient ID
    #verbose = TRUE,
    ratio = 1L # irritatingly you can't set this for "exact" method, so have to filter later
  )


data_matchstatus <-
  tibble(
    patient_id = matching_candidates$patient_id,
    matched = !is.na(obj_matchit$subclass),
    #thread_id = data_thread$thread_id,
    match_id = as.integer(as.character(obj_matchit$subclass)),
    treated = obj_matchit$treat,
    weight = obj_matchit$weights,
    trial_time = matching_candidates$trial_time,
    trial_date = matching_candidates$trial_date,
  ) %>%
  arrange(match_id, treated)


#actual legitimate matches 
data_actual_matched <- 
  matching_candidates %>% 
  filter(
    patient_id %in% (data_matchstatus %>% filter(matched) %>% pull (patient_id)) 
  )


write_rds(data_matchstatus, fs::path(output_dir, glue("data_actual_matchstatus{matching_round}.rds")), compress="gz")


write_rds(data_actual_matched, fs::path(output_dir, "data_actual_matched{matching_round}.rds"), compress="gz")

## how many matches were thrown away ----

print(paste0(nrow(data_actual_matched)/2, " legitimate matched pairs, out of ", nrow(matching_candidates)/2, " total matched pairs") )
print(paste0((nrow(matching_candidates) - nrow(data_actual_matched))/2, " pairs thrown away (", 100*(nrow(matching_candidates) - nrow(data_actual_matched))/nrow(matching_candidates), "%)"))



