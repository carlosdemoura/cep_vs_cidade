# https://gist.github.com/tamnil/792a6a66f6df9fc028041587cfca0c3d

library(tidyverse)
library(data.table)

ibge =
  readxl::read_xls("RELATORIO_DTB_BRASIL_2024_MUNICIPIOS.xls", skip=5) |>
  select(Nome_Município, `Código Município Completo`, Nome_UF) |>
  `colnames<-`(c("municipio", "cod_municipio", "uf")) |>
  mutate(
    cod_municipio = as.integer(cod_municipio),
    municipio = stringi::stri_trans_general(tolower(municipio), "Latin-ASCII"),
    uf = case_when(
      uf == "Rondônia" ~ "RO",
      uf == "Acre" ~ "AC",
      uf == "Amazonas" ~ "AM",
      uf == "Roraima" ~ "RR",
      uf == "Pará" ~ "PA",
      uf == "Amapá" ~ "AP",
      uf == "Tocantins" ~ "TO",
      uf == "Maranhão" ~ "MA",
      uf == "Piauí" ~ "PI",
      uf == "Ceará" ~ "CE",
      uf == "Rio Grande do Norte" ~ "RN",
      uf == "Paraíba" ~ "PB",
      uf == "Pernambuco" ~ "PE",
      uf == "Alagoas" ~ "AL",
      uf == "Sergipe" ~ "SE",
      uf == "Bahia" ~ "BA",
      uf == "Minas Gerais" ~ "MG",
      uf == "Espírito Santo" ~ "ES",
      uf == "Rio de Janeiro" ~ "RJ",
      uf == "São Paulo" ~ "SP",
      uf == "Paraná" ~ "PR",
      uf == "Santa Catarina" ~ "SC",
      uf == "Rio Grande do Sul" ~ "RS",
      uf == "Mato Grosso do Sul" ~ "MS",
      uf == "Mato Grosso" ~ "MT",
      uf == "Goiás" ~ "GO",
      uf == "Distrito Federal" ~ "DF",
      TRUE ~ NA_character_
    )
  )

ceps =
  read.csv(here::here("ceps2.csv")) |>
  as_tibble() |>
  filter(CIDADE != "") |>
  mutate(CIDADE = stringi::stri_trans_general(tolower(CIDADE), "Latin-ASCII")) |>
  left_join(ibge, by = c("UF" = "uf", "CIDADE" = "municipio")) |>
  as_tibble() |>
  relocate("cod_municipio", .before = "CEP.DE") |>  # há algum problema de escrito no nome de +- 40 cidades
  filter(!is.na(cod_municipio)) |>
  select(-c(UF, CIDADE))


susepe =
  read.csv(here::here("S_AUTO_2020A.csv"), sep =";") |>
  as_tibble()

# converter para data.table sem copiar desnecessariamente
setDT(susepe)
setDT(ceps)

# garantir tipo inteiro
susepe[, CEP := as.integer(CEP)]
ceps[, `:=`(
  CEP.DE = as.integer(CEP.DE),
  CEP.ATÉ = as.integer(CEP.ATÉ)
)]

# criar chave de intervalo
setkey(ceps, CEP.DE, CEP.ATÉ)

# join por intervalo
susepe[
  ceps,
  cod_municipio := cod_municipio,
  on = .(CEP >= CEP.DE, CEP <= CEP.ATÉ)
]

susepe =
  susepe |>
  as_tibble() |>
  filter(!is.na(cod_municipio))
