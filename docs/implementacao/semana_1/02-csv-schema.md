# Schema do CSV de métricas de sessão

> **Revisado em 2026-04-21** após descoberta empírica de que `IDX_LOSS_STATS` nunca é recebido quando o cliente é Moonlight→Sunshine. O schema agora deriva da struct `SS_FRAME_FEC_STATUS` (0x5502). Ver `01-code-walkthrough.md`.

## Decisão: sem coluna de bandwidth estimada

O Sunshine não calcula estimativa de largura de banda server-side (ver `01-code-walkthrough.md`, seção 4). O PR #1 exporta apenas dados que já existem no protocolo. Estimativa de bandwidth fica para o PR #2 (controlador).

## Colunas

| Coluna | Tipo | Fonte | Descrição |
|--------|------|-------|-----------|
| `timestamp_ms` | int64 | `steady_clock::now()` desde epoch | Momento da medição (monotônico) |
| `session_id` | uint32 | `session->launch_session_id` | Identificador da sessão |
| `bitrate_kbps` | int | `session->config.monitor.bitrate` | Bitrate de encoding configurado (fixo durante sessão) |
| `frame_index` | uint32 | `SS_FRAME_FEC_STATUS.frameIndex` | Número do frame reportado |
| `missing_packets` | uint16 | `SS_FRAME_FEC_STATUS.missingPacketsBeforeHighestReceived` | Pacotes faltando antes do mais alto recebido |
| `total_data_packets` | uint16 | `SS_FRAME_FEC_STATUS.totalDataPackets` | Pacotes de dados enviados no frame |
| `received_data_packets` | uint16 | `SS_FRAME_FEC_STATUS.receivedDataPackets` | Pacotes de dados recebidos com sucesso |
| `total_parity_packets` | uint16 | `SS_FRAME_FEC_STATUS.totalParityPackets` | Pacotes de paridade FEC enviados |
| `received_parity_packets` | uint16 | `SS_FRAME_FEC_STATUS.receivedParityPackets` | Pacotes de paridade FEC recebidos |
| `fec_percentage` | uint8 | `SS_FRAME_FEC_STATUS.fecPercentage` | Percentual de FEC configurado |
| `idr_request_count` | int | Contador acumulado (implementar) | IDR requests acumulados desde o último evento FEC |

Total: 11 colunas.

### Campos omitidos da struct

- `highestReceivedSequenceNumber`, `nextContiguousSequenceNumber` — úteis para debug de sequência, mas não agregam sinal claro para o controlador. Podem ser adicionados futuramente se necessário.
- `multiFecBlockIndex`, `multiFecBlockCount` — só relevantes em streams 4K+ com multi-block FEC. Fora do escopo do PR #1.

## Formato

- **Separador:** vírgula (`,`)
- **Header:** primeira linha com nomes das colunas
- **Encoding:** UTF-8
- **Quebra de linha:** `\n` (LF)
- **Valores numéricos:** sem aspas, sem separador de milhares
- **Endianness:** todos os campos numéricos da struct são recebidos em **big-endian** do Moonlight e devem ser convertidos com `ntohl`/`ntohs` antes de gravar.

Exemplo (com 5% de perda artificial):
```
timestamp_ms,session_id,bitrate_kbps,frame_index,missing_packets,total_data_packets,received_data_packets,total_parity_packets,received_parity_packets,fec_percentage,idr_request_count
1713045600123,42,20000,1523,3,48,45,12,12,20,0
1713045600187,42,20000,1547,7,48,41,12,11,20,0
1713045600251,42,20000,1571,2,48,46,12,12,20,1
```

## Arquivo

- **Um arquivo por sessão**, criado ao receber o primeiro `SS_FRAME_FEC_STATUS` (lazy open — sessões sem perda não geram arquivo)
- **Nome:** `sunshine_metrics_<session_id>_<timestamp>.csv`
- **Diretório:** configurável via `sunshine.conf` (proposta: chave `metrics_path`)
- **Default:** desabilitado (sem path = sem exportação), para não impactar quem não quer

## Estratégia de escrita

**Escrita síncrona com `std::ofstream`**, uma linha por `SS_FRAME_FEC_STATUS` recebido.

Justificativa:
- O handler roda na **thread de controle** (ver walkthrough, seção 5) — separada das threads de encoding e transmissão. Overhead de I/O aqui não afeta latência de vídeo.
- O sinal é **event-driven e esparso**: só dispara quando há perda/recovery. Empiricamente, 25 eventos em 60s com 5% de perda artificial (≤1 evento/s no pior caso testado). Rede limpa = 0 eventos.
- Buffer in-memory + flush periódico adiciona complexidade sem benefício mensurável nesse volume.
- `std::ofstream` com flush implícito no `<<` + `'\n'` é suficiente. Sem necessidade de `std::endl` (que força flush a cada linha).

## Contador de IDR requests

O handler de `IDX_REQUEST_IDR_FRAME` (stream.cpp:951) e o novo handler de `SS_FRAME_FEC_STATUS` rodam na mesma thread de controle, então não precisam de `std::atomic`. Um `int` simples na session basta:

- Incrementar no handler de `IDX_REQUEST_IDR_FRAME`
- Ler e resetar para 0 no handler de `SS_FRAME_FEC_STATUS` (no momento da escrita)

Se a thread de vídeo também acessar esse contador no futuro (PR #2), aí sim precisa de `std::atomic`.

## Loss rate derivado (pós-processamento)

Com `missing_packets` e `total_data_packets`, qualquer análise offline pode calcular:

```
loss_rate_frame = missing_packets / total_data_packets
recovery_rate  = received_parity_packets / total_parity_packets
```

Não incluímos essas colunas derivadas para manter o CSV enxuto e sem redundância.

## Próximo passo

Medir e documentar a frequência real de eventos `SS_FRAME_FEC_STATUS` sob diferentes condições de rede (artefato `03-report-frequency.md`). Essa frequência determina a resolução temporal útil do CSV e, futuramente, da janela deslizante do controlador do PR #2.
