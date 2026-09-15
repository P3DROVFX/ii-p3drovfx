# Prioridades de recursos após as duas rodadas

**Revisão de 8 de setembro de 2026:** 31 cenários históricos + 15 novos, 6.034 amostras preservadas. A rodada 1 inclui um caso excluído da atribuição e outros pares interferidos; a rodada 2 também tem limitações. Não são 46 experimentos causais equivalentes. Esta revisão leu código e recalculou dados existentes, sem executar o shell.

O objetivo continua sendo aproximar o consumo do end-4. **O maior painel de RAM continua sendo o Calendário; a maior diferença encontrada ao remover uma subárvore está no editor de Notas; a maior anomalia de CPU está no modo de mídia.** A política de retenção afeta a família inteira, mas não resolve sozinha CPU e VRAM.

## 1. RAM: onde investigar primeiro

Incremento = PSS aberto menos controlador anterior. Uma diferença entre variantes não é heap exclusivo nem economia garantida de uma implementação funcional. Não somar os valores desta tabela.

| Prioridade | Alvo | Evidência mais útil | Investigação / possível solução |
|---|---|---|---|
| **Alta, transversal** | **Retenção da família** | Rodada 2: sem cache, −203,4 MiB antes de navegar; **−131,8 MiB no idle final e −135,3 MiB após GC**. | Separar pré-carregamento, retenção temporária e estado leve; limitar abas conservadas. Validar sequência correta, uso prolongado e latência. |
| **Alta, maior diferença por subárvore** | **Editor de Notas** | Remover `NotesDetail`: **−156,2 MiB absolutos / −151,1 MiB no incremento aberto**; −130,9 MiB absolutos após GC. | Decompor editor, ferramentas de IA e menus ocultos. O teste suprimiu funcionalidade e MPRIS diferiu; ganho de um editor funcional ainda não está medido. |
| **Alta, maior painel ocasional** | **Calendário** | Completo: **+328,4 MiB** na rodada 2 (+336,3 na 1). Remover lateral/pickers: **−52,6 MiB no incremento do processo**, −94,6 MiB absolutos na árvore. | Carga tardia funcional de lateral, fontes e pickers. Depois perfilar grade/dependências: ainda +275,8 MiB aberta e +231,9 MiB pós-GC sem essas peças. |
| **Alta, resultado contraditório** | **Barra vertical** | Referência +255,6 MiB na rodada 2 (+300,9 na 1). Layout único poupou 39,2 MiB, mas elevou CPU. Privacy off elevou a RAM total. | Perfil por widget e por dependência; um layout/observador compartilhado; adiar widgets explicitamente desabilitados. Confirmar regressão de CPU antes de adotar o protótipo. |
| **Alta, anomalia de política** | **Dashboard** | Sem cache: −91,2 MiB no controlador, porém **+50,0 MiB aberto / +48,7 MiB após GC** frente ao cache ligado. | Repetir inicialização alternada e decompor cards/modelos. Não contar a economia de boot como economia depois do uso. |
| **Seguinte** | **IA, Phone e Overview** | IA sem cache termina +142,0 MiB sobre controlador. Rodada 1: Phone +163,8 MiB aberto e Overview +175,7 MiB. | Decompor conteúdo interno e singletons. Phone não foi validamente visitado na navegação nova; Overview não teve novo A/B. |

Notas passa à frente na investigação **de subcomponentes**, mas remover o editor inteiro não é uma otimização pronta. O Calendário continua relevante porque a maior parte do seu custo permanece mesmo com lateral e seletores removidos. A lista histórica completa está no [ranking da rodada 1](ranking-recursos.json); os números novos estão separados em [round2/summary.json](round2/summary.json).

## 2. CPU: custos contínuos e condições de pico

Percentuais são de **um núcleo**; 100% equivale a um núcleo inteiro. CPU própria do Quickshell e CPU da árvore são métricas distintas.

| Prioridade | Condição | Observação | Próxima decisão |
|---|---|---|---|
| **Crítica enquanto aberto** | **Media Mode com reprodução** | **67,8% qs / 68,8% árvore**; desligando visualizador e animação, ainda **57,5% qs / 58,7% árvore**. | Perfilar a CPU própria; testar demanda de Cava e listener separadamente. A causa dos 57,5% não foi isolada. |
| **Alta, contínua** | **Família em idle após navegar** | **34,5% árvore com cache / 33,0% sem cache**, com reprodução registrada ativa no idle. | Identificar widgets/serviços ativos e comparar com playback pausado; redução de RAM não basta. |
| **Alta, contraditória** | **Barra: layout único** | CPU árvore **14,8 → 26,6%** na rodada 2; rodada 1 caiu 30,6 → 25,3%. | A duplicação existe, mas o benefício de CPU não foi reproduzido. Comparar estado e perfilar bindings/renderização. |
| **Alta, auxiliares** | **Privacy** | Ao desligar, árvore **14,8 → 10,7%**, redução calculada **4,2 pontos**; auxiliares −12,0 MiB. | Reduzir/compartilhar observação preservando detecção. O ensaio não atribui todo o ganho exclusivamente a `/proc`. |
| **Seguinte** | **Overview / Dock abertos** | Rodada 1: **22,0% / 14,8% árvore**, respectivamente. | Isolar captura, widgets de mídia e animação; controles de captura já existem. |

