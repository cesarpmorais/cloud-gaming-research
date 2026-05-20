# Proposta de TCC — Controle Adaptativo de Bitrate em Servidor de Streaming de Jogos Open Source

**Aluno:** César Morais\
**Curso:** Ciência da Computação — UFMG\
**Entrega prevista:** 29 de junho de 2026

---

## 1. Contextualização

O streaming de jogos deixou de ser uma promessa e se tornou realidade comercial. Serviços como NVIDIA GeForce Now, Microsoft xCloud e PlayStation Now permitem que usuários joguem títulos de alta exigência em dispositivos modestos, transmitindo o processamento gráfico de servidores remotos para o dispositivo do jogador em tempo real. O mercado global de cloud gaming foi avaliado em aproximadamente US$ 14 bilhões em 2026 e projeta crescimento contínuo na próxima década.

No entanto, esses serviços apresentam limitações estruturais: são centralizados, pagos por assinatura e sujeitos a descontinuação unilateral — como demonstrou o encerramento do Google Stadia em 2023, deixando milhares de usuários sem acesso a conteúdo pelo qual haviam pago. A dependência de infraestrutura proprietária levanta questões relevantes sobre propriedade, privacidade e continuidade do acesso.

Essa fragilidade impulsionou um movimento alternativo: jogadores com PCs potentes passaram a hospedar seus próprios servidores de streaming, transmitindo jogos para outros dispositivos da própria casa ou via internet, sem depender de terceiros. O **Sunshine** é o principal servidor de streaming de jogos open source em atividade. Compatível com o protocolo NVIDIA GameStream e com o cliente Moonlight — disponível em Android, iOS, PC e smart TVs —, o projeto conta com contribuições ativas de centenas de desenvolvedores e é amplamente utilizado pela comunidade. Ele representa, na prática, a principal infraestrutura técnica do streaming descentralizado de jogos.

---

## 2. O Problema Técnico

O Sunshine opera um pipeline de três estágios: **captura** (leitura dos frames do display), **codificação** (compressão via GPU, tipicamente NVENC da NVIDIA ou VAAPI) e **transmissão** (envio ao cliente via UDP com correção de erros por FEC — Forward Error Correction).

O **bitrate de codificação** — quantidade de bits por segundo enviada ao cliente — é o principal parâmetro de qualidade da transmissão. Ele determina o nível de compressão aplicado a cada frame: bitrates mais altos resultam em imagem mais fiel ao original; bitrates mais baixos introduzem artefatos visuais como blocagem e desfoque.

### O modelo estático atual

O Sunshine negocia o bitrate uma única vez, durante o handshake inicial da sessão (protocolo RTSP), e mantém esse valor **fixo durante toda a transmissão**, independentemente do que acontece na rede. O ajuste é feito em três etapas: (1) o cliente declara sua largura de banda máxima disponível; (2) o servidor subtrai a sobrecarga do FEC, do áudio e dos cabeçalhos de protocolo; (3) o resultado é passado ao encoder e nunca mais modificado.

### As consequências práticas

Em redes instáveis — Wi-Fi, conexões com perda de pacotes, ou internet residencial sob carga —, o encoder continua transmitindo no bitrate máximo negociado. Quando pacotes são perdidos em quantidade superior à capacidade de recuperação do FEC, o decoder do cliente falha e a tela congela. O cliente, então, envia ao servidor uma requisição de **IDR frame** (Instantaneous Decoder Refresh — um frame de recuperação que reinicia o estado do decoder), sinalizando falha. O servidor produz o IDR frame, mas não reduz o bitrate. Em condições de rede persistentemente ruins, o ciclo se repete indefinidamente.

Estudos em plataformas comerciais como Stadia e PlayStation Now registraram tempos de recuperação de 20 a 200 segundos após eventos de degradação de rede (ARMENDARIZ; JOSKOWICZ, 2025). Pesquisas sobre percepção de qualidade em game streaming identificam 100ms como limiar de tolerância à latência para jogos de ação, e latências acima de 70ms de RTT como prejudiciais à jogabilidade em gêneros competitivos (BALDOVINO, 2022).

### A oportunidade ignorada

O Sunshine já recebe, continuamente, sinais de degradação enviados pelo cliente:

