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
  control_extract_date <- study_dates[[cohort]][[glue("control_extract_dates")]][matching_round]

  splice(
    action(
      name = glue("extract_controlpotential_{cohort}_{vaxn}_{matching_round}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlpotential",
        " --output-file output/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlpotential.feather",
        " --param cohort={cohort}",
        " --param matching_round={matching_round}",
        " --param index_date={control_extract_date}"
      ),
      needs = c(
        if (matching_round > 1) {
          glue("process_controlactual_{cohort}_{vaxn}_{matching_round-1}")
        } else {
          NULL
        }
      ) %>% as.list(),
      highly_sensitive = lst(
        cohort = glue("output/{vaxn}/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlpotential.feather")
      )
    ),
    action(
      name = glue("process_controlpotential_{cohort}_{vaxn}_{matching_round}"),
      run = glue("r:latest analysis/matching/process_controlpotential.R"),
      arguments = c(cohort, matching_round),
      needs = namelesslst(
        glue("extract_controlpotential_{cohort}_{vaxn}_{matching_round}"),
      ),
      highly_sensitive = lst(
        rds = glue("output/{vaxn}/{cohort}/matchround{matching_round}/process/*.rds")
      )
    ),
    action(
      name = glue("match_potential_{cohort}_{vaxn}_{matching_round}"),
      run = glue("r:latest analysis/matching/match_potential.R"),
      arguments = c(cohort, matching_round),
      needs = c(
        glue("process_treated_{cohort}_{vaxn}"),
        glue("process_controlpotential_{cohort}_{vaxn}_{matching_round}"),
        if (matching_round > 1) {
          glue("process_controlactual_{cohort}_{vaxn}_{matching_round-1}")
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
      name = glue("extract_controlactual_{cohort}_{vaxn}_{matching_round}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlactual",
        " --output-file output/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlactual.feather",
        " --param cohort={cohort}",
        " --param matching_round={matching_round}",
      ),
      needs = namelesslst(
        glue("match_potential_{cohort}_{vaxn}_{matching_round}"),
      ),
      highly_sensitive = lst(
        cohort = glue("output/{vaxn}/{vaxn}/{cohort}/matchround{matching_round}/extract/input_controlactual.feather")
      )
    ),
    action(
      name = glue("process_controlactual_{cohort}_{vaxn}_{matching_round}"),
      run = glue("r:latest analysis/matching/process_controlactual.R"),
      arguments = c(cohort, matching_round),
      needs = c(
        glue("process_treated_{cohort}"),
        glue("match_potential_{cohort}_{matching_round}"),
        glue("extract_controlpotential_{cohort}_{matching_round}"), # this is only necessary for the dummy data
        glue("extract_controlactual_{cohort}_{matching_round}"),
        if (matching_round > 1) {
          glue("process_controlactual_{cohort}_{matching_round-1}")
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
      name = glue("extract_treated_{cohort}_{vaxn}"),
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
      name = glue("process_treated_{cohort}_{vaxn}"),
      run = glue("r:latest analysis/treated/process_treated.R"),
      arguments = c(cohort, vaxn),
      needs = namelesslst(
        glue("extract_treated_{cohort}_{vaxn}")
      ),
      highly_sensitive = lst(
        rds = glue("output/{vaxn}/{cohort}/treated/*.rds")
      ),
      moderately_sensitive = lst(
        csv = glue("output/{vaxn}/{cohort}/treated/*.csv")
      )
    ),
    allrounds,
    action(
      name = glue("extract_controlfinal_{cohort}_{vaxn}"),
      run = glue(
        "cohortextractor:latest generate_cohort",
        " --study-definition study_definition_controlfinal",
        " --output-file output/{vaxn}/{cohort}/extract/input_controlfinal.feather",
        " --param cohort={cohort}",
        " --param n_matching_rounds={n_matching_rounds}",
      ),
      needs = namelesslst(
        glue("process_controlactual_{cohort}__{vaxn}_{n_matching_rounds}")
      ),
      highly_sensitive = lst(
        extract = glue("output/{vaxn}/{cohort}/extract/input_controlfinal.feather")
      ),
    ),
    action(
      name = glue("process_controlfinal_{cohort}_{vaxn}"),
      run = glue("r:latest analysis/matching/process_controlfinal.R"),
      arguments = c(cohort),
      needs = c(
        map(
          seq_len(n_matching_rounds),
          ~ glue("process_controlactual_{cohort}_", .x)
        ),
        glue("extract_controlfinal_{cohort}"),
        glue("process_treated_{cohort}")
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
    name = glue("table1_{cohort}"),
    run = glue("r:latest analysis/matching/table1.R"),
    arguments = c(cohort),
    needs = namelesslst(
      glue("process_controlfinal_{cohort}"),
    ),
    moderately_sensitive = lst(
      csv = glue("output/{vaxn}/{cohort}/table1/*.csv"),
      # png= glue("output/{vaxn}/{cohort}/table1/*.png"),
    )
  )
}


action_km <- function(cohort, subgroup, outcome, vaxn) {
  action(
    name = glue("km_{cohort}_{subgroup}_{outcome}"),
    run = glue("r:latest analysis/model/km.R"),
    arguments = c(cohort, subgroup, outcome),
    needs = namelesslst(
      glue("process_controlfinal_{cohort}"),
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
    name = glue("eventcounts_{cohort}_{subgroup}"),
    run = glue("r:latest analysis/model/eventcounts.R"),
    arguments = c(cohort, subgroup),
    needs = namelesslst(
      glue("process_controlfinal_{cohort}"),
    ),
    moderately_sensitive = lst(
      rds = glue("output/{vaxn}/{cohort}/models/eventcounts/{subgroup}/*.rds"),
    )
  )
}

action_combine <- function(cohort, vaxn) {
  action(
    name = glue("combine_{cohort}"),
    run = glue("r:latest analysis/model/combine.R"),
    arguments = c(cohort),
    needs = splice(
      as.list(
        glue_data(
          .x = expand_grid(
            subgroup = c("all", "prior_covid_infection"),
            outcome = c("postest", "emergency", "covidemergency", "covidadmitted", "covidcritcare", "coviddeath", "noncoviddeath"),
          ),
          "km_{cohort}_{subgroup}_{outcome}"
        )
      ),
      as.list(
        glue_data(
          .x = expand_grid(
            subgroup = c("all", "prior_covid_infection"),
          ),
          "eventcounts_{cohort}_{subgroup}"
        )
      )
    ),
    moderately_sensitive = lst(
      rds = glue("output/{vaxn}/{cohort}/models/combined/*.csv"),
      png = glue("output/{vaxn}/{cohort}/models/combined/*.png"),
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
  action_extract_and_match("over12", "vax2", n_matching_rounds),
  action(
    name = "skim_over12_matched",
    run = "r:latest analysis/data_skim.R",
    arguments = c("output/over12/match/data_matched.rds", "output/over12/skim"),
    needs = list("process_controlfinal_over12"),
    moderately_sensitive = lst(
      cohort = "output/over12/skim/*.txt"
    )
  ),
  action_table1("over12", "vax1"),
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
    "Under 12s cohort",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  comment(
    "# # # # # # # # # # # # # # # # # # #",
    "Extract and match"
  ),
  action_extract_and_match("under12", "vax1", n_matching_rounds),
  action_extract_and_match("under12", "vax2", n_matching_rounds),
  action(
    name = "skim_under12_matched",
    run = "r:latest analysis/data_skim.R",
    arguments = c("output/under12/match/data_matched.rds", "output/under12/skim"),
    needs = list("process_controlfinal_under12"),
    moderately_sensitive = lst(
      cohort = "output/under12/skim/*.txt"
    )
  ),
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
    "Move files for release",
    "# # # # # # # # # # # # # # # # # # #"
  ),
  action(
    name = "release",
    run = glue("r:latest analysis/release_objects.R"),
    needs = namelesslst(
      glue("table1_over12"),
      glue("combine_over12"),
      glue("table1_under12"),
      glue("combine_under12"),
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
