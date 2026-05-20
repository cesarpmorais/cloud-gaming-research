# TODO — Implementação POC II

Cronograma semana-a-semana. Marcar `[x]` ao concluir.

## Semana 1 (13/04–19/04) — Preparação do PR #1
- [ ] Code walkthrough de `src/stream.cpp`: pontos de hook em `IDX_LOSS_STATS` e `IDX_REQUEST_IDR_FRAME`
- [ ] Definir esquema do CSV (colunas, formato, path, política de flush)
- [ ] Medir empiricamente a frequência de reporte do `IDX_LOSS_STATS` (3 cenários de rede)
- [ ] Fork `LizardByte/Sunshine` + branch `feat/session-metrics-export`
- [ ] Documentar tudo em `docs/implementacao/semana_1/`

## Semana 2 (20/04–26/04) — PR #1: implementação e submissão
- [ ] Implementar exportação CSV em `src/stream.cpp`
- [ ] Config key em `sunshine.conf` (ex: `metrics_export_path`)
- [ ] Testes gtest em `./tests/`
- [ ] Rodar `python ./scripts/update_clang_format.py`
- [ ] Abrir PR #1 (título: `feat(stats): export session metrics to CSV`)

## Semana 3 (28/04–03/05) — Testbed
- [ ] Script de automação para 6 cenários ABRAGame (A–F) via `tc netem`
- [ ] Validar cenários com `ping`/`iperf`
- [ ] Padronizar duração 240s por cenário
- [ ] Documentar setup (RTX 4070 Super, Fedora, X11, Moonlight Android)

## Semana 4 (04/05–10/05) — Baseline
- [ ] Rodar Sunshine com bitrate fixo nos 6 cenários
- [ ] Coletar CSVs gerados pelo PR #1
- [ ] Análise exploratória (plots de loss, IDR, estBW ao longo do tempo)
- [ ] Derivar thresholds candidatos para o controlador

## Semana 5 (11/05–17/05) — Issue + início do controlador
- [ ] Checar Apollo fork para evitar duplicação
- [ ] Abrir issue pública (problema + dados do baseline + esboço do algoritmo)
- [ ] Começar implementação (janela deslizante, agregação de sinais, hook de reconfig do encoder)

## Semana 6 (18/05–24/05) — PR #2 + pitch
- [ ] Finalizar controlador (decisão reduzir/incrementar, timer 20s)
- [ ] Flag `bitrate_mode = adaptive` em `sunshine.conf`
- [ ] Testes iniciais nos cenários
- [ ] Preparar pitch em vídeo
- [ ] **25/05 — Pitch Vídeo (entrega)**

## Semanas 7–8 (26/05–08/06) — Testes comparativos
- [ ] Rodar controlador nos 6 cenários
- [ ] Calcular métricas (cancelamento de frame loss, tempo de recuperação, falsos positivos, variância do bitrate)
- [ ] Iterar com feedback da issue e do pitch
- [ ] Investigar segunda variante (sinal preditivo) se baseline justificar

## Semana 9 (09/06–15/06) — Análise final + relatório
- [ ] Consolidar resultados comparativos
- [ ] Plots finais baseline vs. adaptativo
- [ ] Começar escrita do relatório (expandir proposta para formato TCC completo)

## Semana 10 (16/06–21/06) — Relatório + pôster
- [ ] Finalizar relatório
- [ ] Preparar pôster científico
- [ ] **21/06 — Entrega do pôster para impressão**

## Semana 11 (22/06–26/06) — Revisão + apresentação
- [ ] Revisão final do relatório com orientador
- [ ] Ensaio da apresentação do pôster
- [ ] **26/06 — Apresentação final presencial**

## Semana 12 (27/06–03/07) — Entregas finais
- [ ] Ajustes finais no relatório
- [ ] **29/06 — Entrega PDF no Moodle**
- [ ] **03/07 — Entrega na plataforma DCC (POC II)**
- [ ] Atualizar grafo do Obsidian com estado final da base de conhecimento