- `IDX_LOSS_STATS`: contagem de pacotes perdidos e intervalo de tempo desde o último reporte
- `IDX_REQUEST_IDR_FRAME`: solicitação de frame de recuperação, indicando falha de decodificação

Ambos os sinais chegam ao servidor via canal de controle (`src/stream.cpp`) e são registrados em log. Nenhum deles é utilizado para ajuste de bitrate. **A infraestrutura de feedback já existe; o controlador não.**

---

## 3. Trabalhos Relacionados e Lacuna Identificada

### 3.1 ABR em streaming de vídeo sob demanda

O controle adaptativo de bitrate (ABR) é amplamente estudado no contexto de streaming de vídeo sob demanda (VoD). Algoritmos como BOLA, Pensieve e MPC foram desenvolvidos para plataformas como DASH e HLS e atingiram alto grau de maturidade. No entanto, esses algoritmos assumem premissas fundamentalmente incompatíveis com o streaming de jogos interativo:

- **Buffering:** plataformas VoD pré-carregam segmentos futuros, tolerando variações de rede sem impacto perceptível. Em game streaming, cada frame deve ser exibido imediatamente — não há buffer de reprodução sem introduzir latência inaceitável.
- **Lookahead:** algoritmos VoD observam o comportamento da rede por vários segundos antes de decidir o próximo bitrate. Em game streaming, o frame seguinte ainda não existe no momento da decisão — é gerado em resposta à ação do jogador.
- **Retransmissão:** perdas em VoD podem ser recuperadas por retransmissão TCP. Game streaming usa UDP para minimizar latência — pacotes perdidos são irrecuperáveis via retransmissão.

Além dessas incompatibilidades, há uma diferença estrutural mais profunda: plataformas VoD mantêm uma *bitrate ladder* — o mesmo conteúdo pré-codificado em múltiplas qualidades antes de qualquer transmissão, permitindo que o servidor simplesmente selecione o arquivo adequado. Em game streaming, o conteúdo não existe até o jogador agir: é impossível pré-codificar frames que dependem de input em tempo real. O servidor dispõe de uma janela de ~16ms (a 60fps) para capturar, codificar e enfileirar cada frame. Isso força o uso de presets de codificação otimizados para velocidade (não qualidade), e torna inviável qualquer análise preditiva de complexidade de cena — uma explosão de partículas e um menu quieto chegam ao encoder na mesma janela, sem aviso prévio.

Os requisitos de latência reforçam essa restrição. Em VoD, buffers de reprodução de 10–30 segundos são invisíveis ao usuário e absorvem variações de rede sem impacto perceptível. Em game streaming, cada milissegundo de buffer adicionado é um milissegundo de latência entre o input do jogador e a resposta visual — inaceitável em jogos competitivos com limiar de tolerância de 50–100ms de RTT (BALDOVINO, 2022). O resultado é que algoritmos ABR projetados para VoD operam em uma escala de tempo e com um grau de liberdade que simplesmente não existe no domínio de game streaming.

Essas diferenças tornam a literatura de VoD diretamente inaplicável ao problema de game streaming.

### 3.2 ABR específico para game streaming

No espaço de game streaming interativo, a literatura é significativamente mais escassa. Uma revisão sistemática conduzida por Baldovino (2022) identificou apenas 33 trabalhos relevantes publicados entre 2017 e 2022 em bases como IEEE Xplore e ACM — número modesto para um problema de crescente importância. Uma busca complementar conduzida neste trabalho em IEEE Xplore, ACM Digital Library e arXiv com os termos *"adaptive bitrate game streaming"*, *"server-side ABR cloud gaming"* e *"reinforcement learning bitrate game streaming"*, filtrando publicações de 2023 a 2025, confirmou que a área permanece pouco explorada.

Os trabalhos mais relevantes encontrados são:

**Hong et al. (2021)** propuseram uma plataforma open source de cloud gaming com suporte a adaptação de bitrate, demonstrando a viabilidade técnica do problema em ambiente controlado. O trabalho, no entanto, não se aprofunda no design do controlador nem avalia seu comportamento em cenários de degradação sistemática de rede.

