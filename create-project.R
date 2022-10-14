library("tidyverse")
library("yaml")
library("here")
library("glue")
# library("rlang")

source(here("analysis", "design.R"))

# create action functions ----

## create comment function ----
comment <- function(...) {
  list_comments <- list(...)
  comments <- map(list_comments, ~ paste0("## ", ., " ##"))
  comments
}


## create function to convert comment "actions" in a yaml string into proper comments
convert_comment_actions <- function(yaml.txt) {
  yaml.txt %>%
    str_replace_all("\\\n(\\s*)\\'\\'\\:(\\s*)\\'", "\n\\1") %>%
    # str_replace_all("\\\n(\\s*)\\'", "\n\\1") %>%
    str_replace_all("([^\\'])\\\n(\\s*)\\#\\#", "\\1\n\n\\2\\#\\#") %>%
    str_replace_all("\\#\\#\\'\\\n", "\n")
}


## generic action function ----
action <- function(name,
                   run,
                   arguments = NULL,
                   needs = NULL,
                   highly_sensitive = NULL,
                   moderately_sensitive = NULL,
                   ... # other arguments / options for special action types
) {
  outputs <- list(
    highly_sensitive = highly_sensitive,
    moderately_sensitive = moderately_sensitive
  )
  outputs[sapply(outputs, is.null)] <- NULL

  action <- list(
    run = paste(c(run, arguments), collapse = " "),
    needs = needs,
    outputs = outputs,
    ... = ...
  )
  action[sapply(action, is.null)] <- NULL

  action_list <- list(name = action)
  names(action_list) <- name

  action_list
}

namelesslst <- function(...) {
  unname(lst(...))
}

## actions for a single matching round ----




