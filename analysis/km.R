
# # # # # # # # # # # # # # # # # # # # #
# Purpose: Get cumulative incidence(kaplan meier) estimates for specified outcome, and derive risk differences
#  - import matched data
#  - adds outcome variable and restricts follow-up
#  - gets CI estimates, with covid and non covid death as competing risks
#  - The script must be accompanied by two arguments:
#    `agegroup` - over12s or under12s
#    `outcome` - the dependent variable

# # # # # # # # # # # # # # # # # # # # #

# Preliminaries ----


# import command-line arguments ----

args <- commandArgs(trailingOnly=TRUE)


if(length(args)==0){
  # use for interactive testing
  removeobjects <- FALSE
  agegroup <- "over12"
  subgroup <- "all"
  outcome <- "covidadmitted"
  
} else {
  removeobjects <- TRUE
  agegroup <- args[[1]]
  subgroup <- args[[2]]
  outcome <- args[[3]]
}



## Import libraries ----
library('tidyverse')
library('here')
library('glue')
library('survival')

## Import custom user functions from lib
source(here("lib", "functions", "utility.R"))
source(here("lib", "functions", "survival.R"))

## Import design elements
source(here("analysis", "design.R"))


# derive symbolic arguments for programming with

agegroup_sym <- sym(agegroup)
subgroup_sym <- sym(subgroup)

# create output directories ----

output_dir <- here("output", "comparison", agegroup, subgroup, outcome)
fs::dir_create(output_dir)


data_matched <- read_rds(here("output", "data", glue("data_finalmatched.rds")))

## import baseline data, restrict to matched individuals and derive time-to-event variables
data_matched <- 
  data_matched %>%
  select(
    # select only variables needed for models to save space
    patient_id, treated, trial_date, match_id, 
    controlistreated_date,
    vax1_date,
    death_date, dereg_date, coviddeath_date, noncoviddeath_date, vax2_date,
    all_of(c(glue("{outcome}_date")))
  ) %>%
  
  mutate(

    #trial_date,
    outcome_date = .data[[glue("{outcome}_date")]],
    
    # follow-up time is up to and including censor date
    censor_date = pmin(
      dereg_date,
      vax2_date-1, # -1 because we assume vax occurs at the start of the day
      death_date,
      study_dates[[glue("{agegroup}followupend_date")]],
      trial_date + maxfup,
      na.rm=TRUE
    ),
    
    matchcensor_date = pmin(censor_date, controlistreated_date, na.rm=TRUE), # new censor date based on whether control gets treated or not

    tte_outcome = tte(trial_date - 1, outcome_date, matchcensor_date, na.censor=FALSE), # -1 because we assume vax occurs at the start of the day, and so outcomes occurring on the same day as treatment are assumed "1 day" long
    ind_outcome = censor_indicator(outcome_date, matchcensor_date),
    
    all="all"
  )

# outcome frequency
outcomes_per_treated <- table(outcome=data_matched$ind_outcome, treated=data_matched$treated)


## redaction threshold ----

threshold <- 6

## competing risks cumulative risk differences ----

data_surv <-
  data_matched %>%
  group_by(treated, !!subgroup_sym) %>%
  nest() %>%
  mutate(
    surv_obj = map(data, ~{
      survfit(Surv(tte_outcome, ind_outcome) ~ 1, data = .x)
    }),
    surv_obj_tidy = map(surv_obj, ~{
      broom::tidy(.x) %>%
      complete(
        time = seq_len(max(.x$time)), # fill in 1 row for each day of follow up
        fill = list(n.event = 0, n.censor = 0)
      ) %>%
      fill(n.risk, .direction = c("up"))
    }), # return survival table for each day of follow up
  ) %>%
  select(!!subgroup_sym, treated, surv_obj_tidy) %>%
  unnest(surv_obj_tidy)

data_surv_rounded <-
  data_surv %>%
  mutate(
    # Round cumulative counts up to `threshold`, then deduct half of threshold to remove bias
    
    lagtime = lag(time,1,0),
    leadtime = lead(time, 1,0),
    interval = time - lagtime,

    N = max(n.risk, na.rm=TRUE),
    
    cml.event = roundmid_any(cumsum(n.event), threshold),
    cml.censor = roundmid_any(cumsum(n.censor), threshold),
    
    n.event = diff(c(0, cml.event)),
    n.censor = diff(c(0, cml.censor)),
    n.risk = roundmid_any(N, threshold) - lag(cml.event + cml.censor, 1, 0),


    ## calculate surv based on rounded event counts

    # KM estimate for event of interest, combining censored and competing events as censored
    summand = (1/(n.risk-n.event)) - (1/n.risk), # = n.event / ((n.risk - n.event) * n.risk) but re-written to prevent integer overflow
    surv = cumprod(1 - n.event / n.risk),
    surv.se = surv * sqrt(cumsum(summand)), #greenwood's formula
    surv.ln.se = surv.se/surv,
    surv.ll = exp(log(surv) + qnorm(0.025)*surv.ln.se),
    surv.ul = exp(log(surv) + qnorm(0.975)*surv.ln.se),
    
    risk = 1 - surv,
    risk.se = surv.se,
    risk.ln.se = surv.ln.se,
    risk.ll = 1 - surv.ul,
    risk.ul = 1 - surv.ll

  ) %>%
  select(
    !!subgroup_sym, treated, time, lagtime, leadtime, interval,
    n.risk,n.event, n.censor,
    surv, surv.se, surv.ll, surv.ul,
    risk, risk.se, risk.ll, risk.ul
  ) 

