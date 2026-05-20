# Organização da Proposta POC 2 — Sunshine ABR

> Rascunho de estrutura. Baseado no estilo do POC 1 (LaTeX, seções numeradas, tabela de cronograma).
> O documento final será em LaTeX, ≤ 10 páginas.

---

## Capa

- **Título:** Controle Adaptativo de Bitrate Server-Side em Plataforma Open Source de Cloud Gaming
- **Tipo de Pesquisa:** Mista (tecnológica + científica)
- **Orientador:** Prof. Dr. Luiz Filipe Menezes Vieira
- **Aluno:** César de Paula Morais — Ciência da Computação, UFMG
- **Entrega prevista:** 29/06/2026
- *(sem coorientador)*

---

## 1. Introdução

### 1.1 Contextualização
*(era "Importância" — mas o conteúdo é contexto, não importância)*

- O que é cloud gaming, self-hosting, Sunshine como plataforma principal
- Mercado (US$14B, 2026), encerramento do Stadia, movimento de self-hosting
- Por que contribuir ao Sunshine: plataforma com usuários reais, contribuição vai a produção

### 1.2 Sumário do POC I e Decisão de Mudança de Tema
*(exigido pelo template para POC 2)*

- O que foi feito: ambiente de simulação (Plexe/SUMO/OMNeT++), dataset ~9k amostras, modelo PPO
- Resultados: acurácia 52,6%, sensibilidade 69,1%, **especificidade 35,6%**
- Por que mudou: resultados não apontaram caminho promissor; especificidade baixa sugeria limitação estrutural, sem hipótese clara para continuação
- Os objetivos originais do POC 2 (implementação robusta das abordagens selecionadas no POC 1, validação experimental) foram descartados junto com o tema
- Nova oportunidade identificada durante exploração de projetos open source ativos

### 1.3 O Problema a ser Investigado

- Sunshine: principal servidor de cloud gaming open source
- Modelo estático de bitrate: negociado uma vez no handshake RTSP, fixo para sempre
- Ciclo de degradação: rede piora → pacotes perdidos → IDR requests → bitrate não muda → ciclo se repete
- Sinais de feedback já chegam ao servidor; controlador não existe
- **Pergunta de pesquisa:** um controlador ABR server-side melhora a estabilidade em redes instáveis sem penalizar redes estáveis? Questão exploratória: sinais exclusivamente server-side (acesso ao encoder, bitrate efetivo) oferecem vantagem sobre a abordagem do ABRAGame?

### 1.4 Objetivos

**Objetivo Geral:** implementar e avaliar empiricamente um controlador adaptativo de bitrate server-side no Sunshine, contribuído ao repositório oficial via Pull Requests.

