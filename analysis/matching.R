
# # # # # # # # # # # # # # # # # # # # #
# This script:
# imports processed data
# chooses matching sets for each sequential trial
# outputs matching summary
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
  agegroup <- "over12"
  matching_round <- "1"
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
library('glue')
library('MatchIt')

## Import custom user functions from lib

source(here("lib", "functions", "utility.R"))

# create output directories ----

output_dir <- here("output", "match")
fs::dir_create(output_dir)

## import globally defined study dates and convert to "Date"
study_dates <-
  jsonlite::read_json(path=here("lib", "design", "study-dates.json")) %>%
  map(as.Date)



## import treated populations ----
data_treated <- read_rds(here("output", "data", "data_treated_eligible.rds")) %>% mutate(treated=1L)

## import control populations ----
data_control <- read_rds(here("output", "data", glue("data_control_potential{matching_round}.rds"))) %>% mutate(treated=0L)

# remove already-matched people from previous mathcing rounds
if(matching_round>1){
  
  previous_round <- as.integer(matching_round)-1L
  
  data_matchstatusprevious <- read_rds(fs::path(output_dir, glue("data_matchstatus_allrounds{previous_round}.rds"))) 
    filter(matched) %>%
    select(patient_id, treated)
  
  data_treated <- 
    data_treated %>%
    anti_join(
      data_matchstatusprevious, by=c("patient_id", "treated")
    )
  
  data_control <- 
    data_control %>%
    anti_join(
      data_matchstatusprevious, by=c("patient_id", "treated")
    )
  
}


## import matching variables ----

#FIXME pick these up automatically from... somewhere
exact_variables <- c("age", "sex", "region")
caliper_variables <- character()

data_eligible <-
  bind_rows(data_treated, data_control) %>%
  mutate(
    
    treatment_date = if_else(vax1_type %in% treatment, vax1_date, as.Date(NA))-1, # -1 because we assume vax occurs at the start of the day

    # person-time is up to and including censor date #FIXME to include dereg and death dates
    censor_date = pmin(
      #dereg_date,
      #competingtreatment_date-1, # -1 because we assume vax occurs at the start of the day
      vax2_date-1, # -1 because we assume vax occurs at the start of the day
      #death_date,
      study_dates[[glue("{agegroup}followupend_date")]],
      na.rm=TRUE
    ),

    #FIXME to include dereg and death dates
    noncompetingcensor_date = pmin(
      #dereg_date,
      #competingtreatment_date-1, # -1 because we assume vax occurs at the start of the day
      vax2_date-1, # -1 because we assume vax occurs at the start of the day
      na.rm=TRUE
    ),

    # assume vaccination occurs at the start of the day, and all other events occur at the end of the day.

    
    ## FIXME kept these comments, as the code can be resused once the final cohort is chosen
    ## tte = time-to-event, and always indicates time from study start date
    # day0_date = study_dates$index_date-1, # day before the first trial date
    ## possible competing events
    # tte_coviddeath = tte(day0_date, coviddeath_date, noncompetingcensor_date, na.censor=TRUE),
    # tte_noncoviddeath = tte(day0_date, noncoviddeath_date, noncompetingcensor_date, na.censor=TRUE),
    # tte_death = tte(day0_date, death_date, noncompetingcensor_date, na.censor=TRUE),
    # 
    # tte_censor = tte(day0_date, censor_date, censor_date, na.censor=TRUE),
    # 
    # tte_treatment = tte(day0_date, treatment_date-1, censor_date, na.censor=TRUE),
    # tte_competingtreament = tte(day0_date, competingtreatment_date-1, censor_date, na.censor=TRUE),
    # tte_vax1 = tte(day0_date, vax1_date-1, censor_date, na.censor=TRUE)

  ) 

if(removeobjects) rm(data_eligible0)