**Baldovino (2022)**, em sua revisão sistemática, identificou abordagens promissoras como o **Themis** — controlador baseado em aprendizado por reforço para particionamento de recursos em game streaming que reduziu o atraso de resposta em 17–36% — e o **DeepGame** — sistema de codificação baseado em visão computacional. Ambos demonstram o potencial de técnicas adaptativas, mas operam em contextos de infraestrutura de data center, distantes do cenário de self-hosting que o Sunshine representa.

**ABRAGame** (Armendariz & Joskowicz, 2025) é o trabalho mais próximo do aqui proposto. Implementa um controlador rule-based inteiramente client-side, sem modificações no servidor. O algoritmo acumula latência de rede em uma janela deslizante de 500ms; se a latência acumulada supera o limiar de 2000 (equivalente a ~80ms sustentados), o bitrate é reduzido para `estBW − 1,5 Mbps`. A recuperação é linear: `+0,5 Mbps` a cada 20 segundos de estabilidade. O sistema foi testado em uma plataforma proprietária (ABYA Go) com emulação de rede via NetEm, em 6 cenários distintos de degradação. Resultados: 100% de detecção de degradações, 10,3% de falsos positivos, 85,9% de cancelamento efetivo de frame loss, tempo médio de recuperação de 4,5 segundos.

### 3.3 Controle de congestionamento em tempo real: WebRTC e GCC

Uma referência industrial diretamente relevante é o **WebRTC** (Web Real-Time Communication), padrão aberto para comunicação em tempo real utilizado em Google Meet, Discord e WhatsApp Web. O WebRTC transmite áudio e vídeo via UDP sem buffering e sem retransmissão — o mesmo modelo do game streaming. Seu algoritmo de controle de taxa, o **GCC** (Google Congestion Control), resolve exatamente o problema aqui proposto: ajuste de bitrate em tempo real sobre UDP, sem lookahead.

O GCC combina dois sinais complementares:
- **Perda de pacotes** — reativo: detecta congestionamento depois que já ocorreu
- **Gradiente de delay** — preditivo: detecta aumento na variação do delay de entrega *antes* que pacotes sejam perdidos

Essa combinação é o que torna o GCC eficaz em redes instáveis. O gradiente de delay é análogo à latência acumulada do ABRAGame — ambos capturam o crescimento da fila de pacotes antes que o overflow provoque descarte. A diferença é que o gradiente de delay não requer sincronização de relógio absoluta entre cliente e servidor: utiliza apenas a variação relativa do delay observada pelo receptor.

O GCC é relevante para este trabalho em dois sentidos: (1) como referência de design para o sinal de congestionamento — a combinação perda + gradiente de delay é uma abordagem comprovada em produção; (2) como motivação para a questão de pesquisa em aberto descrita na seção 4.5.

### 3.4 A lacuna identificada

A busca bibliográfica não encontrou **nenhum trabalho que implemente controle adaptativo de bitrate server-side em uma plataforma open source de game streaming**. ABRAGame, o trabalho mais recente e tecnicamente mais próximo, é client-side, requer sincronização de relógio entre cliente e servidor para medir latência de via única, e opera em plataforma proprietária não reproduzível pela comunidade. O GCC, embora resolva o problema de controle de taxa em tempo real, não foi projetado para o contexto de game streaming e não foi avaliado nesse cenário.

A lacuna é real e justificada: não se trata de território inexplorado por descuido, mas de um problema que combina restrições técnicas severas — operação server-side sem sincronização de relógio, sem lookahead, em plataforma open source com contribuidores independentes — com uma demanda prática crescente da comunidade de self-hosting.

---

## 4. Proposta

Este trabalho propõe o projeto, implementação e avaliação empírica de um **controlador adaptativo de bitrate server-side** para o Sunshine, contribuído diretamente ao repositório open source do projeto por meio de dois Pull Requests.

### 4.1 Pergunta de pesquisa

> "Um controlador adaptativo de bitrate server-side, operando sobre sinais observáveis pelo servidor, reduz a degradação do streaming em condições de rede variáveis comparado ao comportamento fixo atual do Sunshine, sem penalizar significativamente a experiência em redes estáveis?"

### 4.2 Questões de avaliação

Este trabalho avalia duas perguntas em sequência:

**Pergunta 1:** um controlador ABR server-side, inspirado no ABRAGame mas operando sem sincronização de relógio, produz métricas de estabilidade melhores do que o comportamento fixo atual do Sunshine? A expectativa é que sim — mas os sinais disponíveis server-side são predominantemente reativos, e uma melhora significativa não está garantida.