**Objetivos Específicos (POC 2):**
- Instrumentar Sunshine com exportação de métricas de sessão (PR #1)
- Configurar testbed de emulação de rede e coletar baseline de comportamento atual
- Engajar mantenedores do projeto via issue no GitHub antes da implementação
- Implementar controlador adaptativo (PR #2) e avaliar comparativamente ao baseline

---

## 2. Referencial Teórico

### 2.1 Cloud Gaming: Arquitetura e Restrições
Conceitos técnicos: pipeline captura → encode → transmissão, restrições de latência (<100ms RTT), UDP sem buffer, geração em tempo real (sem bitrate ladder)

### 2.2 Pipeline Técnico do Sunshine
Captura → codificação (NVENC/VAAPI) → transmissão UDP + FEC; onde e como o bitrate é negociado

### 2.3 ABR em Vídeo Sob Demanda — e por que é inaplicável
BOLA, Pensieve, DASH/HLS — bitrate ladder impossível, sem lookahead, sem buffer, latência, UDP vs TCP, geração em tempo real vs pré-codificado

### 2.4 Trabalhos Relacionados em Cloud Gaming
- Hong et al. (viabilidade técnica de ABR em cloud gaming)
- Baldovino (revisão sistemática — 33 trabalhos, literatura escassa)
- **ABRAGame** (mais próximo: client-side, 85,9% cancelamento, 4,5s recuperação — requer clock sync)
- **GCC/WebRTC** (referência industrial: controle de taxa em UDP, sinal reativo + preditivo)

### 2.5 Lacuna Identificada
Nenhum trabalho implementa ABR server-side em plataforma open source de cloud gaming.
*(estado da arte será aprofundado durante o POC 2)*

---

## 3. Metodologia

### 3.1 Abordagem Geral
5 passos sequenciais: PR#1 (instrumentação) → testbed → baseline → issue → PR#2 (controlador)

### 3.2 Passo 1 — Exportação de Métricas (PR #1)
Instrumentar `src/stream.cpp`; exportar IDR rate, packet loss, bitrate, timestamp para CSV

### 3.3 Passo 2 — Configuração do Testbed
`tc netem`, 6 cenários de degradação (replicando ABRAGame: queda abrupta, gradual, flutuações, etc.), 240s/cenário

### 3.4 Passo 3 — Coleta do Baseline
Sunshine com bitrate fixo em todos os cenários; os dados informam design do controlador e critérios de sucesso

### 3.5 Passo 4 — Issue no GitHub
Apresentar problema, dados do baseline e esboço do algoritmo aos mantenedores antes de implementar

### 3.6 Passo 5 — Implementação e Avaliação (PR #2)

**Design do algoritmo:**
Inspirado no ABRAGame, adaptado para server-side sem clock sync. Sinal primário: taxa de perda de pacotes + taxa de IDR requests. Redução agressiva ao detectar congestionamento; aumento conservador após período de estabilidade. Segunda variante (exploração de sinais exclusivamente server-side: bitrate efetivo vs. alvo, parâmetros do encoder) será especificada após análise do baseline.

**Métricas de avaliação:**
| Métrica | Descrição | Ref. ABRAGame |
|---------|-----------|---------------|
| Taxa de cancelamento de frame loss | % de eventos de degradação evitados | 85,9% |
| Tempo de recuperação | Segundos até retorno ao bitrate nominal | 4,5s |
| Taxa de falsos positivos | Reduções desnecessárias em rede estável | 10,3% |

### 3.7 Uso de Inteligência Artificial e Gestão de Conhecimento
*(análogo à seção 4.4 do POC 1, expandido)*

- **Claude Code (CLI):** assistente de pesquisa e desenvolvimento, com transparência sobre o que foi delegado vs. autoral
- **Base de conhecimento em Obsidian:** arquivos em `knowledge/` conectados por wikilinks, cobrindo arquitetura, protocolos, codecs e trabalhos relacionados
- **Grafo de conhecimento** como artefato metodológico — visualiza a topologia da pesquisa; incluir screenshot do Obsidian como figura no documento
- **Rastreamento de ideias:** `ideas/` com status progressivo (💡 raw → ✅ chosen), documentando seleção do tema

---

## 4. Resultados Esperados

- Dois PRs submetidos ao repositório oficial do Sunshine (aceitos ou em revisão pública)
- Comparação quantitativa: baseline fixo vs. controlador adaptativo nos 6 cenários
- Documentação metodológica: base de conhecimento + grafo Obsidian como registro do processo
- TCC entregue em 29/06/2026

*Resultado negativo (sinais server-side insuficientes) tem valor: delimita possibilidades do design server-side sem clock sync e motiva trabalho futuro.*

---

## 5. Etapas e Cronograma

| Semana | Período | Atividades |
|--------|---------|-----------|
| 0 (pré) | 13/03 – 10/04 | Desenvolvimento da proposta; revisão bibliográfica — **Entrega da proposta: 10/04** |
| 1–2 | 13/04 – 26/04 | PR #1: instrumentação e exportação de métricas (CSV) |
| 3–4 | 27/04 – 10/05 | Configuração do testbed; coleta e análise do baseline |
| 5 | 11/05 – 17/05 | Abertura de issue no GitHub; início da implementação do controlador |
| 6–7 | 18/05 – 24/05 | Implementação do controlador (PR #2); testes iniciais — **preparação do pitch** |
| — | **25/05** | **Apresentação parcial — Pitch Vídeo** |
| 8–9 | 26/05 – 14/06 | Testes comparativos; análise dos resultados; escrita do TCC |
| 10 | 15/06 – 21/06 | Finalização do TCC; preparação do pôster — **Entrega do pôster para impressão: 21/06** |
| 11 | 22/06 – 26/06 | Revisão final — **Apresentação do pôster: 26/06** |
| 12 | 27/06 – 29/06 | Ajustes finais — **Entrega do relatório final: 29/06** |
| — | **03/07** | **Entrega na plataforma DCC (POC II)** |

*(semanas de entrega a destacar em amarelo no LaTeX — igual ao POC 1)*

---

## 6. Referências Bibliográficas

- ARMENDARIZ; JOSKOWICZ. ABRAGame. Multimedia Tools and Applications, Springer, 2025.
- BALDOVINO. An Overview of the Networking Issues of Cloud Gaming. JINITA, 2022.
- HONG et al. Enabling Adaptive Cloud Gaming in an Open-Source Cloud Gaming Platform. IEEE, 2021.
- TODO: referência GCC — Carsten Holmer et al., "A Google Congestion Control Algorithm for Real-Time Communication", IETF Draft, 2016.