local({

  ## sequential trial matching routine is as follows:
  # each daily trial includes all n people who were vaccinated on that day (treated=1) and
  # a random sample of n controls (treated=0) who:
  # - had not been vaccinated on or before that day (still at risk of treatment);
  # - had not experienced covid recently (within 90 days); TODO; FIXME
  # - still at risk of an outcome (not deregistered or dead); 
  # - had not already been selected as a control in a previous trial


  # set maximum number of daily trials
  # time index is relative to "start date"
  # trial index start at one, not zero. i.e., study start date is "day 1" (but the _time_ at the start of study start date is zero)
  start_trial_time <- 0
  end_trial_time <- as.integer(study_dates[[glue("{agegroup}end_date")]] + 1 - study_dates[[glue("{agegroup}start_date")]])
  trials <- seq(start_trial_time+1, end_trial_time, 1) 
  
  # initialise list of candidate controls
  candidate_ids0 <- data_control$patient_id

  # initialise matching summary data
  data_treated <- NULL
  data_matched <- NULL

  already_stopped <- FALSE

  #trial=1
  for(trial in trials){

    cat("matching trial ", trial, "\n")
    trial_time <- trial-1
    trial_date <- study_dates[[glue("{agegroup}start_date")]]+trial_time

    data_treated_i <-
      data_eligible %>%
      filter(
        # select treated
        treated==1L,
        (censor_date > trial_date) | is.na(censor_date),
        # select people vaccinated on trial day i
        treatment_date == trial_date
        ) %>% 
      transmute(
        patient_id,
        treated,
        trial_time=trial_time,
        trial_date=trial_date
      )
    
    # append total treated on trial day i to all previous treated people
    data_treated <- bind_rows(data_treated, data_treated_i)

    # set of people boosted on trial day, + their candidate controls
    
    data_control_i <-
      data_eligible %>%
      filter(
        # select controls
        treated==0L,
        # remove anyone already censored
        (censor_date > trial_date) | is.na(censor_date),
        # remove anyone already vaccinated
        (treatment_date > trial_date) | is.na(treatment_date),
        # select only people not already selected as a control
        patient_id %in% candidate_ids0
      ) %>%
      transmute(
        patient_id,
        treated,
        trial_time=trial_time,
        trial_date=trial_date
      )
    
    
    n_treated_all <- nrow(data_treated_i)
    
    if(n_treated_all<1 | already_stopped) {
      message("Skipping trial ", trial, " - No treated people eligible for inclusion.")
      next
    }
  
    matching_candidates_i <- 
      bind_rows(data_treated_i, data_control_i) %>%
      left_join(
        data_eligible %>% 
          select(
            patient_id, 
            all_of(
              exact_variables#, 
              #names(caliper_variables)
            ),
        ),
        by = "patient_id"
      )
    

    safely_matchit <- purrr::safely(matchit)
    
    # run matching algorithm
    obj_matchit_i <-
      safely_matchit(
        formula = treated ~ 1,
        data = matching_candidates_i,
        method = "nearest", distance = "glm", # these two options don't really do anything because we only want exact + caliper matching
        replace = FALSE,
        estimand = "ATT",
        exact = exact_variables,
       # caliper = caliper_variables, std.caliper=FALSE,
        m.order = "data", # data is sorted on (effectively random) patient ID
        #verbose = TRUE,
        ratio = 1L # irritatingly you can't set this for "exact" method, so have to filter later
      )[[1]]

    
    if(is.null(obj_matchit_i) | already_stopped) {
      message("Terminating trial sequence at trial ", trial, " - No exact matches found.")
      already_stopped <- TRUE
      next
    }
    
    
    
    data_matchstatus_i <-
      if(is.null(obj_matchit_i)){
        tibble(
          patient_id = matching_candidates_i$patient_id,
          matched = FALSE,
          #thread_id = data_thread$thread_id,
          match_id = NA_integer_,
          treated = matching_candidates_i$treated,
          weight = 0,
          trial_time = trial_time,
          trial_date = trial_date,
        )
      } else {
          tibble(
            patient_id = matching_candidates_i$patient_id,
            matched = !is.na(obj_matchit_i$subclass),
            #thread_id = data_thread$thread_id,
            match_id = as.integer(as.character(obj_matchit_i$subclass)),
            treated = obj_matchit_i$treat,
            weight = obj_matchit_i$weights,
            trial_time = trial_time,
            trial_date = trial_date,
          ) 
      } %>%
      arrange(match_id, treated)
    
    
    
    # summary info for recruited people
    # - one row per person
    # - match_id is within matching_i
    data_matched_i <-
      data_matchstatus_i %>%
      filter(!is.na(match_id)) %>% # remove unmatched people. equivalent to weight != 0
      arrange(match_id, desc(treated)) %>%
      left_join(
        data_eligible %>% select(patient_id, censor_date, treatment_date),
        by = "patient_id"
      ) %>%
      group_by(match_id) %>%
      mutate(
        controlistreated_date = treatment_date[treated==0], # this only works because of the group_by statement above! do not remove group_by statement!
        matchcensor_date = pmin(censor_date, controlistreated_date, na.rm=TRUE), # new censor date based on whether control gets treated or not
      ) %>%
      ungroup()

    n_treated_matched <- sum(data_matched_i$treated)

    # append matched data to matches from previous trials
    data_matched <- bind_rows(data_matched, data_matched_i)
    
    #update list of candidate controls to those who have not already been recruited
    candidate_ids0 <- candidate_ids0[!(candidate_ids0 %in% data_matched_i$patient_id)]

  }

  #remove trial_time and trial_date counters created by the loop
  trial_time <- NULL
  trial_date <- NULL

  data_matched <-
    data_matched %>%
    transmute(
      patient_id, 
      match_id, 
      matched=1L, 
      control=1L-treated, 
      trial_time, 
      trial_date, 
      controlistreated_date, 
      matchcensor_date
    )

  data_matchstatus <<-
    data_treated %>%
    left_join(data_matched %>% filter(control==0L), by=c("patient_id", "trial_time", "trial_date")) %>%
    mutate(
      matched = replace_na(matched, 0L), # 1 if matched, 0 if unmatched
      control = if_else(matched==1L, 0L, NA_integer_) # 0 if matched control, 1 if matched treated, NA if unmatched treated
    ) %>%
    bind_rows(
      data_matched %>% filter(control==1L) %>% mutate(treated=0L)
    )
})

# output matching status ----
write_rds(data_matchstatus, fs::path(output_dir, glue("data_potential_matchstatus{matching_round}.rds")), compress="gz")


# output csv for subsequent study definition
data_matchstatus %>% 
  filter(control==1L) %>% 
  select(patient_id, trial_date, match_id) %>%
  mutate(
    trial_date=as.character(trial_date)
  ) %>%
  write_csv(fs::path(output_dir, glue("potential_matched_controls{matching_round}.csv.gz")))

# number of treated/controls per trial
with(data_matchstatus %>% filter(matched==1), table(trial_time, treated))

# max trial date
print(paste0("max trial day is ", as.integer(max(data_matchstatus %>% filter(matched==1) %>% pull(trial_time), na.rm=TRUE))))



data_matched <- 
  data_matchstatus %>%
  filter(matched==1L) %>%
  left_join(
    data_eligible %>%
    select(
      patient_id,
      all_of(
        exact_variables#, 
        #names(caliper_variables)
      ),
    ),
    by="patient_id"
  ) 

## output dataset containing all matched pairs + matching factors
write_rds(data_matched, fs::path(output_dir, glue("data_potential_matched{matching_round}.rds")), compress="gz")
