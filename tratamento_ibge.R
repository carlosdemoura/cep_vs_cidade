options(timeout = 100000)
library(tidyverse)


url_basico = "https://ftp.ibge.gov.br/Cadastro_Nacional_de_Enderecos_para_Fins_Estatisticos/Censo_Demografico_2022/Arquivos_CNEFE/CSV/UF"
ufs_nomes_codigos = c("11_RO.zip", "12_AC.zip", "13_AM.zip", "14_RR.zip", "15_PA.zip", "16_AP.zip", "17_TO.zip", "21_MA.zip", "22_PI.zip", "23_CE.zip", "24_RN.zip", "25_PB.zip", "26_PE.zip", "27_AL.zip", "28_SE.zip", "29_BA.zip", "31_MG.zip", "32_ES.zip", "33_RJ.zip", "35_SP.zip", "41_PR.zip", "42_SC.zip", "43_RS.zip", "50_MS.zip", "51_MT.zip", "52_GO.zip", "53_DF.zip")

#destino_temp = tempdir()
destino_temp ="/tmp/RtmpDuJC19"
destino_unzip = file.path(destino_temp, "cnefe_unzips")
for (uf in ufs_nomes_codigos) {
  destino_zip   = file.path(destino_temp, uf)
  if (file.exists(  sub("\\.zip$", ".csv", file.path(destino_unzip, uf))  )) next
  download.file(file.path(url_basico, uf), destfile = destino_zip, mode = "wb")
  unzip(destino_zip, exdir = destino_unzip)
  unlink(destino_zip)
}

cep_por_setor = list()
for (file in list.files(destino_unzip, full.names = T)) {
  cep_por_setor[[basename(file)]] =
    read.csv(file, sep = ";") |>
    as_tibble() |>
    select(COD_SETOR, CEP) |>
    mutate(
      COD_SETOR = sub("P$", "", COD_SETOR) |> as.numeric()
    ) |>
    unique()
}

cep_por_setor = do.call(rbind, cep_por_setor)




cep_por_setor = readRDS("~/Downloads/cep_por_setor.rds")

cep_por_cidade =
  cep_por_setor |>
  mutate(
    COD_MUNICIPIO = substr(COD_SETOR,1,7) |> as.numeric()
  ) |>
  select(-COD_SETOR) |>
  unique() |>
  add_count(CEP) |>  # Excluindo CEPs em mais de uma cidade
  filter(n == 1) |>
  select(-n)

susepe =
  read.csv("~/Documentos/S_AUTO_2020A.csv", sep =";") |>
  as_tibble() |>
  left_join(cep_por_cidade, by = "CEP")

