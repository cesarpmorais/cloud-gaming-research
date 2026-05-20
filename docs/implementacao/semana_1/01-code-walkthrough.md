# Code Walkthrough: Sinais de feedback em `src/stream.cpp`

## TL;DR (confirmado empiricamente)

O ponto de hook correto para o PR #1 é **registrar um handler para `0x5502` (SS_FRAME_FEC_STATUS)** em `stream.cpp`, não para `IDX_LOSS_STATS`. O handler atual de `IDX_LOSS_STATS` **nunca é chamado** quando o cliente é Moonlight conectando a Sunshine.

---

## Resumo da investigação

### Hipótese inicial (da proposta)

`IDX_LOSS_STATS` (0x0201) é o ponto onde o servidor recebe estatísticas de perda do cliente.

### O que o código do Moonlight revelou

Em `moonlight-common-c/src/ControlStream.c:1309-1408`, existem **dois protocolos**:

- **Path legado (GameStream)**: envia `IDX_LOSS_STATS` a cada 50 ms, **com `loss_count` hardcoded = 0**
- **Path Sunshine**: envia `SS_FRAME_FEC_STATUS` (0x5502) **apenas quando há perda/recovery**, com dados detalhados por frame

Assertion explícita na linha 1370: `LC_ASSERT(!IS_SUNSHINE())` — impede o path legado de rodar quando conectado a Sunshine.

### O que o código do Sunshine revelou

`0x5502` é enviado pelo servidor como "Set RGB LED" (extensão de gamepad), mas **não há handler registrado para recebê-lo**. Quando o Moonlight envia FEC status, o Sunshine cai no branch `type [Unknown]` em `stream.cpp:557-562` e descarta.

### Verificação empírica (sessão de 2026-04-21 12:05–12:06)

Com `tc netem loss 5%` aplicado na interface `eno1`, conectando Moonlight Android → Sunshine por ~60s:

| Evento | Contagem |
|--------|----------|
| `IDX_LOSS_STATS` recebido | **0** |
| `SS_FRAME_FEC_STATUS` recebido | **25** |

Payload do `SS_FRAME_FEC_STATUS` chegou com `payload_size=21` — bate exatamente com a struct esperada (4+14+3 bytes).

Adicionalmente: o Moonlight exibiu a mensagem "conexão lenta, reduza a taxa de bits". Isso é gerado **client-side** (ControlStream.c:444), com base na taxa de frame loss que o próprio Moonlight calcula. É apenas uma notificação ao usuário — não aciona nenhuma lógica no servidor.

---

## 1. SS_FRAME_FEC_STATUS (0x5502) — O SINAL REAL

### Struct (moonlight-common-c/src/Video.h:56-68, big-endian)

```c
typedef struct _SS_FRAME_FEC_STATUS {
    uint32_t frameIndex;                           // 4 bytes
    uint16_t highestReceivedSequenceNumber;        // 2
    uint16_t nextContiguousSequenceNumber;         // 2
    uint16_t missingPacketsBeforeHighestReceived;  // 2
    uint16_t totalDataPackets;                     // 2
    uint16_t totalParityPackets;                   // 2
    uint16_t receivedDataPackets;                  // 2
    uint16_t receivedParityPackets;                // 2
    uint8_t  fecPercentage;                        // 1
    uint8_t  multiFecBlockIndex;                   // 1
    uint8_t  multiFecBlockCount;                   // 1
} SS_FRAME_FEC_STATUS;  // total: 21 bytes
```

### Campos úteis para o controlador

| Campo | Significado | Uso |
|-------|-------------|-----|
| `frameIndex` | Número do frame | Tracking temporal, detecta gaps |
| `missingPacketsBeforeHighestReceived` | Pacotes faltando | **Sinal direto de perda** |
| `totalDataPackets` | Pacotes enviados do frame | Denominador para loss rate |
| `receivedDataPackets` | Pacotes recebidos com sucesso | Goodput efetivo |
| `totalParityPackets` / `receivedParityPackets` | FEC enviado / recebido | Eficácia da redundância |
| `fecPercentage` | % FEC configurado | Contexto |

