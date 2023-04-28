from cohortextractor import patients, combine_codelists
from codelists import *
import codelists
import pandas as pd

child_vax = pd.read_csv("lib/childhood_vaccines/selected_childhood_vaccines.csv")

def childhood_vaccs():
    def childhood_vacc(
        product_name
    ):
        name = product_name.replace(" (PCV)","").replace(" + ", "_").replace(" - ", "_").replace("/", "_").replace("-", "_").replace(" ", "_").replace("+", "_")

        return {
        name: patients.with_tpp_vaccination_record(
            product_name_matches=product_name,
            returning="binary_flag",
        ),
        }

    childhood_vacc_variables = dict()

    for i in child_vax["VaccinationName"]:
        childhood_vacc_variables.update(childhood_vacc(i))

    return childhood_vacc_variables