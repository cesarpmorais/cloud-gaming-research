## 3. Metodologia

### 3.1 Abordagem Geral

A metodologia proposta é dividida em cinco passos sequenciais, onde cada etapa produz insumos necessários para a seguinte. O projeto parte da premissa de que **os dados do baseline devem guiar o design do controlador** — não premissas a priori — e que a validação com a comunidade deve preceder a implementação. Três questões norteiam cada decisão: o que é factível no escopo de um semestre? O que ainda não foi feito na literatura? O que tem impacto real para usuários da plataforma?

### 3.2 Passo 1 — Exportação de Métricas de Sessão (PR #1)

Instrumentar `src/stream.cpp` para exportar métricas de sessão para arquivo CSV a cada intervalo de reporte do `IDX_LOSS_STATS`. As métricas exportadas incluem: timestamp, bitrate configurado, contagem de pacotes perdidos, taxa de IDR requests e largura de banda estimada. Esta infraestrutura de observabilidade é pré-requisito para todos os passos subsequentes e tem valor independente para a comunidade — atualmente não há forma estruturada de inspecionar o comportamento de uma sessão Sunshine. A frequência de reporte do `IDX_LOSS_STATS` será medida empiricamente nesta etapa, pois determina a resolução temporal da janela deslizante do controlador.

### 3.3 Passo 2 — Configuração do Testbed

Configurar emulação de rede via `tc netem` no host Linux, replicando os 6 cenários de degradação utilizados pelo ABRAGame:

| Cenário | Descrição |
|---------|-----------|
| A | Queda abrupta + recuperação rápida |
| B | Queda gradual + recuperação rápida |
| C | Queda lenta + recuperação rápida |
| D | Flutuações intermitentes |
| E | Queda longa + recuperação abrupta |
| F | Início baixo + melhora tardia |

Duração: 240 segundos por cenário. Cliente: Moonlight Android (smartphone). Servidor: PC com NVIDIA RTX 4070 Super, Fedora Linux, captura via X11. A replicação dos cenários do ABRAGame permite comparação direta dos resultados com o trabalho de referência.

### 3.4 Passo 3 — Coleta do Baseline

Executar o Sunshine com bitrate fixo em todos os 6 cenários. Coletar os CSVs gerados pelo PR #1. Quantificar o comportamento atual da plataforma — esses dados cumprem dois papéis: (1) embasam o argumento da issue pública (Passo 4) com evidência empírica; (2) informam os critérios de sucesso do controlador, substituindo thresholds arbitrários por referências derivadas dos dados reais.

### 3.5 Passo 4 — Issue no GitHub do Sunshine

Abrir issue de discussão no repositório oficial do Sunshine apresentando: descrição do problema, dados coletados no Passo 3, esboço do algoritmo proposto e perguntas sobre preferências arquiteturais dos mantenedores. O objetivo é validar a abordagem antes de escrever código, coletar feedback técnico da comunidade e estabelecer registro público da proposta — práticas padrão de contribuição a projetos open source ativos.

### 3.6 Passo 5 — Implementação e Avaliação (PR #2)

**Design do algoritmo:** o controlador executa a cada mensagem `IDX_LOSS_STATS` recebida do cliente — o mesmo evento que hoje o Sunshine apenas loga. A cada execução, agrega taxa de perda de pacotes e taxa de requisições de IDR sobre uma janela deslizante, produzindo um sinal composto de congestionamento.

O controlador tem duas decisões possíveis. Se o sinal supera um limiar de congestionamento, o bitrate é reduzido agressivamente para a largura de banda estimada menos uma margem de segurança, respeitando um mínimo configurável — e um timer de estabilidade é reiniciado. Se o sinal está abaixo do limiar e o timer de estabilidade atingiu 20 segundos sem interrupção, o bitrate é incrementado conservadoramente por um passo fixo, respeitando um máximo configurável. Se nenhuma condição for satisfeita, o bitrate permanece inalterado. A reconfiguração do encoder é chamada apenas quando há mudança. Os parâmetros — margem de redução, passo de incremento, limiar de congestionamento e tamanho da janela deslizante — serão calibrados a partir dos dados do baseline. O controlador será ativável via configuração (`bitrate_mode = adaptive` em `sunshine.conf`), sem impacto para usuários que não o habilitarem.

