"""
correios_cep.py — Scraper de faixas de CEP dos Correios
========================================================

Usa Selenium com o Chrome instalado na sua máquina para contornar
os bloqueios do servidor (o site rejeita requests sem browser real).

Dependências:
    pip install selenium beautifulsoup4

O Chrome/Chromium precisa estar instalado.
O chromedriver é baixado automaticamente pelo Selenium 4.6+.

Uso:
    python correios_cep.py --ufs RN
    python correios_cep.py --ufs RN PB CE
    python correios_cep.py                      # todas as 27 UFs
    python correios_cep.py --ufs SP --output sp.csv
    python correios_cep.py --visible            # abre o browser visível (útil para debug)
"""

import csv
import re
import sys
import time
import argparse
import tempfile
from pathlib import Path
from datetime import datetime

from bs4 import BeautifulSoup
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import Select, WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.common.exceptions import TimeoutException, NoSuchElementException

# ---------------------------------------------------------------------------
# Constantes
# ---------------------------------------------------------------------------

INDEX_URL = "https://buscacepinter.correios.com.br/app/faixa_cep_uf_localidade/index.php"

UF_LIST = [
    "AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO",
    "MA", "MG", "MS", "MT", "PA", "PB", "PE", "PI", "PR",
    "RJ", "RN", "RO", "RR", "RS", "SC", "SE", "SP", "TO",
]

# ---------------------------------------------------------------------------
# Browser
# ---------------------------------------------------------------------------