A anomalia antiga de 48,3% após descarregar mídia **não se repetiu**: na rodada 2 foram 3,3% e 3,0% na árvore descarregada. Manter o registro histórico, sem tratá-lo como patamar universal.

## 3. GPU: atividade e ocupação têm prioridades distintas

| Alvo | Observação | Interpretação |
|---|---|---|
| **Mídia + Background** | VRAM **237,6 → 214,1 MiB**; SM médio aproximado **13,6 → 4,7%** ao desligar duas opções. | Sinal de ganho gráfico; separar animação e visualizador. Não houve ganho de RAM. |
| **Família após navegação** | **222,9 MiB de VRAM nos dois modos** de cache. | A redução de retenção QML não reduziu o conjunto gráfico residente nesse par. |
| **Background** | Rodada 1: cerca de **145,1 MiB VRAM**, CPU baixa. | Decompor superfícies, buffers, capas e widgets; não confundir ocupação com atividade alta. |
| **Overview / Dock** | Rodada 1: SM aproximado **9,9% / 5,6%**; VRAM **81,7 / 18,2 MiB**. | Priorizar taxa de captura/renderização; bytes baixos não garantem GPU ociosa. |

SM é aproximação NVML por PID, não energia; não somar VRAM à RAM. Nenhum ensaio atribuiu todos os bytes de VRAM a texturas específicas.

## 4. Anomalias e correções da interpretação

| Achado | Consequência para a auditoria |
|---|---|
| `nav_policies_phone` atribui índice 1; o modelo/config principal indicam **Tradutor** nesse índice. Marcador não guardou o ícone da aba. | Preservar o ID bruto, corrigir sua descrição e retirar a alegação de Phone visitado. Seleção/validação por identidade é pendente. |
| Navegação tem 180 s, dos quais 25 s de idle final e 15 s de GC. | **Retenção permanente** e resultado independente do tempo de uso não foram demonstrados. |
| MPRIS vazio em `notes`, Playing em `notes_list_only`; Paused em uma fase do `family_nav_keep`. | Pares com interferência; repetir antes de quantificar ganho causal exato. Saída vazia não é sinônimo de pausado. |
| Protótipos de Calendário/Notas usam `Item`s e métodos vazios. | São remoções experimentais de funcionalidade, não implementações validadas de carga sob demanda. |
| Dashboard sem cache piora após abrir; layout único da barra aumenta CPU; Privacy off aumenta RAM. | Tratar como investigação prioritária, não como otimização já aprovada por todas as métricas. |
| Um binding loop em `Dock.qml` em cada execução de navegação. | Inspecionar a dependência; a ocorrência isolada não prova consumo contínuo nem explica 33% de CPU. |

Os detalhes e diferenças recalculadas estão em [testes-ab.md](testes-ab.md). Pequenas correções — Calendário 55,2 em vez de 55,3 MiB; Privacy 4,2 em vez de 4,1 pontos — decorrem de calcular diferenças antes do arredondamento.

## 5. Distância do end-4 e critério de sucesso

A comparação disponível continua sendo a **rodada 1**, família visual, não boot integral: end-4 **316,0 MiB PSS / 442,7 MiB RSS**, fork **903,7 MiB PSS / 1.055,8 MiB RSS**. Diferença de processo **587,7 MiB PSS**; árvore **655,6 MiB**. Há diferenças de funções e avisos de compatibilidade documentados em [comparacao-end4.md](comparacao-end4.md).

A rodada 2 não repetiu o end-4. Seus 779,1 MiB pós-GC sem cache não devem ser comparados como par equivalente aos 316,0 MiB antigos, nem usados para prometer uma meta atingida. Também não somar economias isoladas de IA, Dashboard, Calendário e Notas: compartilham dependências.

Aprovar uma melhoria exige preservar a função, reduzir a métrica alvo em pares repetidos e não regressar significativamente CPU, GPU ou latência. A meta deve incluir boot, idle e retorno ao idle após a mesma navegação nas duas versões, com reprodução/dados iguais. Ver [plano de melhorias](melhorias.md) e [pendências verificáveis](PENDENCIAS.md).

A execução investigativa está detalhada em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md), começando pela análise offline A0 e ajustes de validade T0, seguidos de um par de mídia ou Notas. A ordem do ranking indica impacto; o roteiro escolhe testes menores para esclarecer a causa antes de ampliar intervenções.
