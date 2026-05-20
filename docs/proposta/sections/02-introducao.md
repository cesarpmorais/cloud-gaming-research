## 1. Introdução

### 1.1 Contextualização

O *cloud gaming* — modalidade em que o processamento gráfico de jogos é executado em um servidor remoto e transmitido em tempo real para o dispositivo do jogador — deixou de ser uma promessa e se tornou realidade comercial. Serviços como NVIDIA GeForce Now, Microsoft xCloud e PlayStation Plus permitem que usuários joguem títulos de alta exigência em dispositivos modestos, eliminando a necessidade de hardware dedicado. O mercado global de cloud gaming foi avaliado em aproximadamente US$ 14 bilhões em 2026 e projeta crescimento contínuo na próxima década.

No entanto, esses serviços apresentam limitações estruturais relevantes: são centralizados, pagos por assinatura e sujeitos a descontinuação unilateral. O encerramento abrupto do Google Stadia em 2023 ilustrou essa fragilidade, deixando usuários sem acesso a conteúdo pelo qual haviam pago. A dependência de infraestrutura proprietária levanta questões sobre propriedade, privacidade e continuidade do acesso.

Essa fragilidade impulsionou um movimento alternativo: jogadores com hardware potente passaram a hospedar seus próprios servidores de streaming, transmitindo jogos para outros dispositivos dentro de casa ou via internet, sem depender de terceiros. O **Sunshine** é o principal servidor de cloud gaming open source em atividade. Compatível com o protocolo NVIDIA GameStream e com o cliente **Moonlight** — disponível em Android, iOS, PC e smart TVs —, o projeto conta com centenas de contribuidores ativos e é amplamente utilizado pela comunidade de self-hosting. Uma contribuição técnica ao Sunshine beneficia diretamente usuários reais e, se aceita pelos mantenedores, vai a produção.

### 1.2 Trabalho Desenvolvido Anteriormente

Este projeto tem como ponto de partida a pesquisa desenvolvida no POC I, cujo tema era a **detecção de ataques de False Data Injection (FDI) em pelotões veiculares usando Reinforcement Learning**. O trabalho anterior estabeleceu um ambiente de simulação completo utilizando Plexe, SUMO e OMNeT++ para modelagem realística de pelotões veiculares; implementação controlada de ataques FDI via modificações no código-fonte do framework; geração de dataset balanceado com aproximadamente 9.000 amostras contendo cenários com e sem ataques; e um modelo de detecção baseado em PPO (*Proximal Policy Optimization*) treinado offline.

Os resultados preliminares, embora demonstrem a viabilidade da abordagem, revelaram limitações significativas: **acurácia de 52,6%, sensibilidade de 69,1% e especificidade de apenas 35,6%**. Esses indicadores são insuficientes para aplicações práticas em sistemas de segurança veicular, onde falhas na detecção podem ter consequências críticas. Mais importante, a análise dos resultados não apontou hipótese clara de melhoria: a especificidade baixa sugeria uma limitação estrutural da abordagem no domínio — não apenas de hiperparâmetros — sem direção promissora para um POC II no mesmo tema. Os objetivos originais do POC II (implementação robusta das abordagens selecionadas e validação experimental) foram, portanto, descartados junto com o tema.

Durante a exploração de projetos open source ativos como alternativa, identificou-se uma oportunidade técnica concreta no Sunshine: a ausência de controle adaptativo de bitrate no servidor, problema com impacto direto na qualidade de experiência dos usuários e lacuna não coberta pela literatura existente.

### 1.3 O Problema a ser Investigado

O **bitrate de codificação** — quantidade de bits por segundo utilizada para comprimir cada frame — é o principal parâmetro de qualidade em cloud gaming. Bitrates mais altos produzem imagens mais fiéis; bitrates mais baixos introduzem artefatos visuais como blocagem e desfoque.

O Sunshine negocia o bitrate uma única vez, durante o handshake inicial da sessão (protocolo RTSP), e mantém esse valor **fixo durante toda a transmissão**, independentemente das condições da rede. Em redes instáveis — Wi-Fi, conexões com perda de pacotes, ou internet residencial sob carga —, o encoder continua transmitindo no bitrate máximo negociado. Quando a perda de pacotes excede a capacidade de recuperação da correção de erros (FEC), a tela do jogador congela. O cliente solicita um frame de recuperação (IDR); o servidor o produz, mas não reduz o bitrate. O ciclo se repete indefinidamente.

O Sunshine já recebe sinais contínuos de degradação do cliente — contagem de pacotes perdidos e solicitações de recuperação — mas nenhum é utilizado para ajustar o bitrate. **A infraestrutura de feedback já existe; o controlador não.** O detalhamento técnico deste mecanismo é apresentado na seção 2.2.

Este trabalho investiga duas perguntas em sequência. A **pergunta principal**: um controlador ABR server-side, operando sobre sinais observáveis pelo servidor sem sincronização de relógio com o cliente, produz métricas de estabilidade melhores do que o comportamento fixo atual? A **pergunta exploratória**: é possível ir além do estado da arte explorando sinais exclusivos do posicionamento server-side — como a taxa de variação da perda de pacotes ou o intervalo de chegada das mensagens de controle — em comparação com abordagens client-side como o ABRAGame?

### 1.4 Objetivos

**Objetivo Geral:** projetar, implementar e avaliar empiricamente um controlador adaptativo de bitrate server-side para o Sunshine, contribuído ao repositório oficial do projeto por meio de Pull Requests.

**Objetivos Específicos:**

- Instrumentar o Sunshine com exportação estruturada de métricas de sessão para arquivo CSV, provendo infraestrutura de observabilidade atualmente inexistente na plataforma (PR #1);
- Configurar um testbed de emulação de rede via `tc netem` replicando cenários reais de degradação, e coletar dados de baseline do comportamento atual do Sunshine sob cada cenário;
- Engajar os mantenedores do repositório oficial por meio de issue pública, apresentando o problema, os dados do baseline e o esboço do algoritmo antes da implementação;
- Implementar um controlador adaptativo de bitrate (PR #2), avaliá-lo comparativamente ao baseline de bitrate fixo, e documentar os resultados independentemente do desfecho.
