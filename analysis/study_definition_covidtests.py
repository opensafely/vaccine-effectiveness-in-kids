# Import codelists from codelists.py
import codelists

# import json module
import json

from cohortextractor import (
    StudyDefinition,
    patients,
    codelist_from_csv,
    codelist,
    filter_codes_by_category,
    combine_codelists,
    params,
)

cohort = params["cohort"]
vaxn = params["vaxn"]
arm = params["arm"]

############################################################
## tests
from variables_covidtests import generate_covidtests_variables

covidtests_variables = generate_covidtests_variables(index_date="trial_date")
############################################################


# Specify study defeinition
study = StudyDefinition(
    # Configure the expectations framework
    default_expectations={
        "date": {"earliest": "2020-01-01", "latest": "today"},
        "rate": "uniform",
        "incidence": 0.2,
        "int": {"distribution": "normal", "mean": 1000, "stddev": 100},
        "float": {"distribution": "normal", "mean": 25, "stddev": 5},
    },
    # This line defines the study population
    population=patients.which_exist_in_file(
        f_path=f"output/{cohort}/vax{vaxn}/match/data_matched_{arm}.csv.gz"
    ),
    trial_date=patients.with_value_from_file(
        f_path=f"output/{cohort}/vax{vaxn}/match/data_matched_{arm}.csv.gz",
        returning="trial_date",
        returning_type="date",
        date_format="YYYY-MM-DD",
    ),
    ###############################################################################
    # covariates
    ##############################################################################
    **covidtests_variables,
)
