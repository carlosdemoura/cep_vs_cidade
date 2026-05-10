library(tidyverse)
source("add_ibge.R")

susepe =
  read.csv(here::here("S_AUTO_2020A.csv"), sep =";") |>
  mutate(
    CEP = case_when(
      nchar(CEP) == 5 ~ 1000 * CEP,
      TRUE ~ CEP
    )
  ) |>
  add_ibge("CEP") |>
  mutate(
    CEP_ = case_when(
      is.na(COD_MUNICIPIO) & nchar(CEP) == 7 ~ CEP *10+1,
      is.na(COD_MUNICIPIO) & nchar(CEP) == 8 ~ CEP +1,
      is.na(COD_MUNICIPIO) & nchar(CEP) == 5 ~ CEP *1000,
      TRUE ~ CEP
    ),
    COD_MUNICIPIO = case_when(
      is.na(COD_MUNICIPIO) ~ add_ibge(CEP_, as.vec = T),
      TRUE ~ COD_MUNICIPIO
    )
  ) |>
  select(-CEP_)

susepe |>
  #filter(nchar(CEP)>=7) |>
  pull(COD_MUNICIPIO) |>
  is.na() |>
  mean()

# susepe |>
#   filter(is.na(COD_MUNICIPIO)) |>
#   select(-COD_MUNICIPIO) |>
#   pull(CEP) |>
#   unique() |>
#   sort()

saveRDS(susepe, "susepe.rds", compress = "xz")