action_1matchround <- function(cohort, vaxn, matching_round) {
  control_extract_date <- study_dates[[cohort]][[glue("control_extract_dates{substr(vaxn,4,4)}")]][matching_round]

  splice(
    action(
      name = glue("extract_controlpotential_{vaxn}_{cohort}_{matching_round}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlpotential",
        " --output-file output/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlpotential.feather",
        " --param cohort={cohort}",
        " --param matching_round={matching_round}",
        " --param index_date={control_extract_date}",
        " --param vaxn={vaxn}"
      ),
      needs = c(
        if (matching_round > 1) {
          glue("process_controlactual_{vaxn}_{cohort}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        cohort = glue("output/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlpotential.feather")
      )
    ),
    action(
      name = glue("process_controlpotential_{vaxn}_{cohort}_{matching_round}"),
      run = glue("r:latest analysis/matching/process_controlpotential.R"),
      arguments = c(cohort, matching_round,vaxn),
      needs = namelesslst(
        glue("extract_controlpotential_{vaxn}_{cohort}_{matching_round}"),
      ),
      highly_sensitive = lst(
        rds = glue("output/{vaxn}/{cohort}/matchround{matching_round}/process/*.rds")
      )
    ),
    action(
      name = glue("match_potential_{vaxn}_{cohort}_{matching_round}"),
      run = glue("r:latest analysis/matching/match_potential.R"),
      arguments = c(cohort, matching_round,vaxn),
      needs = c(
        glue("process_treated_{vaxn}_{cohort}"),
        glue("process_controlpotential_{vaxn}_{cohort}_{matching_round}"),
        if (matching_round > 1) {
          glue("process_controlactual_{vaxn}_{cohort}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        rds = glue("output/{vaxn}/{cohort}/matchround{matching_round}/potential/*.rds"),
        csv = glue("output/{vaxn}/{cohort}/matchround{matching_round}/potential/*.csv.gz"),
      )
    ),
    action(
      name = glue("extract_controlactual_{vaxn}_{cohort}_{matching_round}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlactual",
        " --output-file output/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlactual.feather",
        " --param cohort={cohort}",
        " --param matching_round={matching_round}",
        " --param vaxn={vaxn}",
      ),
      needs = namelesslst(
        glue("match_potential_{vaxn}_{cohort}_{matching_round}"),
      ),
      highly_sensitive = lst(
        cohort = glue("output/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlactual.feather")
      )
    ),
    action(
      name = glue("process_controlactual_{vaxn}_{cohort}_{matching_round}"),
      run = glue("r:latest analysis/matching/process_controlactual.R"),
      arguments = c(cohort, matching_round,vaxn),
      needs = c(
        glue("process_treated_{vaxn}_{cohort}"),
        glue("match_potential_{vaxn}_{cohort}_{matching_round}"),
        glue("extract_controlpotential_{vaxn}_{cohort}_{matching_round}"), # this is only necessary for the dummy data
        glue("extract_controlactual_{vaxn}_{cohort}_{matching_round}"),
        if (matching_round > 1) {
          glue("process_controlactual_{vaxn}_{cohort}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        rds = glue("output/{vaxn}/{cohort}/matchround{matching_round}/actual/*.rds"),
        csv = glue("output/{vaxn}/{cohort}/matchround{matching_round}/actual/*.csv.gz"),
      )
    )
  )
}

# test function
# action_1matchround("over12", 2)

# create all necessary actions for n matching rounds
action_extract_and_match <- function(cohort, vaxn, n_matching_rounds) {
  allrounds <- map(seq_len(n_matching_rounds), ~ action_1matchround(cohort, vaxn, .x)) %>% flatten()

  splice(

    # all treated people
    action(
      name = glue("extract_treated_{vaxn}_{cohort}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_treated",
        " --output-file output/{vaxn}/{cohort}/extract/input_treated.feather",
        " --param cohort={cohort}",
        " --param vaxn={vaxn}",
      ),
      highly_sensitive = lst(
        extract = glue("output/{vaxn}/{cohort}/extract/input_treated.feather")
      ),
    ),

    # all treated people
    action(
      name = glue("process_treated_{vaxn}_{cohort}"),
      run = glue("r:latest analysis/treated/process_treated.R"),
      arguments = c(cohort, vaxn),
      needs = namelesslst(
        glue("extract_treated_{vaxn}_{cohort}")
      ),
      highly_sensitive = lst(
        rds = glue("output/{vaxn}/{cohort}/treated/*.rds")
      ),
    ),
    allrounds,
    action(
      name = glue("extract_controlfinal_{vaxn}_{cohort}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlfinal",
        " --output-file output/{vaxn}/{cohort}/extract/input_controlfinal.feather",
        " --param cohort={cohort}",
        " --param n_matching_rounds={n_matching_rounds}",
        " --param vaxn={vaxn}",
      ),
      needs = namelesslst(
        glue("process_controlactual_{vaxn}_{cohort}_{n_matching_rounds}")
      ),
      highly_sensitive = lst(
        extract = glue("output/{vaxn}/{cohort}/extract/input_controlfinal.feather")
      ),
    ),
    action(
      name = glue("process_controlfinal_{vaxn}_{cohort}"),
      run = glue("r:latest analysis/matching/process_controlfinal.R"),
      arguments = c(cohort,vaxn),
      needs = c(
        map(
          seq_len(n_matching_rounds),
          ~ glue("process_controlactual_{vaxn}_{cohort}_", .x)
        ),
        glue("extract_controlfinal_{vaxn}_{cohort}"),
        glue("process_treated_{vaxn}_{cohort}")
      ),
      highly_sensitive = lst(
        extract = glue("output/{vaxn}/{cohort}/match/*.rds")
      ),
    )
  )
}

# test action
# action_extract_and_match("over12", 2)


action_table1 <- function(cohort, vaxn) {
  action(
    name = glue("table1_{vaxn}_{cohort}"),
    run = glue("r:latest analysis/matching/table1.R"),
    arguments = c(cohort,vaxn),
    needs = namelesslst(
      glue("process_controlfinal_{vaxn}_{cohort}"),
    ),
    moderately_sensitive = lst(
      csv = glue("output/{vaxn}/{cohort}/table1/*.csv"),
      # png= glue("output/{vaxn}/{cohort}/table1/*.png"),
    )
  )
}


action_km <- function(cohort, subgroup, outcome, vaxn) {
  action(
    name = glue("km_{vaxn}_{cohort}_{subgroup}_{outcome}"),
    run = glue("r:latest analysis/model/km.R"),
    arguments = c(cohort, subgroup, outcome,vaxn),
    needs = namelesslst(
      glue("process_controlfinal_{vaxn}_{cohort}"),
    ),
    moderately_sensitive = lst(
      # csv= glue("output/{vaxn}/{cohort}/models/km/{subgroup}/{outcome}/*.csv"),
      rds = glue("output/{vaxn}/{cohort}/models/km/{subgroup}/{outcome}/*.rds"),
      png = glue("output/{vaxn}/{cohort}/models/km/{subgroup}/{outcome}/*.png"),
    )
  )
}

action_eventcounts <- function(cohort, subgroup, vaxn) {
  action(
    name = glue("eventcounts_{vaxn}_{cohort}_{subgroup}"),
    run = glue("r:latest analysis/model/eventcounts.R"),
    arguments = c(cohort, subgroup,vaxn),
    needs = namelesslst(
      glue("process_controlfinal_{vaxn}_{cohort}"),
    ),
    moderately_sensitive = lst(
      rds = glue("output/{vaxn}/{cohort}/models/eventcounts/{subgroup}/*.rds"),
    )
  )
}

action_combine <- function(cohort, vaxn) {
  action(
    name = glue("combine_{vaxn}_{cohort}"),
    run = glue("r:latest analysis/model/combine.R"),
    arguments = c(cohort,vaxn),
    needs = splice(
      as.list(
        glue_data(
          .x = expand_grid(
            subgroup = c("all", "prior_covid_infection"),
            outcome = c("postest", "emergency", "covidemergency", "covidadmitted", "covidcritcare", "coviddeath", "noncoviddeath"),
          ),
          "km_{vaxn}_{cohort}_{subgroup}_{outcome}"
        )
      ),
      as.list(
        glue_data(
          .x = expand_grid(
            subgroup = c("all", "prior_covid_infection"),
          ),
          "eventcounts_{vaxn}_{cohort}_{subgroup}"
        )
      )
    ),
    moderately_sensitive = lst(
      rds = glue("output/{vaxn}/{cohort}/models/combined/*.csv"),
      png = glue("output/{vaxn}/{cohort}/models/combined/*.png"),
    )
  )
}

action_skim <- function(cohort, vaxn) {
action(
  name = glue("skim_{vaxn}_{cohort}_matched"),
  run = "r:latest analysis/data_skim.R",
  arguments = c(glue("output/{vaxn}/{cohort}/match/data_matched.rds"), glue("output/{vaxn}/{cohort}/skim")),
  needs = list(glue("process_controlfinal_{vaxn}_{cohort}")),
  moderately_sensitive = lst(
    cohort = glue("output/{vaxn}/{cohort}/skim/*.txt")
  )
)
}


# specify project ----

## defaults ----
defaults_list <- lst(
  version = "3.0",
  expectations = lst(population_size = 100000L)
)

## actions ----
actions_list <- splice(
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "DO NOT EDIT project.yaml DIRECTLY",
    "This file is created by create-project.R",
    "Edit and run create-project.R to update the project.yaml",
    "# # # # # # # # # # # # # # # # # # #",
    " "
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Over 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Extract and match"
  ),
  action_extract_and_match("over12", "vax1", n_matching_rounds),
  action_skim("over12", "vax1"),
  action_table1("over12", "vax1"),
  action_extract_and_match("over12", "vax2", n_matching_rounds),
  action_skim("over12", "vax2"),
  action_table1("over12", "vax2"),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Model"
  ),
  action_km("over12", "all", "postest", "vax1"),
  action_km("over12", "all", "emergency", "vax1"),
  action_km("over12", "all", "covidemergency", "vax1"),
  action_km("over12", "all", "covidadmitted", "vax1"),
  action_km("over12", "all", "covidcritcare", "vax1"),
  action_km("over12", "all", "coviddeath", "vax1"),
  action_km("over12", "all", "noncoviddeath", "vax1"),
  action_km("over12", "prior_covid_infection", "postest", "vax1"),
  action_km("over12", "prior_covid_infection", "emergency", "vax1"),
  action_km("over12", "prior_covid_infection", "covidemergency", "vax1"),
  action_km("over12", "prior_covid_infection", "covidadmitted", "vax1"),
  action_km("over12", "prior_covid_infection", "covidcritcare", "vax1"),
  action_km("over12", "prior_covid_infection", "coviddeath", "vax1"),
  action_km("over12", "prior_covid_infection", "noncoviddeath", "vax1"),
  action_eventcounts("over12", "all", "vax1"),
  action_eventcounts("over12", "prior_covid_infection", "vax1"),
  action_combine("over12", "vax1"),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "second vaccination"
  ),
  action_km("over12", "all", "postest", "vax2"),
  action_km("over12", "all", "emergency", "vax2"),
  action_km("over12", "all", "covidemergency", "vax2"),
  action_km("over12", "all", "covidadmitted", "vax2"),
  action_km("over12", "all", "covidcritcare", "vax2"),
  action_km("over12", "all", "coviddeath", "vax2"),
  action_km("over12", "all", "noncoviddeath", "vax2"),
  action_km("over12", "prior_covid_infection", "postest", "vax2"),
  action_km("over12", "prior_covid_infection", "emergency", "vax2"),
  action_km("over12", "prior_covid_infection", "covidemergency", "vax2"),
  action_km("over12", "prior_covid_infection", "covidadmitted", "vax2"),
  action_km("over12", "prior_covid_infection", "covidcritcare", "vax2"),
  action_km("over12", "prior_covid_infection", "coviddeath", "vax2"),
  action_km("over12", "prior_covid_infection", "noncoviddeath", "vax2"),
  action_eventcounts("over12", "all", "vax2"),
  action_eventcounts("over12", "prior_covid_infection", "vax2"),
  action_combine("over12", "vax2"),
  
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Under 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Extract and match"
  ),
  action_extract_and_match("under12", "vax1", n_matching_rounds),
  action_skim("under12", "vax1"),
  action_table1("under12", "vax1"),
  action_extract_and_match("under12", "vax2", n_matching_rounds),
  action_skim("under12", "vax2"),
  action_table1("under12", "vax2"),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Model"
  ),
  action_km("under12", "all", "postest", "vax1"),
  action_km("under12", "all", "emergency", "vax1"),
  action_km("under12", "all", "covidemergency", "vax1"),
  action_km("under12", "all", "covidadmitted", "vax1"),
  action_km("under12", "all", "covidcritcare", "vax1"),
  action_km("under12", "all", "coviddeath", "vax1"),
  action_km("under12", "all", "noncoviddeath", "vax1"),
  action_km("under12", "prior_covid_infection", "postest", "vax1"),
  action_km("under12", "prior_covid_infection", "emergency", "vax1"),
  action_km("under12", "prior_covid_infection", "covidemergency", "vax1"),
  action_km("under12", "prior_covid_infection", "covidadmitted", "vax1"),
  action_km("under12", "prior_covid_infection", "covidcritcare", "vax1"),
  action_km("under12", "prior_covid_infection", "coviddeath", "vax1"),
  action_km("under12", "prior_covid_infection", "noncoviddeath", "vax1"),
  action_eventcounts("under12", "all", "vax1"),
  action_eventcounts("under12", "prior_covid_infection", "vax1"),
  action_combine("under12", "vax1"),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "second vaccination"
  ),
  action_km("under12", "all", "postest", "vax2"),
  action_km("under12", "all", "emergency", "vax2"),
  action_km("under12", "all", "covidemergency", "vax2"),
  action_km("under12", "all", "covidadmitted", "vax2"),
  action_km("under12", "all", "covidcritcare", "vax2"),
  action_km("under12", "all", "coviddeath", "vax2"),
  action_km("under12", "all", "noncoviddeath", "vax2"),
  action_km("under12", "prior_covid_infection", "postest", "vax2"),
  action_km("under12", "prior_covid_infection", "emergency", "vax2"),
  action_km("under12", "prior_covid_infection", "covidemergency", "vax2"),
  action_km("under12", "prior_covid_infection", "covidadmitted", "vax2"),
  action_km("under12", "prior_covid_infection", "covidcritcare", "vax2"),
  action_km("under12", "prior_covid_infection", "coviddeath", "vax2"),
  action_km("under12", "prior_covid_infection", "noncoviddeath", "vax2"),
  action_eventcounts("under12", "all", "vax2"),
  action_eventcounts("under12", "prior_covid_infection", "vax2"),
  action_combine("under12", "vax2"),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Move files for release",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action(
    name = "release",
    run = glue("r:latest analysis/release_objects.R"),
    needs = namelesslst(
      glue("table1_vax1_over12"),
      glue("combine_vax1_over12"),
      glue("table1_vax1_under12"),
      glue("combine_vax1_under12"),
      glue("table1_vax2_over12"),
      glue("combine_vax2_over12"),
      glue("table1_vax2_under12"),
      glue("combine_vax2_under12"),
    ),
    moderately_sensitive = lst(
      txt = glue("output/meta-release/*.txt"),
      csv = glue("output/release/*.csv"),
    ),
  ),
  comment("#### End ####")
)

project_list <- splice(
  defaults_list,
  list(actions = actions_list)
)

## convert list to yaml, reformat comments and whitespace ----
thisproject <- as.yaml(project_list, indent = 2) %>%
  # convert comment actions to comments
  convert_comment_actions() %>%
  # add one blank line before level 1 and level 2 keys
  str_replace_all("\\\n(\\w)", "\n\n\\1") %>%
  str_replace_all("\\\n\\s\\s(\\w)", "\n\n  \\1")


# if running via opensafely, check that the project on disk is the same as the project created here:
if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("expectations", "tpp")) {
  thisprojectsplit <- str_split(thisproject, "\n")
  currentproject <- readLines(here("project.yaml"))

  stopifnot("project.yaml is not up-to-date with create-project.R.  Run create-project.R before running further actions." = identical(thisprojectsplit, currentproject))

  # if running manually, output new project as normal
} else if (Sys.getenv("OPENSAFELY_BACKEND") %in% c("")) {

  ## output to file ----
  writeLines(thisproject, here("project.yaml"))
  # yaml::write_yaml(project_list, file =here("project.yaml"))

  ## grab all action names and send to a txt file

  names(actions_list) %>%
    tibble(action = .) %>%
    mutate(
      model = action == "" & lag(action != "", 1, TRUE),
      model_number = cumsum(model),
    ) %>%
    group_by(model_number) %>%
    summarise(
      sets = str_trim(paste(action, collapse = " "))
    ) %>%
    pull(sets) %>%
    paste(collapse = "\n") %>%
    writeLines(here("actions.txt"))

  # fail if backend not recognised
} else {
  stop("Backend not recognised by create.project.R script")
}
