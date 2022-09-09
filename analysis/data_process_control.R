######################################

# This script:
# imports data extracted by the cohort extractor (or dummy data)
# fills in unknown ethnicity from GP records with ethnicity from SUS (secondary care)
# tidies missing values
# standardises some variables (eg convert to factor) and derives some new ones
# organises vaccination date data to "vax X type", "vax X date" (rather than "pfizer X date", "az X date", ...)
######################################


# Preliminaries ----

## Import libraries ----
library('tidyverse')
library('lubridate')
library('arrow')
library('here')
library('glue')

## import command-line arguments ----

args <- commandArgs(trailingOnly=TRUE)


if(length(args)==0){
  # use for interactive testing
  removeobjects <- FALSE
  agegroup <- "over12"
  matching_round <- as.integer("1")
} else {
  #FIXME replace with actual eventual action variables
  removeobjects <- TRUE
  agegroup <- args[[1]]
  matching_round <- as.integer(args[[2]])
}





source(here("lib", "functions", "utility.R"))

## Import design elements
source(here("analysis", "design.R"))

# import globally defined study dates and convert to "Date"
study_dates <-
  jsonlite::read_json(path=here("lib", "design", "study-dates.json")) %>%
  map(as.Date)



start_date <- study_dates[[glue("{agegroup}start_date")]]
matching_round_date <- study_dates[[glue("{agegroup}start_date")]] + (matching_round-1)*14


# define vaccination of interest
if(agegroup=="under12") {
  treatment <- "pfizerC"
}
if(agegroup=="over12") {
  treatment <- "pfizerA"
}

fs::dir_create(here("output", "data"))


# process ----

# use externally created dummy data if not running in the server
# check variables are as they should be
if(Sys.getenv("OPENSAFELY_BACKEND") %in% c("", "expectations")){

  # ideally in future this will check column existence and types from metadata,
  # rather than from a cohort-extractor-generated dummy data

  data_studydef_dummy <- read_feather(here("output", glue("input_control_potential{matching_round}.feather"))) %>%
    # because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"), ~ as.Date(.))) %>%
    # because of a bug in cohort extractor -- remove once pulled new version
    mutate(patient_id = as.integer(patient_id))

  data_custom_dummy <- read_feather(here("lib", "dummydata", "dummy_control_potential1.feather")) %>%
    mutate(
      msoa = sample(factor(c("1", "2")), size=n(), replace=TRUE) # override msoa so matching success more likely
    ) %>%
    select(
      -covid_vax_pfizerA_1_date, -covid_vax_pfizerA_2_date, -covid_vax_pfizerC_1_date, -covid_vax_pfizerC_2_date, -covid_vax_any_2_date
    )


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

  data_extract <- data_custom_dummy 
} else {
  data_extract <- read_feather(here("output", glue("input_control_potential{matching_round}.feather"))) %>%
    #because date types are not returned consistently by cohort extractor
    mutate(across(ends_with("_date"),  as.Date))
}


data_processed <- data_extract %>%
  mutate(

    sex = fct_case_when(
      sex == "F" ~ "Female",
      sex == "M" ~ "Male",
      #sex == "I" ~ "Inter-sex",
      #sex == "U" ~ "Unknown",
      TRUE ~ NA_character_
    ),

    # ethnicity_combined = if_else(is.na(ethnicity), ethnicity_6_sus, ethnicity),
    # 
    # ethnicity_combined = fct_case_when(
    #   ethnicity_combined == "1" ~ "White",
    #   ethnicity_combined == "4" ~ "Black",
    #   ethnicity_combined == "3" ~ "South Asian",
    #   ethnicity_combined == "2" ~ "Mixed",
    #   ethnicity_combined == "5" ~ "Other",
    #   #TRUE ~ "Unknown",
    #   TRUE ~ NA_character_
    # 
    # ),

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
    
    
    prior_covid_infection = (!is.na(postest_0_date)) | (!is.na(covidadmitted_0_date)) | (!is.na(primary_care_covid_case_0_date)),
    
    # latest covid event before study start
    anycovid_0_date = pmax(postest_0_date, covidemergency_0_date, covidadmitted_0_date, na.rm=TRUE),
    
    vax1_date = covid_vax_any_1_date
  )



## select eligible patients and create flowchart ----


# Define selection criteria ----
data_criteria <- data_processed %>%
  transmute(
    patient_id,
    has_age = !is.na(age),
    has_sex = !is.na(sex) & !(sex %in% c("I", "U")),
    has_imd = imd_Q5 != "Unknown",
    #has_ethnicity = !is.na(ethnicity_combined),
    has_region = !is.na(region),
    no_recentcovid90 = is.na(anycovid_0_date) |  ((vax1_date - anycovid_0_date)>90),
    include = (
        has_age & has_sex & has_imd & # has_ethnicity &
        has_region &
        no_recentcovid90
    ),
  )


data_control_potential <- data_criteria %>%
  filter(include) %>%
  select(patient_id) %>%
  left_join(data_processed, by="patient_id") %>%
  droplevels()

write_rds(data_control_potential, here("output", "data", glue("data_control_potential{matching_round}.rds")), compress="gz")