**Pergunta 2:** é possível ir além do ABRAGame explorando o que o posicionamento server-side oferece exclusivamente — acesso direto ao encoder, bitrate efetivamente produzido, e métricas internas de codificação? Uma segunda variante do controlador, cujo design será especificado após a análise do baseline, investigará se esses sinais adicionais produzem ganho sobre a variante inspirada no ABRAGame.

### 4.3 Entregáveis

**PR #1 — Exportação de estatísticas de sessão**
Exportação de métricas de streaming para arquivo CSV: taxa de IDR requests, contagem de pacotes perdidos, bitrate atual, largura de banda estimada e timestamp. Esta infraestrutura de instrumentação é pré-requisito para todos os passos subsequentes e tem valor independente para a comunidade — atualmente não há forma estruturada de inspecionar o comportamento de uma sessão Sunshine.

**PR #2 — Controlador adaptativo de bitrate (modo opcional)**
Implementação de um novo modo de controle de bitrate no Sunshine, ativável via configuração (`bitrate_mode = adaptive` em `sunshine.conf` e na interface Web). O controlador opera inteiramente server-side, utilizando sinais já disponíveis no canal de controle, e reconfigura o encoder NVENC em tempo real via `NvEncReconfigureEncoder()` sem interrupção da sessão.

### 4.4 Design do algoritmo

O algoritmo é inspirado em ABRAGame, adaptado para operação server-side sem sincronização de relógio. O sinal de congestionamento é construído a partir de métricas observáveis pelo servidor:

```
// Executa a cada intervalo de reporte do IDX_LOSS_STATS

sinal = f(taxa_perda_pacotes, taxa_IDR_requests) sobre janela deslizante

se sinal > limiar_congestionamento:
    novo_bitrate = estBW − margem          // redução agressiva
    novo_bitrate = max(novo_bitrate, BITRATE_MINIMO)
    reinicia timer_estabilidade

senão se timer_estabilidade >= 20s:
    novo_bitrate = bitrate_atual + passo   // aumento conservador
    novo_bitrate = min(novo_bitrate, BITRATE_MAXIMO)
    reinicia timer_estabilidade

encoder.reconfigurar(novo_bitrate)         // NvEncReconfigureEncoder()
```

Parâmetros a calibrar com dados do baseline: `margem`, `passo`, `limiar_congestionamento`. Ponto de partida: valores do ABRAGame (1,5 Mbps / 0,5 Mbps / equivalente a 80ms).

Uma variante com **aumento exponencial** (em lugar de linear) será avaliada — melhoria identificada como trabalho futuro pelos próprios autores do ABRAGame.

**Segunda variante: exploração de sinais exclusivamente server-side**

O posicionamento server-side oferece acesso a métricas que um controlador client-side como o ABRAGame não pode observar: o bitrate efetivamente produzido pelo encoder (não apenas o alvo configurado), parâmetros internos de quantização (QP), e a diferença entre bitrate alvo e bitrate entregue como estimativa de saturação de banda. Esses sinais podem ter poder preditivo superior à taxa de perda pontual — capturam degradação *antes* que pacotes sejam descartados em quantidade suficiente para gerar IDR requests.

O design exato desta segunda variante será especificado após a coleta e análise do baseline (Passo 3). A razão é metodológica: os dados do baseline revelarão quais sinais variam de forma mais informativa antes, durante e após eventos de degradação — e essa evidência deve guiar a escolha do sinal, não premissas a priori. Se o baseline mostrar que o bitrate efetivo diverge do alvo antes da ocorrência de IDR requests, esse gap será o sinal primário. Se os sinais server-side adicionais não mostrarem poder preditivo distinto da taxa de perda, a primeira variante (ABRAGame-inspired) será o único controlador avaliado, e esse resultado informará as limitações do design server-side.

**Diferença central em relação ao ABRAGame:** ABRAGame usa latência de via única (requer sincronização de relógio). Esta implementação usa taxa de perda de pacotes e taxa de IDR requests — ambos disponíveis server-side sem sincronização. O desafio de encontrar um sinal server-observable suficientemente preditivo é o problema de pesquisa central do trabalho.