write_csv(data_surv_rounded, fs::path(output_dir, "km_estimates.csv"))

plot_km <- data_surv_rounded %>%
  group_modify(
    ~add_row(
      .x,
      time=0,
      lagtime=0,
      leadtime=1,
      #interval=1,
      surv=1,
      surv.ll=1,
      surv.ul=1,
      risk=0,
      risk.ll=0,
      risk.ul=0,
      .before=0
    ) #%>%
    #fill(treated_descr, .direction="up")
  ) %>%
  mutate(
    treated_descr = if_else(treated==1L, "Vaccinated", "Unvaccinated"),
  ) %>%
  ggplot(aes(group=treated_descr, colour=treated_descr, fill=treated_descr)) +
  geom_step(aes(x=time, y=risk), direction="vh")+
  geom_step(aes(x=time, y=risk), direction="vh", linetype="dashed", alpha=0.5)+
  geom_rect(aes(xmin=lagtime, xmax=time, ymin=risk.ll, ymax=risk.ul), alpha=0.1, colour="transparent")+
  facet_grid(rows=vars(!!subgroup_sym))+
  scale_color_brewer(type="qual", palette="Set1", na.value="grey") +
  scale_fill_brewer(type="qual", palette="Set1", guide="none", na.value="grey") +
  scale_x_continuous(breaks = seq(0,600,14))+
  scale_y_continuous(expand = expansion(mult=c(0,0.01)))+
  coord_cartesian(xlim=c(0, NA))+
  labs(
    x="Days",
    y="Cumulative incidence",
    colour=NULL,
    title=NULL
  )+
  theme_minimal()+
  theme(
    axis.line.x = element_line(colour = "black"),
    panel.grid.minor.x = element_blank(),
    legend.position=c(.05,.95),
    legend.justification = c(0,1),
  )

plot_km

ggsave(filename=fs::path(output_dir, "km.png"), plot_km, width=20, height=15, units="cm")


## calculate quantities relating to cumulative incidence curve and their ratio / difference / etc

