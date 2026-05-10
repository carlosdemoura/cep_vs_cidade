add_ibge = function(data, cep.col, ibge.col = "COD_MUNICIPIO", as.vec = F) {
  suppressPackageStartupMessages(library(data.table))
  suppressPackageStartupMessages(library(dplyr))
  
  ceps = read.csv(here::here("lista_cep_correios.csv"))
  setDT(ceps)
  
  if (as.vec) {
    data = data.table(CEP = data)
    cep.col = "CEP"
  }
  
  setDT(data)
  data[, (cep.col) := as.integer(get(cep.col))]
  
  data[
    ceps,
    (ibge.col) := i.COD_MUNICIPIO,
    #on = .(CEP >= cep.min, CEP <= cep.max)
    on = c( paste0(cep.col, " >= cep.min"), paste0(cep.col, " <= cep.max") )
  ]

  data = as_tibble(data)
  
  if ( any( is.na(data[[ibge.col]]) ) ) {
    data = mutate(data, .row_number = row_number())
    
    data1 =
      data |>
      filter(is.na(.data[[ibge.col]])) |>
      select(-all_of(ibge.col))
    data2 = filter(data, !is.na(.data[[ibge.col]]))
    
    cep_ibge = readRDS("cep_ibge.rds")
    setDT(data1)
    setDT(cep_ibge)
    
    data1[
      cep_ibge,
      (ibge.col) := i.COD_MUNICIPIO,
      on = setNames("CEP", cep.col)
    ]
    
    # data1 |>
    #   select(-all_of(ibge.col)) |>
    #   left_join(cep_ibge, by = c("CEP" = cep.col))
    
    data =
      bind_rows(data1, data2) |>
      arrange(.row_number) |>
      select(-.row_number)
  }
  
  if (as.vec) {
    return(pull(data, all_of(ibge.col)))
  } else {
    return(data)
  }
}