### 4.5 Questão em aberto: sinal reativo vs preditivo

Esta é a principal incerteza técnica do projeto e merece registro explícito.

O sinal primário candidato — taxa de IDR requests — é **reativo**: uma requisição de IDR chega ao servidor *depois* que o decoder do cliente já falhou, ou seja, depois que frame loss já ocorreu. ABRAGame usa latência acumulada, que é **preditivo**: sobe enquanto pacotes ainda chegam, mas com atraso crescente, antes do overflow que causa descarte.

A questão é: sinais server-side disponíveis no Sunshine (perda de pacotes via `IDX_LOSS_STATS`, taxa de IDR requests) são suficientemente preditivos para *evitar* frame loss, ou apenas para *reagir* a ele?

O GCC endereça esse problema combinando perda de pacotes (reativo) com gradiente de delay (preditivo). Uma direção possível para este trabalho é investigar se uma métrica análoga ao gradiente de delay pode ser construída server-side a partir da variação no intervalo de chegada das mensagens de controle do cliente — sem sincronização de relógio absoluta. Essa investigação, condicionada aos dados coletados no Passo 1, pode refinar o design do controlador durante a implementação.

---

## 5. Metodologia

### Passo 1 — Exportação de estatísticas (PR #1)
Instrumentar `src/stream.cpp` para exportar métricas de sessão para CSV. Medir empiricamente a frequência de reporte do `IDX_LOSS_STATS` — esse valor determina a resolução temporal da janela deslizante do controlador.

### Passo 2 — Configuração do testbed
Configurar emulação de rede via `tc netem` no host Linux, replicando os 6 cenários de degradação de ABRAGame:

| Cenário | Descrição |
|---------|-----------|
| A | Queda abrupta + recuperação rápida |
| B | Queda gradual + recuperação rápida |
| C | Queda lenta + recuperação rápida |
| D | Flutuações intermitentes |
| E | Queda longa + recuperação abrupta |
| F | Início baixo + melhora tardia |

Duração: 240 segundos por cenário. Cliente: Moonlight Android (smartphone). Servidor: PC com NVIDIA RTX 4070 Super, Fedora Linux, captura via X11.

### Passo 3 — Coleta do baseline
Executar o Sunshine com bitrate fixo em todos os 6 cenários. Coletar CSVs. Quantificar o comportamento atual — esses dados embasarão o argumento da issue e serão o ponto de comparação final.

### Passo 4 — Abertura de issue no GitHub do Sunshine
Abrir issue de discussão no repositório oficial com: descrição do problema, dados coletados no Passo 3, esboço do algoritmo, e perguntas sobre preferências arquiteturais dos mantenedores. Objetivo: validar a abordagem antes de escrever código, coletar feedback e estabelecer registro público da proposta.

### Passo 5 — Implementação e avaliação (PR #2)
Implementar o controlador com parâmetros calibrados a partir dos dados do Passo 3 e do feedback da issue. Executar o mesmo protocolo de testes dos Passos 2–3. Comparar resultados contra o baseline.

### Métricas de avaliação

| Métrica | Descrição | Referência (ABRAGame) |
|---------|-----------|----------------------|
| Taxa de cancelamento de frame loss | % de eventos de degradação evitados | 85,9% |
| Tempo de recuperação | Segundos até retorno ao bitrate nominal | 4,5s |
| Taxa de falsos positivos | Reduções desnecessárias em rede estável | 10,3% |
| Variância do bitrate | Estabilidade do controlador | — |
| Taxa de IDR requests | Proxy de falhas de decodificação | — |

### Plano de análise estatística

O plano de análise estatística será definido após a coleta do baseline (Passo 3), quando a natureza e distribuição dos dados coletados estiverem claras. A metodologia incluirá repetições por cenário, testes de hipótese adequados ao perfil dos dados, e definição de tamanho de efeito mínimo para distinguir melhora prática de ruído estatístico.

---

## 6. Resultados Esperados e Critérios de Sucesso

**Quanto à Pergunta 1**, a expectativa é que o controlador ABRAGame-inspired produza redução consistente na taxa de frame loss e no tempo de recuperação nos cenários de degradação, com taxa de falsos positivos aceitável em redes estáveis. Os critérios quantitativos serão definidos após a coleta do baseline — os dados do comportamento atual do Sunshine informarão o que constitui melhora prática relevante. ABRAGame serve como referência de calibração, reconhecendo que a operação server-side impõe restrições adicionais nos sinais disponíveis.