def _make_driver(headless: bool = True) -> webdriver.Chrome:
    opts = Options()
    if headless:
        opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-blink-features=AutomationControlled")
    opts.add_experimental_option("excludeSwitches", ["enable-automation"])
    opts.add_experimental_option("useAutomationExtension", False)
    opts.add_argument(
        "user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    )
    driver = webdriver.Chrome(options=opts)
    driver.execute_script(
        "Object.defineProperty(navigator, 'webdriver', {get: () => undefined})"
    )
    return driver


# ---------------------------------------------------------------------------
# Captcha
# ---------------------------------------------------------------------------

def _solve_captcha(driver: webdriver.Chrome) -> str:
    """Tira screenshot do elemento captcha e pede ao usuário que leia."""
    tmp = Path(tempfile.mktemp(suffix=".png"))
    try:
        el = driver.find_element(By.ID, "captcha_image")
        el.screenshot(str(tmp))
        print(f"\n[CAPTCHA] Imagem salva em: {tmp.resolve()}")
    except NoSuchElementException:
        driver.save_screenshot(str(tmp))
        print(f"\n[CAPTCHA] Screenshot da página em: {tmp.resolve()}")

    answer = input("  >> Digite o texto do captcha: ").strip()
    tmp.unlink(missing_ok=True)
    return answer


# ---------------------------------------------------------------------------
# Parse — sempre a partir do page_source, nunca de elementos guardados
# (elementos guardados ficam "stale" quando o JS reescreve o DOM)
# ---------------------------------------------------------------------------

def _parse_faixa(raw: str) -> tuple[str, str]:
    parts = re.split(r"\s+a\s+", raw.strip(), maxsplit=1)
    return (parts[0].strip(), parts[1].strip()) if len(parts) == 2 else (raw.strip(), "")


def _parse_page(html: str, uf: str) -> list[dict]:
    """Extrai registros da tabela #resultado-DNEC a partir do HTML estático."""
    soup = BeautifulSoup(html, "html.parser")
    table = soup.find("table", {"id": "resultado-DNEC"})
    if not table:
        return []
    records = []
    for row in table.select("tbody tr"):
        cells = [td.get_text(strip=True) for td in row.find_all("td")]
        if len(cells) < 4:
            continue
        inicio, fim = _parse_faixa(cells[1])
        records.append({
            "uf":           uf,
            "localidade":   cells[0],
            "faixa_inicio": inicio,
            "faixa_fim":    fim,
            "situacao":     cells[2],
            "tipo_faixa":   cells[3],
        })
    return records


def _get_total(html: str) -> int:
    soup = BeautifulSoup(html, "html.parser")
    nav = soup.find("div", {"id": "navegacao-total"})
    if nav:
        m = re.search(r"de\s+(\d+)", nav.get_text())
        if m:
            return int(m.group(1))
    return 0


def _captcha_failed(html: str) -> bool:
    lc = html.lower()
    return "captcha" in lc and any(w in lc for w in ("inválido", "invalido", "incorreto"))


# ---------------------------------------------------------------------------
# Waits
# ---------------------------------------------------------------------------

def _wait_rows(driver: webdriver.Chrome, timeout: int = 15) -> None:
    """Aguarda pelo menos 1 linha na tabela ou mensagem de erro."""
    WebDriverWait(driver, timeout).until(lambda d: (
        len(d.find_elements(By.CSS_SELECTOR, "#resultado-DNEC tbody tr")) > 0
        or d.find_element(By.ID, "mensagem-resultado").text.strip() not in ("", "\xa0", ".", "&nbsp;.")
    ))


def _wait_page_change(driver: webdriver.Chrome, old_first_cell: str, timeout: int = 15) -> None:
    """Aguarda o DOM ser reescrito com novos dados após clicar em Próximo.

    Compara o texto da primeira célula — quando mudar, o novo DOM está pronto.
    """
    def _first_cell(d):
        try:
            return d.find_element(By.CSS_SELECTOR, "#resultado-DNEC tbody tr td").text.strip()
        except NoSuchElementException:
            return old_first_cell  # ainda não atualizou

    WebDriverWait(driver, timeout).until(lambda d: _first_cell(d) != old_first_cell)


# ---------------------------------------------------------------------------
# Paginação
# ---------------------------------------------------------------------------

def _has_next(driver: webdriver.Chrome) -> bool:
    """Retorna True se o botão Próximo estiver visível e clicável."""
    try:
        btn = driver.find_element(By.CSS_SELECTOR, "a.botao.proximo")
        classes = btn.get_attribute("class") or ""
        return "esconde" not in classes and "disabled" not in classes
    except NoSuchElementException:
        return False


def _click_next(driver: webdriver.Chrome) -> None:
    driver.find_element(By.CSS_SELECTOR, "a.botao.proximo").click()


# ---------------------------------------------------------------------------
# Scraping de uma UF
# ---------------------------------------------------------------------------

def _scrape_uf(uf: str, driver: webdriver.Chrome, retries: int, page_delay: float) -> list[dict]:
    print(f"[{uf}] Iniciando...")

    for attempt in range(1, retries + 1):
        driver.get(INDEX_URL)
        time.sleep(1.5)

        # Seleciona a UF
        try:
            WebDriverWait(driver, 10).until(EC.presence_of_element_located((By.ID, "uf")))
            Select(driver.find_element(By.ID, "uf")).select_by_value(uf)
        except TimeoutException:
            print(f"[{uf}] Timeout aguardando formulário (tentativa {attempt})")
            continue

        # Resolve o captcha
        captcha_text = _solve_captcha(driver)
        
        if not captcha_text:
            print(f"[{uf}] Captcha vazio — UF ignorada.\n")
            return []
        
        campo = driver.find_element(By.ID, "captcha")
        campo.clear()
        campo.send_keys(captcha_text)
        driver.find_element(By.ID, "btn_pesquisar").click()

        # Aguarda resultado
        try:
            _wait_rows(driver, timeout=15)
        except TimeoutException:
            print(f"[{uf}] Timeout aguardando resultados (tentativa {attempt})")
            continue

        html = driver.page_source

        if _captcha_failed(html):
            print(f"[{uf}] Captcha incorreto (tentativa {attempt}/{retries})")
            continue

        rows = _parse_page(html, uf)
        if not rows:
            print(f"[{uf}] Nenhum resultado (tentativa {attempt}/{retries})")
            continue

        total = _get_total(html)
        print(f"[{uf}] Pág. 1 — {len(rows)} registros (total: {total})")
        all_records = rows[:]

        # Paginação
        page_num = 2
        while _has_next(driver):
            time.sleep(page_delay)

            # Guarda o texto da primeira célula antes de clicar
            try:
                old_cell = driver.find_element(
                    By.CSS_SELECTOR, "#resultado-DNEC tbody tr td"
                ).text.strip()
            except NoSuchElementException:
                break

            _click_next(driver)

            # Aguarda o DOM ser substituído
            try:
                _wait_page_change(driver, old_cell, timeout=15)
            except TimeoutException:
                print(f"[{uf}] Timeout na pág. {page_num}")
                break

            html = driver.page_source
            page_rows = _parse_page(html, uf)
            if not page_rows:
                break

            all_records.extend(page_rows)
            print(f"[{uf}] Pág. {page_num} — {len(page_rows)} registros")
            page_num += 1

        print(f"[{uf}] Concluído — {len(all_records)} registros.\n")
        return all_records

    print(f"[{uf}] AVISO: falha após {retries} tentativas — UF ignorada.\n")
    return []


# ---------------------------------------------------------------------------
# Função principal
# ---------------------------------------------------------------------------

def scrape_cep(
    ufs:        list[str] | None = None,
    output:     str | None       = None,
    headless:   bool             = True,
    page_delay: float            = 1.5,
    retries:    int              = 3,
) -> list[dict]:
    """
    Raspa as faixas de CEP dos Correios e salva em CSV.

    Args:
        ufs:        UFs a raspar (ex: ["RN", "SP"]). None = todas as 27.
        output:     Caminho do CSV. None = nome automático com timestamp.
        headless:   False abre o Chrome visível (útil para debug).
        page_delay: Pausa em segundos entre páginas.
        retries:    Tentativas por captcha antes de pular a UF.

    Returns:
        Lista de dicts: uf, localidade, faixa_inicio, faixa_fim, situacao, tipo_faixa
    """
    target_ufs = ufs or UF_LIST
    driver = _make_driver(headless=headless)
    all_records: list[dict] = []

    try:
        for uf in target_ufs:
            records = _scrape_uf(uf, driver, retries=retries, page_delay=page_delay)
            all_records.extend(records)
    finally:
        driver.quit()

    if not output:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        output = f"faixas_cep_{ts}.csv"

    fields = ["uf", "localidade", "faixa_inicio", "faixa_fim", "situacao", "tipo_faixa"]
    with open(output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(all_records)

    print(f"=== Total: {len(all_records)} registros → {output} ===")
    return all_records


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Scraper de faixas de CEP dos Correios (usa Chrome via Selenium).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--ufs", nargs="+", metavar="UF",
                        help="UFs a raspar (ex: RN SP MG). Padrão: todas.")
    parser.add_argument("--output", metavar="ARQUIVO",
                        help="Nome do CSV de saída.")
    parser.add_argument("--visible", action="store_true",
                        help="Abre o Chrome visível em vez de headless.")
    parser.add_argument("--delay", type=float, default=1.5, metavar="SEG",
                        help="Pausa entre páginas em segundos (padrão: 1.5).")
    parser.add_argument("--retries", type=int, default=3, metavar="N",
                        help="Tentativas por captcha (padrão: 3).")
    args = parser.parse_args()

    if args.ufs:
        ufs = [u.upper() for u in args.ufs]
        bad = [u for u in ufs if u not in UF_LIST]
        if bad:
            print(f"UFs inválidas: {', '.join(bad)}")
            print(f"UFs válidas:   {', '.join(UF_LIST)}")
            sys.exit(1)
    else:
        ufs = None

    scrape_cep(
        ufs=ufs,
        output=args.output,
        headless=not args.visible,
        page_delay=args.delay,
        retries=args.retries,
    )
