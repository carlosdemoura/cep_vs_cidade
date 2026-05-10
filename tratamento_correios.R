library(tidyverse)

ibge =
  suppressWarnings(suppressMessages( readxl::read_xls(here::here("RELATORIO_DTB_BRASIL_2024_MUNICIPIOS.xls"), skip=5) )) |>
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
    ),
    municipio = case_when(
      uf == "RN" & municipio == "januario cicco" ~ "boa saude",
      TRUE ~ municipio
    )
  )


ceps =
  read.csv(here::here("output.csv")) |>
  as_tibble() |>
  select(-c(situacao, tipo_faixa)) |>
  rename(municipio = "localidade") |>
  mutate(
    municipio = stringi::stri_trans_general(tolower(municipio), "Latin-ASCII"),
    municipio = case_when(
      uf == "BA" & municipio == "muquem de sao francisco" ~ "muquem do sao francisco",
      uf == "BA" & municipio == "santa teresinha" ~ "santa terezinha",
      uf == "MA" & municipio == "pindare mirim" ~ "pindare-mirim",
      uf == "MG" & municipio == "amparo da serra" ~ "amparo do serra",
      uf == "MG" & municipio == "barao de monte alto" ~ "barao do monte alto",
      uf == "MG" & municipio == "olhos d'agua" ~ "olhos-d'agua",
      uf == "MG" & municipio == "sao thome das letras" ~ "sao tome das letras",
      uf == "MT" & municipio == "santo antonio do leverger" ~ "santo antonio de leverger",
      uf == "PE" & municipio == "lagoa do itaenga" ~ "lagoa de itaenga",
      uf == "RN" & municipio == "arez" ~ "ares",
      uf == "RN" & municipio == "olho-d'agua do borges" ~ "olho d'agua do borges",
      uf == "SC" & municipio == "grao para" ~ "grao-para",
      uf == "SE" & municipio == "amparo de sao francisco" ~ "amparo do sao francisco",
      uf == "TO" & municipio == "couto de magalhaes" ~ "couto magalhaes",
      TRUE ~ municipio
    )
  ) |>
  left_join(ibge, by = c("uf", "municipio")) |>
  select(-c(uf, municipio)) |>
  rename(COD_MUNICIPIO = "cod_municipio", cep.min = "faixa_inicio", cep.max = "faixa_fim") |>
  relocate(COD_MUNICIPIO) |>
  unique() |>
  mutate(
    across(
      c(cep.min, cep.max),
      function(x) as.integer(str_replace(x, "[-]", ""))
      )
  )

write.csv(ceps, "lista_cep_correios.csv", row.names = FALSE)