Não se pode descartar que os sinais server-side disponíveis sejam insuficientemente preditivos para antecipar congestionamento antes que frame loss ocorra. Esse resultado seria, em si, uma contribuição: delimitaria as possibilidades do design server-side sem sincronização de relógio e motivaria trabalho futuro.

**Quanto à Pergunta 2**, o resultado depende do que os dados do baseline revelarem. Se os sinais exclusivamente server-side (bitrate efetivo, gap de quantização) mostrarem poder preditivo distinto, uma segunda variante será implementada e comparada. Caso contrário, o trabalho contribuirá com a delimitação empírica do que é observável server-side — resultado igualmente válido para a comunidade.

---

## 7. Riscos e Mitigações

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| PR rejeitado pelos mantenedores do Sunshine | Média | Abertura prévia de issue (Passo 4) para alinhar expectativas; o código permanece publicado no fork mesmo sem merge |
| `IDX_LOSS_STATS` com frequência de reporte insuficiente para janela deslizante de 500ms | Média | Medição empírica no Passo 1; ajuste da janela conforme necessário |
| Sinais server-side insuficientemente preditivos (H0 não rejeitada) | Média | Resultado negativo documentado e analisado; contribuição metodológica permanece válida |
| `NvEncReconfigureEncoder()` com comportamento inesperado em CBR | Baixa | Confirmado em documentação NVIDIA; fallback: reinicialização completa do encoder como modo degradado |
| Atraso no testbed comprometer cronograma | Baixa | Testbed é configurável no mesmo host do Sunshine; não requer hardware adicional |

---

## 8. Contribuições

**Contribuição científica:** primeira implementação e avaliação empírica de controlador ABR server-side em plataforma open source de game streaming. Estende ABRAGame — o estado da arte — para o lado do servidor, elimina a necessidade de sincronização de relógio entre cliente e servidor, e contribui metodologia reproduzível (código aberto, testbed documentado) para a comunidade acadêmica.

**Contribuição para a comunidade open source:** os dois PRs serão submetidos ao repositório oficial do Sunshine. Se aceitos, beneficiarão diretamente todos os usuários da plataforma — em particular em cenários de Wi-Fi e streaming via internet, onde instabilidade de rede é a norma. O PR #1 (exportação de estatísticas) tem valor independente como ferramenta de diagnóstico.

**Contribuição formativa:** contribuição real a projeto open source ativo em C++17, com revisão por pares por engenheiros da comunidade, aplicação de conceitos de sistemas, redes e controle, e experiência com o ciclo completo de desenvolvimento — problema → implementação → avaliação → publicação.

---

## 9. Cronograma

| Período | Atividades |
|---------|-----------|
| **Abril 2026** | Revisão bibliográfica complementar; implementação do PR #1 (CSV export); configuração do testbed; coleta e análise do baseline |
| **Maio 2026** | Abertura da issue no GitHub; implementação do controlador adaptativo; calibração de parâmetros; testes comparativos; iteração com mantenedores |
| **Junho 2026** | Análise dos resultados; escrita do TCC; revisão; ajustes finais; entrega em 29/06/2026 |

---

## Referências

ARMENDARIZ, M.; JOSKOWICZ, J. **ABRAGame: Automatic Bit Rate Adjustment for Cloud Gaming**. Multimedia Tools and Applications, Springer, 2025. DOI: 10.1007/s11042-024-20506-2. Disponível em: https://link.springer.com/article/10.1007/s11042-024-20506-2.

BALDOVINO, Britanny. **An Overview of the Networking Issues of Cloud Gaming: A Literature Review**. JINITA, Baguio City, Philippines, 2022. Disponível em: https://ejournal.pnc.ac.id/index.php/jinita/article/view/1581/473.

HONG, Hua-Jun et al. **Enabling Adaptive Cloud Gaming in an Open-Source Cloud Gaming Platform**. IEEE, 2021. Disponível em: https://ieeexplore.ieee.org/abstract/document/7137667.

https://www.coherentmarketinsights.com/market-insight/cloud-gaming-market-4600