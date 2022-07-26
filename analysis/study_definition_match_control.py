from variables_outcome import vaccination_date_X 
from ast import And
# Import codelists from codelists.py
import codelists

# import json module
import json



############################################################
## inclusion variables
from variables_inclusion import generate_inclusion_variables 
inclusion_variables = generate_inclusion_variables(index_date="index_date")
############################################################
## matching variables
from variables_matching import generate_matching_variables 
matching_variables = generate_matching_variables(index_date="index_date")
############################################################


from cohortextractor import (
  StudyDefinition,
  patients,
  codelist_from_csv,
  codelist,
  filter_codes_by_category,
  combine_codelists,
)


# import study dates defined in "./lib/design/study-dates.R" script
with open("./lib/design/study-dates.json") as f:
  study_dates = json.load(f)

# change these in design.R if necessary
studystart_date = study_dates["over12start_date"] 
studyend_date = study_dates["over12end_date"]


# Specify study defeinition
study = StudyDefinition(
  
  # Configure the expectations framework
  default_expectations={
    "date": {"earliest": "2020-01-01", "latest": studyend_date},
    "rate": "uniform",
    "incidence": 0.2,
    "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
    "float": {"distribution": "normal", "mean": 25, "stddev": 5},
  },
  
  # This line defines the study population
  population = patients.satisfying(
    "controls",
    controls = which_exist_in_file("output/match/potential_matched_controls_1.csv.gz")
  ),
  
  # select index_date from file
  trial_date = with_value_from_file("output/match/potential_matched_controls_1.csv.gz", returning="trial_date", returning_type="date", date_format='YYYY-MM-DD'),
  match_id = with_value_from_file("output/match/potential_matched_controls_1.csv.gz", returning="match_id", returning_type="int"),
  
  index_date = with_value_from_file("output/match/potential_matched_controls_1.csv.gz", returning="trial_date", returning_type="date", date_format='YYYY-MM-DD'),
  
  **vaccination_date_X(
    name = "covid_vax_disease",
    index_date = "1900-01-01",
    n = 1,
    target_disease_matches="SARS-2 CORONAVIRUS"
  ),
  **inclusion_variables,    
  **matching_variables,      
)
