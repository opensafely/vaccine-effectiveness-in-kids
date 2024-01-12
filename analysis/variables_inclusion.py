from cohortextractor import patients, combine_codelists
from codelists import *
import json
import codelists

specific_atrisk_date = "2020-07-01"


def generate_inclusion_variables(baseline_date):
    inclusion_variables = dict(
        registered=patients.registered_as_of(
            baseline_date,
        ),
        has_died=patients.died_from_any_cause(
            on_or_before=baseline_date,
            returning="binary_flag",
        ),
        age_aug21=patients.age_as_of(
            "2021-08-31",
        ),
        age=patients.age_as_of(
            f"{baseline_date} - 1 day",
        ),
        child_atrisk=patients.satisfying(
            """
        ATRISK_GROUP
        OR
        HHLD_IMDEF
        OR
        PREG1_GROUP
        """,
            HHLD_IMDEF=patients.with_these_clinical_events(
                hhld_imdef_cod,
                on_or_before=f"{baseline_date} - 1 day",
            ),
            nulldate=patients.fixed_value("1902-01-01"),
            ATRISK_GROUP=patients.satisfying(
                """
            IMMUNOGROUP
            OR
            CKD_GROUP
            OR
            RESP_GROUP
            OR
            DIAB_GROUP 
            OR
            CLD
            OR
            CNS_GROUP
            OR
            CHD_COV
            OR
            SPLN_COV
            OR
            LEARNDIS
            OR
            SEVMENT_GROUP
            """,
                ##### Patients with Immunosuppression
                IMMUNOGROUP=patients.satisfying(
                    """
                IMMDX
                OR
                IMMRX
                OR
                DXT_CHEMO
                """,
                    ###  any immunosuppressant Read code is recorded
                    IMMDX=patients.with_these_clinical_events(
                        immdx_cov_cod,
                        find_last_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                    ),
                    ### any Immunosuppression medication codes is recorded
                    IMMRX=patients.with_these_clinical_events(
                        immrx_cod,
                        find_last_match_in_period=True,
                        between=[specific_atrisk_date, f"{baseline_date} - 1 day"],
                    ),
                    ### Receiving chemotherapy or radiotherapy
                    DXT_CHEMO=patients.with_these_clinical_events(
                        dxt_chemo_cod,
                        find_last_match_in_period=True,
                        between=[
                            f"{baseline_date} - 6 months",
                            f"{baseline_date} - 1 day",
                        ],
                    ),
                ),
                # Patients with Chronic Kidney Disease
                # as per official COVID-19 vaccine reporting specification
                # IF CKD_COV_DAT > NULL (diagnoses) | Select | Next
                # IF CKD15_DAT = NULL  (No stages)   | Reject | Next
                # IF CKD35_DAT>=CKD15_DAT            | Select | Reject
                # (i.e. any diagnostic code, or most recent stage recorded >=3)
                CKD_GROUP=patients.satisfying(
                    """
                CKD_COV
                OR
                (
                CKD15_DAT
                AND
                CKD15_DAT > nulldate
                AND
                CKD35_DAT
                AND
                CKD35_DAT > nulldate
                AND
                CKD15
                AND
                CKD35_DAT >= CKD15_DAT 
                )
                """,
                    ### Chronic kidney disease diagnostic codes
                    CKD_COV=patients.with_these_clinical_events(
                        ckd_cov_cod,
                        find_first_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                    ),
                    ### Chronic kidney disease codes - all stages
                    CKD15=patients.with_these_clinical_events(
                        ckd15_cod,
                        find_last_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                    ),
                    ### date of Chronic kidney disease codes-stages 3 – 5
                    CKD35_DAT=patients.with_these_clinical_events(
                        ckd35_cod,
                        returning="date",
                        find_last_match_in_period=True,
                        date_format="YYYY-MM-DD",
                        on_or_before=f"{baseline_date} - 1 day",
                    ),
                    ### date of Chronic kidney disease codes - all stages
                    CKD15_DAT=patients.with_these_clinical_events(
                        ckd15_cod,
                        returning="date",
                        date_format="YYYY-MM-DD",
                        on_or_before=f"{baseline_date} - 1 day",
                        find_last_match_in_period=True,
                    ),
                ),
                ### Patients who have Chronic Respiratory Disease
                RESP_GROUP=patients.satisfying(
                    """
                AST_GROUP
                OR
                RESP_COV 
                """,
                    ### Patients with Asthma
                    AST_GROUP=patients.satisfying(
                        """
                ASTADM
                OR
                (
                AST
                AND
                ASTRXM1
                AND
                ASTRXM2 > 1
                )
                """,
                        ### Asthma Admission codes
                        ASTADM=patients.with_these_clinical_events(
                            astadm_cod,
                            find_last_match_in_period=True,
                            between=[
                                f"{baseline_date} - 730 days",
                                f"{baseline_date} - 1 day",
                            ],
                        ),
                        ### Asthma Diagnosis code
                        AST=patients.with_these_clinical_events(
                            ast_cod,
                            find_first_match_in_period=True,
                            on_or_before=f"{baseline_date} - 1 day",
                        ),
                        ### Asthma - inhalers in last 12 months
                        ASTRXM1=patients.with_these_medications(
                            astrxm1_cod,
                            returning="binary_flag",
                            between=[
                                f"{baseline_date} - 365 days",
                                f"{baseline_date} - 1 day",
                            ],
                        ),
                        ### Asthma - systemic oral steroid prescription codes in last 24 months
                        ASTRXM2=patients.with_these_medications(
                            astrxm2_cod,
                            returning="number_of_matches_in_period",
                            between=[
                                f"{baseline_date} - 730 days",
                                f"{baseline_date} - 1 day",
                            ],
                        ),
                    ),
                    ### Chronic Respiratory Disease
                    RESP_COV=patients.with_these_clinical_events(
                        resp_cov_cod,
                        find_first_match_in_period=True,
                        returning="binary_flag",
                        on_or_before=f"{baseline_date} - 1 day",
                    ),
                ),
                ### Patients with Diabetes
                DIAB_GROUP=patients.satisfying(
                    """
                (
                    DIAB_DAT
                    AND
                    DIAB_DAT > nulldate
                    AND
                    DIAB_DAT > DMRES_DAT
                )
                OR
                ADDIS
                OR
                GDIAB_GROUP
                """,
                    ### Date any Diabetes diagnosis Read code is recorded
                    DIAB_DAT=patients.with_these_clinical_events(
                        diab_cod,
                        returning="date",
                        find_last_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                        date_format="YYYY-MM-DD",
                    ),
                    ### Date of Diabetes resolved codes
                    DMRES_DAT=patients.with_these_clinical_events(
                        dmres_cod,
                        returning="date",
                        find_last_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                        date_format="YYYY-MM-DD",
                    ),
                    ### Addison’s disease & Pan-hypopituitary diagnosis codes
                    ADDIS=patients.with_these_clinical_events(
                        addis_cod,
                        find_last_match_in_period=True,
                        returning="binary_flag",
                        on_or_before=f"{baseline_date} - 1 day",
                    ),
                    ### Patients who are currently pregnant with gestational diabetes
                    GDIAB_GROUP=patients.satisfying(
                        """
                GDIAB
                AND
                PREG1_GROUP
                """,
                        ### Gestational Diabetes diagnosis codes
                        GDIAB=patients.with_these_clinical_events(
                            gdiab_cod,
                            find_last_match_in_period=True,
                            returning="binary_flag",
                            between=[
                                f"{baseline_date} - 254 days",
                                f"{baseline_date} - 1 day",
                            ],
                        ),
                        ### Patients who are currently pregnant
                        PREG1_GROUP=patients.satisfying(
                            """
                    PREG
                    AND
                    PREG_DAT
                    AND
                    PREGDEL_DAT < PREG_DAT
                    """,
                            ### Pregnancy codes recorded in the 8.5 months before the audit run date
                            PREG=patients.with_these_clinical_events(
                                preg_cod,
                                returning="binary_flag",
                                between=[
                                    f"{baseline_date} - 254 days",
                                    f"{baseline_date} - 1 day",
                                ],
                            ),
                            ### Pregnancy or Delivery codes recorded in the 8.5 months before audit run date
                            PREGDEL_DAT=patients.with_these_clinical_events(
                                pregdel_cod,
                                returning="date",
                                find_last_match_in_period=True,
                                between=[
                                    f"{baseline_date} - 254 days",
                                    f"{baseline_date} - 1 day",
                                ],
                                date_format="YYYY-MM-DD",
                            ),
                            ### Date of pregnancy codes recorded in the 8.5 months before audit run date
                            PREG_DAT=patients.with_these_clinical_events(
                                preg_cod,
                                returning="date",
                                find_last_match_in_period=True,
                                between=[
                                    f"{baseline_date} - 254 days",
                                    f"{baseline_date} - 1 day",
                                ],
                                date_format="YYYY-MM-DD",
                            ),
                        ),
                    ),
                ),
                ### Chronic Liver disease codes
                CLD=patients.with_these_clinical_events(
                    cld_cod,
                    find_first_match_in_period=True,
                    returning="binary_flag",
                    on_or_before=f"{baseline_date} - 1 day",
                ),
                ### Patients with CNS Disease (including Stroke/TIA)
                CNS_GROUP=patients.with_these_clinical_events(
                    cns_cov_cod,
                    find_first_match_in_period=True,
                    returning="binary_flag",
                    on_or_before=f"{baseline_date} - 1 day",
                ),
                ### Chronic heart disease codes
                CHD_COV=patients.with_these_clinical_events(
                    chd_cov_cod,
                    find_first_match_in_period=True,
                    returning="binary_flag",
                    on_or_before=f"{baseline_date} - 1 day",
                ),
                ### Asplenia or Dysfunction of the Spleen codes
                SPLN_COV=patients.with_these_clinical_events(
                    spln_cov_cod,
                    find_first_match_in_period=True,
                    returning="binary_flag",
                    on_or_before=f"{baseline_date} - 1 day",
                ),
                ### Wider Learning Disability
                LEARNDIS=patients.with_these_clinical_events(
                    learndis_cod,
                    find_last_match_in_period=True,
                    returning="binary_flag",
                    on_or_before=f"{baseline_date} - 1 day",
                ),
                ### Patients with Severe Mental Health
                SEVMENT_GROUP=patients.satisfying(
                    """
            SEV_MENTAL_DAT
            AND
            SEV_MENTAL_DAT > nulldate
            AND
            SEV_MENTAL_DAT > SMHRES_DAT
            """,
                    ### date of Severe Mental Illness codes
                    SEV_MENTAL_DAT=patients.with_these_clinical_events(
                        sev_mental_cod,
                        returning="date",
                        find_last_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                        date_format="YYYY-MM-DD",
                    ),
                    ### date of Remission codes relating to Severe Mental Illness
                    SMHRES_DAT=patients.with_these_clinical_events(
                        smhres_cod,
                        returning="date",
                        find_last_match_in_period=True,
                        on_or_before=f"{baseline_date} - 1 day",
                        date_format="YYYY-MM-DD",
                    ),
                ),
            ),
        ),
        ########## end of at risk criteria
    )
    return inclusion_variables