kmcontrasts <- function(data, cuts=NULL){

  if(is.null(cuts)){cuts <- unique(c(0,data$time))}

  data %>%
    filter(time!=0) %>%
    transmute(
      !!subgroup_sym,
      treated,

      time, lagtime, interval,
      period_start = as.integer(as.character(cut(time, cuts, right=TRUE, label=cuts[-length(cuts)]))),
      period_end = as.integer(as.character(cut(time, cuts, right=TRUE, label=cuts[-1]))),
      period = cut(time, cuts, right=TRUE, label=paste0(cuts[-length(cuts)]+1, " - ", cuts[-1])),

      n.atrisk = n.risk,
      n.event, n.censor,

      cml.persontime = cumsum(n.atrisk*interval),
      cml.event = cumsum(replace_na(n.event, 0)),
      cml.censor = cumsum(replace_na(n.censor, 0)),

      rate = n.event / n.atrisk,
      cml.rate = cml.event / cml.persontime,

      surv, surv.se, surv.ll, surv.ul,
      risk, risk.se, risk.ll, risk.ul,

      inc = -(surv-lag(surv,1,1))/lag(surv,1,1),

      inc2 = diff(c(0,-log(surv)))

    ) %>%
    group_by(!!subgroup_sym, treated, period_start, period_end, period) %>%
    summarise(

      ## time-period-specific quantities

      persontime = sum(n.atrisk*interval), # total person-time at risk within time period

      inc = weighted.mean(inc, n.atrisk*interval),
      inc2 = weighted.mean(inc2, n.atrisk*interval),

      n.atrisk = first(n.atrisk), # number at risk at start of time period
      n.event = sum(n.event, na.rm=TRUE), # number of events within time period
      n.censor = sum(n.censor, na.rm=TRUE), # number censored within time period

      inc = n.event/persontime, # = weighted.mean(kmhaz, n.atrisk*interval), incidence rate. this is equivalent to a weighted average of the hazard ratio, with time-exposed as the weights

      interval = sum(interval), # width of time period

      ## quantities calculated from time zero until end of time period
      # these should be the same as the daily values as at the end of the time period


      surv = last(surv),
      surv.se = last(surv.se),
      surv.ll = last(surv.ll),
      surv.ul = last(surv.ul),

      risk = last(risk),
      risk.se = last(risk.se),
      risk.ll = last(risk.ll),
      risk.ul = last(risk.ul),

      
      #cml.haz = last(cml.haz),  # cumulative hazard from time zero to end of time period

      cml.rate = last(cml.rate), # event rate from time zero to end of time period

      # cml.persontime = last(cml.persontime), # total person-time at risk from time zero to end of time period
       cml.event = last(cml.event), # number of events from time zero to end of time period
      # cml.censor = last(cml.censor), # number censored from time zero to end of time period

      # cml.summand = last(cml.summand), # summand used for estimation of SE of survival

      .groups="drop"
    ) %>%
    ungroup() %>%
    pivot_wider(
      id_cols= all_of(c(subgroup, "period_start", "period_end", "period",  "interval")),
      names_from=treated,
      names_glue="{.value}_{treated}",
      values_from=c(

        persontime, n.atrisk, n.event, n.censor,
        inc, inc2,

        surv, surv.se, surv.ll, surv.ul,
        risk, risk.se, risk.ll, risk.ul,


        cml.event, cml.rate
        )
    ) %>%
    mutate(
      n.nonevent_0 = n.atrisk_0 - n.event_0,
      n.nonevent_1 = n.atrisk_1 - n.event_1,

      ## time-period-specific quantities

      # hazard ratio, standard error and confidence limits

      # incidence rate ratio
      irr = inc_1 / inc_0,
      irr.ln.se = sqrt((1/n.event_0) + (1/n.event_1)),
      irr.ll = exp(log(irr) + qnorm(0.025)*irr.ln.se),
      irr.ul = exp(log(irr) + qnorm(0.975)*irr.ln.se),


      # incidence rate ratio
      irr = inc_1 / inc_0,
      irr.ln.se = sqrt((1/n.event_0) + (1/n.event_1)),
      irr.ll = exp(log(irr) + qnorm(0.025)*irr.ln.se),
      irr.ul = exp(log(irr) + qnorm(0.975)*irr.ln.se),

      # incidence rate ratio, v2
      irr2 = inc2_1 / inc2_0,
      irr2.ln.se = sqrt((1/n.event_0) + (1/n.event_1)),
      irr2.ll = exp(log(irr2) + qnorm(0.025)*irr2.ln.se),
      irr2.ul = exp(log(irr2) + qnorm(0.975)*irr2.ln.se),

      # incidence rate difference
      #ird = rate_1 - rate_0,

      ## quantities calculated from time zero until end of time period
      # these should be the same as values calculated on each day of follow up


      # cumulative incidence rate ratio
      cmlirr = cml.rate_1 / cml.rate_0,
      cmlirr.ln.se = sqrt((1/cml.event_0) + (1/cml.event_1)),
      cmlirr.ll = exp(log(cmlirr) + qnorm(0.025)*cmlirr.ln.se),
      cmlirr.ul = exp(log(cmlirr) + qnorm(0.975)*cmlirr.ln.se),

      # survival ratio, standard error, and confidence limits, treating cause-specific death as a competing event
      sr = surv_1 / surv_0,
      #cisr.ln = log(cisr),
      sr.ln.se = (surv.se_0/surv_0) + (surv.se_1/surv_1), #because cmlhaz = -log(surv) and cmlhaz.se = surv.se/surv
      sr.ll = exp(log(sr) + qnorm(0.025)*sr.ln.se),
      sr.ul = exp(log(sr) + qnorm(0.975)*sr.ln.se),

      # risk ratio, standard error, and confidence limits, using delta method, , treating cause-specific death as a competing event
      rr = risk_1 / risk_0,
      #cirr.ln = log(cirr),
      rr.ln.se = sqrt((risk.se_1/risk_1)^2 + (risk.se_0/risk_0)^2),
      rr.ll = exp(log(rr) + qnorm(0.025)*rr.ln.se),
      rr.ul = exp(log(rr) + qnorm(0.975)*rr.ln.se),

      # risk difference, standard error and confidence limits, , treating cause-specific death as a competing event
      rd = risk_1 - risk_0,
      rd.se = sqrt( (risk.se_0^2) + (risk.se_1^2) ),
      rd.ll = rd + qnorm(0.025)*rd.se,
      rd.ul = rd + qnorm(0.975)*rd.se,



      # cumulative incidence rate difference
      #cmlird = cml.rate_1 - cml.rate_0
    )
}


contrasts_rounded_daily <- kmcontrasts(data_surv_rounded)
contrasts_rounded_cuts <- kmcontrasts(data_surv_rounded, postbaselinecuts)
contrasts_rounded_overall <- kmcontrasts(data_surv_rounded, c(0,maxfup))


write_csv(contrasts_rounded_daily, fs::path(output_dir, "contrasts_daily.csv"))
write_csv(contrasts_rounded_cuts, fs::path(output_dir, "contrasts_cuts.csv"))
write_csv(contrasts_rounded_overall, fs::path(output_dir, "contrasts_overall.csv"))




