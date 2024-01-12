from ast import And

# Import codelists from codelists.py
import codelists

# import json module
import json
import re

from cohortextractor import (
    StudyDefinition,
    patients,
    codelist_from_csv,
    codelist,
    filter_codes_by_category,
    combine_codelists,
    params,
)

from variables_outcome import vaccination_date_X


cohort = params["cohort"]
n_matching_rounds = params["n_matching_rounds"]
vaxn = params["vaxn"]

# import study dates defined in "./analysis/design.R" script
with open("./lib/design/study-dates.json") as f:
    study_dates = json.load(f)

# change these in design.R if necessary
start_date_0 = study_dates[cohort]["start_date1"]
end_date_0 = study_dates[cohort]["end_date1"]
start_date_1 = study_dates[cohort]["start_date1"]
end_date_1 = study_dates[cohort]["end_date1"]
start_date_2 = study_dates[cohort]["start_date2"]
end_date_2 = study_dates[cohort]["end_date2"]
start_date = study_dates[cohort][f"start_date{vaxn}"]
end_date = study_dates[cohort][f"end_date{vaxn}"]

# import study parameters defined in "./analysis/design.R" script
with open("./lib/design/study-params.json") as f:
    study_params = json.load(f)

minage = study_params[cohort]["minage"]
maxage = study_params[cohort]["maxage"]
treatment = study_params[cohort]["treatment"]
product_name = study_params[cohort]["product_name"]


############################################################
## outcome variables
from variables_outcome import generate_outcome_variables

outcome_variables = generate_outcome_variables(
    baseline_date="trial_date", product_name=product_name
)
############################################################


# Specify study defeinition
study = StudyDefinition(
    # Configure the expectations framework
    default_expectations={
        "date": {"earliest": "2020-01-01", "latest": end_date},
        "rate": "uniform",
        "incidence": 0.2,
        "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
        "float": {"distribution": "normal", "mean": 25, "stddev": 5},
    },
    index_date=start_date,
    # This line defines the study population
    population=patients.which_exist_in_file(
        f_path=f"output/{cohort}/vax{vaxn}/matchround{n_matching_rounds}/actual/cumulative_matchedcontrols.csv.gz"
    ),
    trial_date=patients.with_value_from_file(
        f_path=f"output/{cohort}/vax{vaxn}/matchround{n_matching_rounds}/actual/cumulative_matchedcontrols.csv.gz",
        returning="trial_date",
        returning_type="date",
        date_format="YYYY-MM-DD",
    ),
    match_id=patients.with_value_from_file(
        f_path=f"output/{cohort}/vax{vaxn}/matchround{n_matching_rounds}/actual/cumulative_matchedcontrols.csv.gz",
        returning="match_id",
        returning_type="int",
    ),
    ###############################################################################
    # matching
    ##############################################################################
    # **matching_variables,
    ###############################################################################
    # outcomes
    ##############################################################################
    **outcome_variables,
)
