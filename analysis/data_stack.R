library('here')
library('arrow')
library('tidyverse')

treated<-read_feather(here("output", "input_treated.feather")) %>%
  mutate(treated=TRUE)

control<-read_feather(here("output", "input_control.feather")) %>%
  mutate(treated=FALSE)

input <-treated %>% 
  bind_rows(control)  %>%
   mutate(across(ends_with("_date"),  as.Date))
 

write_feather(input,here("output", "input.feather"))