### Quando é enviado (moonlight-common-c/src/RtpVideoQueue.c)

A função `reportFinalFrameFecStatus()` é chamada em três pontos:
1. **Após FEC recovery bem-sucedido** (linha 344) — recuperou pacotes via paridade
2. **Frame descartado por chegar tarde** (linha 596) — FEC não foi suficiente
3. **Frame descartado por block mismatch** (linha 640) — corrupção da sequência

**Implicação:** o sinal é **event-driven e esparso**. Rede perfeita ⇒ zero mensagens. Isso foi confirmado: primeira tentativa (LAN limpa) produziu 0 eventos; segunda tentativa (5% loss artificial) produziu 25 eventos em 60s.

---

## 2. IDX_LOSS_STATS (0x0201) — NÃO USAR

O handler atual em `stream.cpp:935-948` loga dados que **nunca serão reais** porque:
- Moonlight→Sunshine nunca ativa o path legado
- No path legado, `stats[0]` (loss count) é hardcoded 0
- `stats[2]` é a constante `1000`, não total de pacotes

**Recomendação:** deixar o handler existente intocado (para compatibilidade com outros clientes GameStream legado), mas **não é o ponto de hook do PR #1**.

---

## 3. IDX_REQUEST_IDR_FRAME (0x0302) — stream.cpp:951

```cpp
server->map(packetTypes[IDX_REQUEST_IDR_FRAME], [&](session_t *session, const std::string_view &payload) {
  BOOST_LOG(debug) << "type [IDX_REQUEST_IDR_FRAME]"sv;
  session->video.idr_events->raise(true);
});
```

Funciona em ambos os protocolos. O PR #1 pode contar a frequência dessas mensagens como sinal secundário (indica que o FEC recovery falhou e o cliente precisou de um keyframe completo).

---

## 4. Contexto disponível no handler

Todos os campos seguintes estão acessíveis dentro de um handler via `session`:

| Item | Acesso | Fonte |
|------|--------|-------|
| Bitrate configurado | `session->config.monitor.bitrate` | negociado no RTSP (rtsp.cpp:993-1070) |
| Session ID | `session->launch_session_id` | stream.cpp:407 |
| Timestamp | `std::chrono::steady_clock::now()` | monotônico |

Bandwidth estimada **não existe server-side** (ver decisão em `02-csv-schema.md`).

---

## 5. Thread do handler

Handlers de `controlBroadcastThread` (stream.cpp:922) rodam na **thread de controle**, separada das threads de vídeo e áudio. I/O nessa thread (ex: escrita do CSV) não afeta latência de encoding.

---

## 6. Implicações para o PR #1

### Mudança de escopo

A proposta original previa hook no `IDX_LOSS_STATS`. O PR #1 vai precisar:

1. **Adicionar novo handler** para `SS_FRAME_FEC_STATUS` (0x5502) em `stream.cpp`
2. **Definir uma constante** `IDX_FRAME_FEC_STATUS = 16` (próximo índice livre) e packet type correspondente
3. **Replicar a struct** `SS_FRAME_FEC_STATUS` do Moonlight no Sunshine (header novo ou inline)
4. **Parsear os 21 bytes** com atenção ao endianness (Moonlight envia big-endian: `BE32/BE16`)
5. **Exportar para CSV** os campos relevantes a cada evento recebido

### Schema do CSV (revisado)

As colunas agora derivam da struct real. Será detalhado em `02-csv-schema.md`:

```
timestamp_ms, session_id, bitrate_kbps, frame_index,
missing_packets, total_data_packets, received_data_packets,
total_parity_packets, received_parity_packets, fec_percentage
```

### Valor para a comunidade

Este PR resolve um gap real do Sunshine: **a plataforma recebe o sinal mais rico do protocolo (status FEC por frame) e descarta**. Expor isso via CSV é útil mesmo sem o controlador do PR #2 — ajuda qualquer desenvolvedor/usuário a diagnosticar problemas de rede.

---

## Próximo passo

Revisar `02-csv-schema.md` para refletir os campos do `SS_FRAME_FEC_STATUS` e remover os campos do path legado.
