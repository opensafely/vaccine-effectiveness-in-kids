from variables_outcome import vaccination_date_X 
from ast import And
# Import codelists from codelists.py
import codelists

# import json module
import json

############################################################
## matching variables
from variables_matching import generate_matching_variables 
matching_variables = generate_matching_variables(index_date="trial_date")
############################################################
## outcome variables
from variables_outcome import generate_outcome_variables 
outcome_variables = generate_outcome_variables(index_date="trial_date")
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
  
  index_date = studystart_date,
  
  # This line defines the study population
  population = patients.which_exist_in_file(f_path="output/match/cumulative_matchedcontrols1.csv.gz"),

  trial_date = patients.with_value_from_file(f_path="output/match/cumulative_matchedcontrols1.csv.gz", returning="trial_date", returning_type="date", date_format='YYYY-MM-DD'),
  
  match_id = patients.with_value_from_file(f_path="output/match/cumulative_matchedcontrols1.csv.gz", returning="match_id", returning_type="int"),
  
  
  ###############################################################################
  # matching
  ##############################################################################
  #**matching_variables,
  
  ###############################################################################
  # outcomes
  ##############################################################################
  **outcome_variables,
  
  
)