Uma segunda variante será investigada após a análise do baseline, condicionada ao que os dados revelarem. A motivação para essa investigação é a tensão central do design: os sinais primários do controlador (taxa de perda de pacotes, requisições de IDR) são **reativos** — chegam ao servidor *depois* que o congestionamento já causou dano. O ABRAGame, por contraste, usa latência acumulada, que é **preditivo**: detecta a fila de pacotes enchendo *antes* do overflow. O GCC demonstrou que combinar um sinal reativo com um preditivo é o que torna um controlador robusto em redes instáveis. A questão de pesquisa não é apenas "o controlador melhora o baseline?" — é "sinais server-side são suficientemente preditivos para *evitar* frame loss, ou apenas para *reagir* a ele?" Um resultado negativo nessa frente seria, em si, uma contribuição para o controle preditivo em cloud gaming server-side.

**Métricas de avaliação:**

| Métrica | Descrição | Referência (ABRAGame) |
|---------|-----------|----------------------|
| Taxa de cancelamento de frame loss | % de eventos de degradação evitados | 85,9% |
| Tempo de recuperação | Segundos até retorno ao bitrate nominal | 4,5 s |
| Taxa de falsos positivos | Reduções desnecessárias em rede estável | 10,3% |
| Variância do bitrate | Estabilidade do controlador ao longo do tempo | — |

### 3.7 Riscos e Mitigações

Os principais riscos do projeto são de natureza técnica e acadêmica. No lado técnico, a frequência de reporte do `IDX_LOSS_STATS` pode ser insuficiente para a resolução temporal desejada — risco mitigado pela medição empírica no Passo 1, que permitirá ajustar a janela deslizante antes de qualquer implementação. No lado acadêmico, os sinais server-side disponíveis podem se mostrar insuficientemente preditivos para antecipar congestionamento antes que frame loss ocorra — resultado que, se confirmado, será documentado como contribuição: delimita o que é possível sem sincronização de relógio. Quanto à aceitação pela comunidade, a abertura prévia de issue (Passo 4) alinha expectativas com os mantenedores antes da implementação; independentemente de merge, o código permanecerá publicado no fork como contribuição reproduzível.

### 3.8 Uso de Inteligência Artificial e Gestão de Conhecimento

Este projeto adota uma metodologia de **documentação contínua assistida por IA**, com transparência explícita sobre o que foi delegado à ferramenta versus o que é de autoria própria.

O **Claude Code** (CLI da Anthropic) foi utilizado como assistente de pesquisa e desenvolvimento ao longo do projeto: análise de código-fonte do Sunshine, estruturação de documentos acadêmicos e suporte à implementação em C++. O desenvolvimento conceitual, as decisões de design e as conclusões são de autoria do pesquisador.

O conhecimento acumulado durante o projeto é organizado em uma **base de conhecimento em Obsidian** — ferramenta de notas com suporte a *wikilinks* e visualização em grafo. A base contém arquivos cobrindo arquitetura do Sunshine, protocolos de streaming, codecs, trabalhos relacionados e decisões de design, todos interconectados por referências bidirecionais. O **grafo de conhecimento** resultante — ilustrado na Figura 1 — funciona como artefato metodológico: registra a topologia da pesquisa e torna visível o caminho intelectual percorrido, não apenas o resultado final - e será atualizado no final do projeto.

[FIGURA 1: Grafo de conhecimento do projeto no Obsidian]

As ideias exploradas ao longo do projeto são rastreadas em um diretório dedicado, documentando o processo de seleção do tema e das abordagens adotadas.
