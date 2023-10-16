from cohortextractor import (
  StudyDefinition,
  patients,
  codelist_from_csv,
  codelist,
  filter_codes_by_category,
  combine_codelists,
  params
)

# Import codelists from codelists.py
import codelists

# import json module
import json

from variables_functions import *

cohort = params["cohort"]
vaxn = int(params["vaxn"])
carditis_type = params["carditis_type"]

with open("./lib/design/study-dates.json") as f:
  study_dates = json.load(f)

# change these in design.R if necessary
end_date = study_dates[cohort][f"end_date{vaxn}"]
index_date = study_dates[cohort][f"start_date{vaxn}"]

study = StudyDefinition(
  
  # Configure the expectations framework
  default_expectations={
    "date": {"earliest": "2020-01-01", "latest": end_date},
    "rate": "uniform",
    "incidence": 0.2,
    "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
    "float": {"distribution": "normal", "mean": 25, "stddev": 5},
  },
  
  index_date = index_date, # this shouldn't be used anywhere!
    
  population = patients.which_exist_in_file(f_path=f"output/{cohort}/vax{vaxn}/carditis_severity/{carditis_type}carditis_dates.csv"),
  carditis_date = patients.with_value_from_file(f_path=f"output/{cohort}/vax{vaxn}/carditis_severity/{carditis_type}carditis_dates.csv", returning=f"{carditis_type}carditis_date", returning_type="date", date_format='YYYY-MM-DD'),

  **admitted_to_hospital_X(
    n = 3,
    with_admission_method=["21", "22", "23", "24", "25", "2A", "2B", "2C", "2D", "28"],
    on_or_after="carditis_date",
    end_date=end_date
  ),

  ** carditis_emergency_X(carditis_type=carditis_type,on_or_after="carditis_date"),

  
)