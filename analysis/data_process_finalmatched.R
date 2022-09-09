######################################

# This script:
# imports data extracted by the cohort extractor (or dummy data)
# fills in unknown ethnicity from GP records with ethnicity from SUS (secondary care)
# tidies missing values
# standardises some variables (eg convert to factor) and derives some new ones
# organises vaccination date data to "vax X type", "vax X date" (rather than "pfizer X date", "az X date", ...)
######################################


# import command-line arguments ----

args <- commandArgs(trailingOnly=TRUE)


if(length(args)==0){
  # use for interactive testing
  removeobjects <- FALSE
  agegroup <- "over12"
} else {
  #FIXME replace with actual eventual action variables
  removeobjects <- TRUE
  agegroup <- args[[1]]
}

# define vaccination of interest
if(agegroup=="under12") treatment <- "pfizerC"
if(agegroup=="over12") treatment <- "pfizerA"

# Import libraries ----
library('tidyverse')
library('lubridate')
library('arrow')
library('here')
library('glue')

source(here("lib", "functions", "utility.R"))

source(here("analysis","design.R"))

# import globally defined study dates and convert to "Date"
study_dates <-
  jsonlite::read_json(path=here("lib", "design", "study-dates.json")) %>%
  map(as.Date)

# output processed data to rds ----

fs::dir_create(here("output", "data"))


# process ----

# use externally created dummy data if not running in the server
# check variables are as they should be
if(Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")){

  data_studydef_dummy <- read_feather(here("output", "input_finalmatched.feather")) %>%
    #because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"),  as.Date))
  
  data_custom_dummy <- read_feather(fs::path("lib", "dummydata", glue("dummy_finalmatched.feather")))
  
  
  not_in_studydef <- names(data_custom_dummy)[!( names(data_custom_dummy) %in% names(data_studydef_dummy) )]
  not_in_custom  <- names(data_studydef_dummy)[!( names(data_studydef_dummy) %in% names(data_custom_dummy) )]
  
  
  if(length(not_in_custom)!=0) stop(
    paste(
      "These variables are in studydef but not in custom: ",
      paste(not_in_custom, collapse=", ")
    )
  )
  
  if(length(not_in_studydef)!=0) stop(
    paste(
      "These variables are in custom but not in studydef: ",
      paste(not_in_studydef, collapse=", ")
    )
  )
  
  # reorder columns
  data_studydef_dummy <- data_studydef_dummy[,names(data_custom_dummy)]
  
  unmatched_types <- cbind(
    map_chr(data_studydef_dummy, ~paste(class(.), collapse=", ")),
    map_chr(data_custom_dummy, ~paste(class(.), collapse=", "))
  )[ (map_chr(data_studydef_dummy, ~paste(class(.), collapse=", ")) != map_chr(data_custom_dummy, ~paste(class(.), collapse=", ")) ), ] %>%
    as.data.frame() %>% rownames_to_column()
  
  
  if(nrow(unmatched_types)>0) stop(
    #unmatched_types
    "inconsistent typing in studydef : dummy dataset\n",
    apply(unmatched_types, 1, function(row) paste(paste(row, collapse=" : "), "\n"))
  )
  
  data_outcomes <- data_custom_dummy 
  

} else {
  data_outcomes <- read_feather(here("output", "input_finalmatched.feather")) %>%
    #because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"),  as.Date))
}


data_matchstatus <- read_rds(here("output", "match", glue("data_matchstatus_allrounds{n_matching_rounds}.rds"))) 

# import data for treated group and select those who were successfully matched

data_treated <- 
  left_join(
    data_matchstatus %>% filter(treated==1L),
    read_rds(here("output", "data", "data_treated_eligible.rds")),
    by="patient_id"
  ) 


# import final dataset of matched controls, including matching variables
data_control <- 
  map_dfr(
    seq_len(n_matching_rounds), 
    ~read_rds(here("output", "match", glue("data_successful_matchedcontrols{.x}.rds"))),
    .id="matching_round_id"
  ) %>%
  # merge with outcomes data
  left_join(
    data_outcomes,
    by=c("patient_id", "match_id", "trial_date")
  ) %>%
  mutate(
    treated=0L
  )

# check final data agrees with matching status

all(data_control$patient_id %in% (data_matchstatus %>% filter(treated==0L) %>% pull(patient_id)))
all((data_matchstatus %>% filter(treated==0L) %>% pull(patient_id)) %in% data_control$patient_id)

# check matching round IDs agree
all(data_control$matching_round_id == as.character(data_control$matching_round))


# merge treated and control groups
# FIXME there are more variables in the treated dataset than in the control datset. see -"matching_candidates" in `matching_filter1.R`
data_matched <-
  bind_rows(
    data_treated,
    data_control
  ) %>%
  # derive some variables
  mutate(

    # earliest covid event after study start
    anycovid_date = pmin(postest_date, covidemergency_date, covidadmitted_date, covidcritcare_date, coviddeath_date, na.rm=TRUE),
    
    noncoviddeath_date = if_else(!is.na(death_date) & is.na(coviddeath_date), death_date, as.Date(NA_character_)),
    
    cause_of_death = fct_case_when(
      !is.na(coviddeath_date) ~ "covid-related",
      is.na(death_date) ~ "not covid-related",
      TRUE ~ NA_character_
    ),
    
  )


write_rds(data_matched, here("output", "data", glue("data_finalmatched.rds")), compress="gz")


## Flowchart ----

## FIXME -- to add flowchart entry for all treated people who ended up with a matched control, and all treated people who were also used as a control in an earlier trial


