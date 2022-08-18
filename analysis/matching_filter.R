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
  agegroup <- "over12"
  matching_round <- 1
} else {
  #FIXME replace with actual eventual action variables
  removeobjects <- TRUE
  agegroup <- args[[1]]
  matching_round <- args[[2]]
}

# define vaccination of interest
if(agegroup=="under12") treatment <- "pfizerC"
if(agegroup=="over12") treatment <- "pfizerA"


#FIXME put this info in study_dates script, probably
if(matching_round=="1") matching_round_date <- "2021-09-20"
if(matching_round=="2") matching_round_date <- "2021-10-04"



## Import libraries ----
library('tidyverse')
library('here')
library('arrow')
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


## import matching variables ----

#FIXME pick these up automatically from... somewhere
exact_variables <- c("age", "sex", "region")
caliper_variables <- character()


## trial info for matched controls
data_control_matchinfo <- read_csv(fs::path(output_dir, glue("potential_matched_controls{matching_round}.csv.gz")))

# use externally created dummy data if not running in the server
# check variables are as they should be
if(Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")){
  
  # just reuse previous extraction for dummy run, dummyinput_control_potential1.feather
  # and change a few variables to simulate new index dates
  data_extract <- read_feather(fs::path("lib", "dummydata", glue("dummyinput_control_potential1.feather"))) %>%
    filter(patient_id %in% data_control_matchinfo$patient_id) %>%
    mutate(
      region = if_else(runif(n())<0.05, sample(x=unique(region), size=n(), replace=TRUE), region),
    )

} else {
  data_extract <- read_feather(fs::path("output", glue("input_control_match{matching_round}.feather"))) %>%
    #because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"),  as.Date))
}


data_processed <- 
  data_extract %>%
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
    
    vax1_date = covid_vax_any_1_date
    
  )

# Define selection criteria ----
data_criteria <- data_processed %>%
  transmute(
    patient_id,
    has_age = !is.na(age),
    has_sex = !is.na(sex) & !(sex %in% c("I", "U")),
    has_imd = imd_Q5 != "Unknown",
    #has_ethnicity = !is.na(ethnicity_combined),
    has_region = !is.na(region),
    include = (
      has_age & has_sex & has_imd & # has_ethnicity &
        has_region 
    ),
  )

data_control0 <- data_criteria %>%
  filter(include) %>%
  select(patient_id) %>%
  left_join(data_processed, by="patient_id") %>%
  droplevels()



data_treated <- read_rds(fs::path(output_dir, glue("data_potential_matched{matching_round}.rds"))) %>% filter(treated==1L)

data_control <- data_control0 %>% 
  mutate(treated=0L) 

if(Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")){
  # these variables are not included in the dummy data so join them on here
  data_control <- data_control %>% left_join(data_control_matchinfo, by="patient_id")
}

matching_candidates <- 
  bind_rows(data_treated, data_control) %>%
  arrange(treated, match_id, trial_date)

### debug ###

#print missing values

map(matching_candidates, ~any(is.na(.x)))

### /debug ###


#########

## Easiest thing is to rematch, with additional exact matching on "match_id" and "trial_date"
## but might be quite slow

## alternative is to compare old matching variables with new matching variables
## but if calipers are used it gets a bit tricky

## so we rematch for now

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
    matching_round = matching_round
  ) %>%
  arrange(matched, match_id, treated)





### alternatively, use a fuzzy join _if_ this is quicker ###

# rematch_exact <-
#   inner_join(
#     x=data_treated %>% select(match_id, trial_date, all_of(exact_variables)),
#     y=data_control %>% select(match_id, trial_date, all_of(exact_variables)),
#     by = c("match_id", "trial_date", exact_variables)
#   ) 
# 
# caliper_check <- function(distance){
#   function(x,y){abs(x-y) <= distance}
# }
# 
# if(length(caliper_variables) >0 ){
#   rematch_caliper <-
#     fuzzyjoin::fuzzy_inner_join(
#       x=data_treated %>% select(match_id, trial_date, all_of(exact_variables)) %>% right_join(rematch_exact, by=c("match_id", "trial_date")),
#       y=data_control %>% select(match_id, trial_date, all_of(exact_variables)) %>% right_join(rematch_exact, by=c("match_id", "trial_date")),
#       by = unname(caliper_variables),
#       #match_fun = list(caliper_check(1), caliper_check(2), ...) #add functions to check caliper matches here
#   )
#     # fuzzy_join returns `variable.x` and `variable.y` columns, not just `variable` because they might be different values.
#     # but we know match_id and trial_date are exactly matched, so only need to pick these out to define the legitimate matches
#   rematch <- 
#     rematch_caliper %>% 
#     select(match_id=match_id.x, trial_date=trial_date.x) %>%
#     mutate(matched=1L)
# 
# } else{
#   rematch <- 
#     rematch_caliper %>% 
#     select(match_id, trial_date) %>%
#     mutate(matched=1L)
# }
# 
# data_matchstatus <-
#   matching_candidates %>%
#   select(patient_id, treated, match_id, trial_date, trial_time) %>%
#   left_join(rematch, by=c("match_id", "trial_date")) %>%
#   mutate(
#     matched= if_else(is.na(matched), 0L, matched),
#     matching_round = matching_round
#   ) %>%
#   arrange(matched, match_id, treated)

###

## pick up all previous successful matches

matching_roundprevious <- as.integer(matching_round) - 1

if(matching_round>1){
  
  data_matchstatusprevious <- 
    read_rds(fs::path(output_dir, glue("data_matchstatus_allrounds{matching_roundprevious}.rds"))) %>%
    filter(matched)
  
  data_matchstatus_allrounds <- 
    data_matchstatus %>% 
    filter(matched) %>%
    bind_rows(data_matchstatusprevious)
  
  
} else{
  data_matchstatus_allrounds <- 
    data_matchstatus %>% 
    filter(matched) 
}

write_rds(data_matchstatus_allrounds, fs::path(output_dir, glue("data_matchstatus_allrounds{matching_round}.rds")))

#actual legitimate matches 
data_match_actual <- 
  data_matchstatus %>%
  filter(matched) %>%
  select(patient_id, treated) %>%
  left_join(
    matching_candidates,
    by=c("patient_id", "treated")
  )

write_rds(data_match_actual, fs::path(output_dir, glue("data_match_actual{matching_round}.rds")))


## how many matches are lost?

print(glue("{sum(data_matchstatus$matched & data_matchstatus$treated)} matched-pairs kept out of {sum(data_matchstatus$treated)} 
           ({round(100*(sum(data_matchstatus$matched & data_matchstatus$treated) / sum(data_matchstatus$treated)),2)}%)
           "))

