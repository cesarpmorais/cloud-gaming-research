# Semana 1 (13/04–19/04) — Preparação do PR #1

## Objetivo

Terminar a semana com base técnica sólida para escrever o PR #1 na Semana 2. **Não escrever código de produção ainda** — o foco é entendimento, decisões de design e medição empírica.

## Definição de pronto

Ao final da semana, os seguintes artefatos devem existir em `docs/implementacao/semana_1/`:

1. Code walkthrough do caminho `IDX_LOSS_STATS` / `IDX_REQUEST_IDR_FRAME` em `src/stream.cpp`
2. Esquema do CSV definido (colunas, formato, path, política de flush)
3. Medição empírica da frequência do `IDX_LOSS_STATS` em 3 cenários de rede
4. Fork + branch configurados no GitHub
5. Resumo da semana (aprendizados, decisões, riscos)

## Entregáveis detalhados

### 1. `01-code-walkthrough.md`
Mapear o caminho completo das mensagens de feedback em `src/stream.cpp`:
- Função que recebe `IDX_LOSS_STATS` do cliente, struct do payload, linha onde o log atual é emitido
- Mesma análise para `IDX_REQUEST_IDR_FRAME`
- Como acessar no mesmo contexto: bitrate configurado, `estBW`, timestamp de sessão, session ID
- Identificar **ponto exato de hook** (arquivo:linha) para a exportação CSV

### 2. `02-csv-schema.md`
Decisões de design do arquivo de saída:
- Colunas propostas: `timestamp_ms, session_id, bitrate_kbps, lost_packets, total_packets, idr_requests, est_bandwidth_kbps`
- Formato: header, separador, encoding
- Path de escrita: config key em `sunshine.conf` (proposta: `metrics_export_path`)
- Política: escrita síncrona vs. buffer + flush periódico — análise de impacto na latência do hot path
- Rotação: arquivo por sessão vs. append único

### 3. `03-report-frequency.md`
Medição empírica (requer build local do Sunshine):
- Build debug em `cmake-build-debug`
- Patch temporário: log com timestamp a cada `IDX_LOSS_STATS` recebido (não committar)
- Rodar 3 sessões de 60s: rede estável, perda artificial 2%, perda artificial 10%
- Métricas: média, mediana, p95 do intervalo entre mensagens
- Conclusão: resolução temporal viável para a janela deslizante do controlador

### 4. `04-fork-setup.md`
Infraestrutura git (executado pelo Cesar):
- Fork `LizardByte/Sunshine` → `cesarpmorais/Sunshine`
- Remote `upstream` → LizardByte
- Branch `feat/session-metrics-export` a partir do `master`
- Registrar URLs dos remotes e hash do commit base

### 5. `99-resumo.md`
Síntese final da semana:
- O que foi aprendido sobre o código
- Decisões de design tomadas e justificativa
- Riscos identificados (ex: frequência insuficiente, overhead de I/O)
- O que fica pronto para iniciar a Semana 2

## Ordem de execução

1. **Code walkthrough** — Claude faz com Read/Grep, Cesar revisa
2. **Schema do CSV** — recomendação do Claude, decisão do Cesar
3. **Fork + branch** — Cesar executa (requer conta GitHub)
4. **Build debug + medição de frequência** — execução conjunta (build demora)
5. **Resumo** — Claude rascunha, Cesar edita

## Fora de escopo

- Código de produção em `src/stream.cpp`
- Testes gtest
- Abertura de PR
- Qualquer decisão sobre o algoritmo do controlador (fica pra Semana 5+)
