add_cep = function(data, cep.col, ibge.col = "COD_MUNICIPIO") {
  suppressPackageStartupMessages(library(data.table))
  
  ceps = read.csv(here::here("lista_cep_correios.csv"))
  setDT(ceps)
  
  setDT(data)
  data[, (cep.col) := as.integer(get(cep.col))]
  
  data[
    ceps,
    (ibge.col) := i.COD_MUNICIPIO,
    #on = .(CEP >= cep.min, CEP <= cep.max)
    on = c( paste0(cep.col, " >= cep.min"), paste0(cep.col, " <= cep.max") )
  ]

  tibble::as_tibble(data)
}


# susepe =
#   read.csv(here::here("S_AUTO_2020A.csv"), sep =";", nrows = 100) |>
#   add_cep(cep.col = "CEP")