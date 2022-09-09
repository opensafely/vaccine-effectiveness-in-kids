


ceiling_any <- function(x, to=1){
  # round to nearest 100 millionth to avoid floating point errors
  ceiling(plyr::round_any(x/to, 1/100000000))*to
}

roundmid_any <- function(x, to=1){
  # like ceiling_any, but centers on (integer) midpoint of the rounding points
  ceiling(x/to)*to - (floor(to/2)*(x!=0))
}


fct_case_when <- function(...) {
  # uses dplyr::case_when but converts the output to a factor,
  # with factors ordered as they appear in the case_when's  ... argument
  args <- as.list(match.call())
  levels <- sapply(args[-1], function(f) f[[3]])  # extract RHS of formula
  levels <- levels[!is.na(levels)]
  factor(dplyr::case_when(...), levels=levels)
}


postvax_cut <- function(event_time, time, breaks, prelabel="pre", prefix=""){

  # this function defines post-vaccination time-periods at `time`,
  # for a vaccination occurring at time `event_time`
  # delimited by `breaks`

  # note, intervals are open on the left and closed on the right
  # so at the exact time point the vaccination occurred, it will be classed as "pre-dose".

  event_time <- as.numeric(event_time)
  event_time <- if_else(!is.na(event_time), event_time, Inf)

  diff <- time - event_time
  breaks_aug <- unique(c(-Inf, breaks, Inf))
  labels0 <- cut(c(breaks, Inf), breaks_aug)
  labels <- paste0(prefix, c(prelabel, as.character(labels0[-1])))
  period <- cut(diff, breaks=breaks_aug, labels=labels, include.lowest=TRUE)


  period
}

# define post-vaccination time periods for piece-wise constant hazards (ie time-varying effects / time-varying coefficients)
# eg c(0, 10, 21) will create 4 periods
# pre-vaccination, [0, 10), [10, 21), and [21, inf)
# can use eg c(3, 10, 21) to treat first 3 days post-vaccination the same as pre-vaccination
# note that the exact vaccination date is set to the first "pre-vax" period,
# because in survival analysis, intervals are open-left and closed-right.


timesince_cut <- function(time_since, breaks, prefix=""){

  # this function defines post-vaccination time-periods at `time_since`,
  # delimited by `breaks`

  # note, intervals are open on the left and closed on the right
  # so at the exact time point the vaccination occurred, it will be classed as "pre-dose".

  stopifnot("time_since should be strictly non-negative" = time_since>=0)
  time_since <- as.numeric(time_since)
  time_since <- if_else(!is.na(time_since), time_since, Inf)

  breaks_aug <- unique(c(breaks, Inf))

  lab_left <- breaks+1
  lab_right <- lead(breaks)
  label <- paste0(lab_left, "-", lab_right)
  label <- str_replace(label,"-NA", "+")
  labels <- paste0(prefix, label)

  #labels0 <- cut(c(breaks, Inf), breaks_aug)
  #labels <- paste0(prefix, c(prelabel, as.character(labels0[-1])))
  period <- cut(time_since, breaks=breaks_aug, labels=labels, include.lowest=TRUE)

  period
}