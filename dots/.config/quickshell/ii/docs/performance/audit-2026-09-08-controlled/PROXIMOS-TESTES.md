# Próximos testes para atribuir CPU, RAM e GPU

Este é um plano de investigação, atualizado após as duas rodadas. **Os testes novos abaixo não foram executados nem implementados por esta atualização documental.** O objetivo é transformar as anomalias em perguntas menores, com uma intervenção identificável e um resultado que determine o próximo passo. Os números que motivam o plano estão em [PRIORIDADES.md](PRIORIDADES.md) e [testes-ab.md](testes-ab.md).

## 1. O que podemos fazer agora

| Ordem | ID do plano | Pergunta | Situação do ferramental |
|---|---|---|---|
| 1 | [A0](#a0) | Em que fase/thread/helper aparece o custo já registrado? | Análise offline dos dados existentes; algumas informações, como threads na rodada 2, não foram coletadas. |
| 2 | [T0](#t0) | A bancada seleciona o conteúdo correto e controla reprodução/repetições? | Correções e instrumentação necessárias antes de novo lote causal. |
| 3, CPU | [M1](#m1) | Os pontos de Cava ou seu consumidor explicam a CPU alta? | Novas variantes a construir na cópia; `media_static` é somente uma referência histórica. |
| 3, RAM | [N1](#n1) | Quais partes do editor de Notas provocam o aumento? | Decompor a variante histórica e preservar edição para validar a solução. |
| 4, RAM | [C1](#c1) | Quanto custa lateral, cada picker e o restante do Calendário? | Novas variantes e contadores por componente. |
| 4, anomalia | [B1](#b1) | O layout único da barra melhora ou piora CPU sob estado igual? | IDs base já existem; conferir o diff contra a revisão atual e repetir após T0. |
| 5 | [D1](#d1) | Por que Dashboard sem cache termina maior? | IDs base já existem; instrumentar construção tardia e cards. |
| 5 | [P1](#p1) | Qual parte de Privacy/screen share consome CPU e mantém helpers? | Contadores/variantes do monitor ainda necessários. |
| 6 | [F1](#f1) | O que mantém a família em cerca de 33% de um núcleo no idle? | Remoção controlada de um grupo por vez; identidade das abas corrigida. |
| 7 | [R1](#r1) | O saldo após fechar estabiliza ou cresce por ciclo/dados visitados? | Driver e agregador precisam distinguir ciclos e janelas prolongadas. |
| 8 | [G1](#g1) | VRAM vem de superfícies, imagens ou efeitos? | Métricas existentes + variantes gráficas separadas. |
| Conforme o resultado | [H1](#h1) | Quais pilhas/threads explicam a parcela não atribuída? | `perf`/`heaptrack` encontrados; integração com supervisor e suporte a símbolos a validar. |
| Após as intervenções | [E1](#e1) | O fork se aproxima do end-4 em condições equivalentes? | Repetir referência e fork com a mesma sequência; boot integral requer outro harness. |

Esses IDs organizam o plano; **não são novos argumentos já disponíveis em `run.py`**. O catálogo implementado continua em [tools/cases.json](tools/cases.json). Não executar todos os itens como um lote único.

## 2. Primeiro lote recomendado e duração

Começar por **A0 → T0 → um par de M1**, porque a CPU alta oferece uma hipótese testável com poucos componentes. Se a investigação escolhida for RAM, substituir M1 pelo primeiro par de N1. Em seguida, escrever o resultado e escolher a próxima variante a partir dele.

Usar inicialmente as fases já implementadas no supervisor genérico: `core` 30 s, `controller` 20 s, `open` 30 s, `closed` 30 s, `reopen` 20 s, `closed_again` 25 s, `unloaded` 20 s e `gc` 20 s. **São 195 s por execução**, sem contar preparação, boot e restauração. As rodadas anteriores usaram outras durações; não misturar seus períodos como se fossem o mesmo protocolo.

| Passagem | Execuções de processos novos | Tempo programado mínimo | Decisão |
|---|---:|---:|---|
| Piloto de T0 | 1 | 3 min 15 s | Validar abertura, fechamento, instrumentação e restauração. |
| Triagem A/B | 2 | 6 min 30 s | Procurar sinal e anomalias; não declarar ganho estável. |
| Confirmação A–B–B–A | 4 | 13 min | Ter duas execuções independentes por variante e conferir efeito de ordem. |
| Confirmação ampliada, se houver dispersão | 6 no total | 19 min 30 s | Três por variante; ainda reportar dispersão, sem prometer significância estatística. |

A–B–B–A refere-se à ordem de **processos novos**, com o mesmo seed restaurado antes de cada um. Reabrir o painel dentro do mesmo processo mede aquecimento/retenção, não outra réplica independente. O supervisor recusa repetir um ID no mesmo diretório: usar preparações novas com seed idêntico ou implementar IDs de execução distintos antes do lote. O `prepare.py` atual recopia dados live; preparações separadas não garantem, sozinhas, seeds idênticos. Conferir hashes privados dos seeds usados no par.

Aplicar o descarte inicial de cinco segundos já existente, mas exigir conteúdo correto/pronto antes de aceitar a fase. Se a construção ultrapassar a acomodação, registrar a latência e invalidar/adaptar a janela; não medir uma página vazia como economia. Não usar GC antes do ponto de repouso que representa uso normal. GC fica como diagnóstico adicional.

Parar a expansão do lote se a aba estiver errada, reprodução mudar, o alvo não carregar, uma variante falhar, o PID mudar ou a instrumentação interferir no resultado. Salvar a tentativa como inválida e explicar o motivo. Se os pares válidos mudarem de sinal ou tiverem sobreposição grande, classificar como inconclusivo e investigar estado/pilhas antes de ampliar indefinidamente a coleta. Ao terminar o lote, analisar os arquivos uma vez e escrever o relatório; não gastar chamadas acompanhando cada segundo.

<a id="a0"></a>
## 3. A0 — extrair mais dos dados já disponíveis

**Sem interromper a sessão.** Ler `round2/data/<caso>/measurements.json`, `summary.json`, `validacao.json` e os equivalentes históricos, preservando a separação entre rodadas.

1. Traçar PSS do processo, PSS da árvore, auxiliares e VRAM contra tempo/fase. Reportar mediana, faixa observada e máximo amostrado; máximo a cada segundo não é pico absoluto. Localizar se o aumento ocorre ao abrir, durante animação, após construção tardia ou no fechamento.
2. Para cada identidade `(PID, startTicks)`, calcular CPU própria por intervalo em que o processo aparece nos dois extremos. Agrupar auxiliares por nome de script e registrar aparecimento, desaparecimento e residência após unload. Não calcular diferenças cruzando reutilização de PID.
3. Separar tempo próprio de tempo de filhos encerrados. Os contadores de filhos podem mudar de proprietário quando processos terminam; não atribuir a mesma CPU ao helper e novamente ao pai. Processos nascidos e encerrados entre amostras continuam sendo uma limitação de atribuição.
4. Comparar os snapshots `maps` de controlador, aberto e GC: heap JS, anônimo/nativo, bibliotecas, fontes e mapeamentos de dispositivo. As leituras são fotografias de fase e não necessariamente coincidem com a mediana; não combinar ambas como contabilidade exata por objeto.
5. Alinhar marcadores, mudanças MPRIS e categorias de erros com a série temporal. Uma coincidência gera hipótese, não prova causalidade. Os dados de threads disponíveis na auditoria inicial não existem automaticamente nos cenários da rodada 2.

**Entrega:** `series-por-fase.json`, tabela de helpers e uma página de achados com links para caso/fase. Priorizar `media_static`, barra referência/layout único, Dashboard keep/unload e família idle. Se o custo estiver majoritariamente no processo qs, seguir para H1; se estiver nos auxiliares, concentrar o próximo A/B nos helpers encontrados. Esta análise suplementar ainda não foi produzida.

<a id="t0"></a>
## 4. T0 — preparar uma medição que consiga atribuir o problema

Estas mudanças são da **bancada privada**, não instrumentação permanente do produto. Preservar a versão dos scripts e um diff por variante. O [guia](GUIA-DE-AUDITORIA.md) continua definindo isolamento, uma instância por vez e recuperação. Não usar IPC do Quickshell nem capturas de tela.

| Lacuna atual | Adaptação exigida | Evidência de que ficou correta |
|---|---|---|
| Phone escolhido por índice | Resolver a aba por identidade estável no modelo da revisão e emitir identidade observada também nos casos de família. | Marcador mostra `smartphone` no teste Phone e `neurology` no teste IA, com conteúdo pronto. Índice pretendido sozinho não basta. |
| MPRIS externo variável | Usar fonte local controlada, registrar lista de players, player realmente selecionado pelo shell, estado e mudanças ao longo do ensaio. Guardar retorno/erro sanitizado da consulta. | Mesmo player/conteúdo/status em A e B; nenhuma troca silenciosa. Saída vazia é desconhecido/ausência/erro distinguível, nunca pausa presumida. |
| Playing não garante entrada equivalente de Cava | Manter a mesma fonte e rota de áudio; contar linhas de saída e se os pontos estão variando, sem gravar áudio. | Playback e entrada do visualizador comprovados; não substituir áudio real só por uma flag falsa de Playing para testar CPU completa. |
| IDs únicos impedem réplicas no mesmo resultado | Separar `experimentId`, `variantId`, `runId`, `cycle` e `phaseIndex`; preservar cada execução. | Agregador agrupa pelo conjunto, não mistura todos os períodos `open`. Enquanto não implementado, preparações distintas e seeds idênticos. |
| Fases nem sempre representam conteúdo carregado | Emitir pedido, carregamento pronto, início/fim de animação e descarte. Validar estado visível/mapeado e identidade. | Fase inválida não entra no resumo válido; latência de construção é medida separadamente. |
| CPU da thread não coletada nos módulos | Acrescentar deltas de `/proc/<pid>/task/<tid>/stat` com identidade/início do TID. | CPU própria por thread pode ser conciliada aproximadamente com a do processo; falhas/lacunas são explícitas. |
| Trabalho interno sem contagem | Contadores de criação/destruição dos componentes alvo, callbacks, consultas, linhas Cava e pedidos de atualização, publicados uma vez por fase. | O A/B confirma que somente a parte pretendida parou de construir/trabalhar; evitar log por frame. |
| Falha pode perder amostras | Gravar incrementalmente em arquivo privado; manter resultado parcial e motivo. Verificar fases antes de parar produção. | Tentativa falha fica recuperável e não é classificada como sucesso. |
| Instrumentação altera carga | Comparar uma referência com instrumentação desligada/ligada e mesma função. | Declarar overhead observado; não misturar perfil pesado com baseline normal. |

Fixar também nota/mês/aba, quantidade de eventos, wallpaper/capa, letras, vídeo, cor dinâmica, resolução/escala/refresh, configuração de widgets, energia e estado inicial dos caches da cópia. Para leitura de notas/calendário, começar com reprodução pausada controlada; para M1, reprodução ativa controlada. Mudar isso entre pares somente quando for a variável explícita.

Guardar no resultado os hashes de código/script/variante, metadados de tamanho dos dados, contagens de consumidores e flags relevantes sem segredos. Com o checkout atual avançando, não presumir que o protótipo histórico ainda representa o mesmo código. O piloto precisa comprovar encerramento da árvore do teste e restauração de uma instância normal, não apenas imprimir `restored: true`.

<a id="m1"></a>
## 5. M1 — separar Cava, listener e efeitos do Media Mode

**Pergunta:** quanto dos 57,5% de CPU própria sem visualizador/animação vem do produtor Cava e quanto vem do caminho que copia os pontos? Fontes: [CavaService.qml](../../../services/CavaService.qml) e [MediaMode.qml](../../../modules/ii/background/MediaMode.qml).

Em todas as variantes iniciais: mesma reprodução/áudio/capa, `visualizerMode: 0`, animação de fundo desligada, mesmas opções de letras/vídeo/cor. Registrar seu estado efetivo. O modo zero também evita acionar o visualizador procedural ao desligar Cava.

| Variante planejada | Única mudança perante M-base | O que isola |
|---|---|---|
| M-base | Nenhuma: cenário estático atual, Cava e listener existentes. | Reproduz a CPU alta sob estado realmente controlado. |
| M-listener-off | Desabilitar somente o `Connections` que copia pontos em MediaMode; manter Cava. | Trabalho desse consumidor e reavaliações derivadas; Cava deve continuar emitindo no mesmo ritmo. |
| M-producer-off | Impedir somente a execução de Cava na cópia; manter o listener e modo zero. | Produtor + parser + cascata de mudanças provocada por sua saída. Não equivale ao custo exclusivo do processo externo. |

Começar por M-base/M-listener-off; se não explicar o custo, testar M-base/M-producer-off. Se ambos alterarem partes do mesmo caminho, não somar as diferenças. Registrar CPU qs por thread, CPU dos helpers, callbacks/segundo, PSS JS/nativo, GC observado quando disponível, VRAM e SM aproximado.

**Como interpretar:** queda com listener off localiza trabalho no consumidor; queda só com produtor off aponta a parser/outros consumidores/cascata; nenhuma queda relevante leva a H1 no processo qs. Se M-base já não reproduzir a alta CPU, primeiro comparar o estado com a rodada 2, em vez de declarar o problema corrigido.

Depois, separar efeitos em outra matriz: animação off/on mantendo visualizador off; visualizador off/on mantendo animação off, sob o mesmo áudio. Se existir interação, medir a combinação por último. Ganho gráfico não é automaticamente ganho de RAM.

**Validação da solução funcional:** demanda explícita deve preservar todos os consumidores de Cava, iniciar um único produtor quando necessário e parar após o último consumidor sair. Medir abertura/reabertura e ausência de processamento com visualizador oculto, além de reprodução pausada/ativa. Não aplicar produtor globalmente desligado como correção final.

<a id="n1"></a>
## 6. N1 — decompor Notas mantendo o editor utilizável

**Pergunta:** onde estão os 151,1 MiB de diferença de incremento observados ao retirar `NotesDetail` inteiro? Repetir primeiro completo versus lista sem editor com seeds e reprodução iguais. É controle de diagnóstico, não aceitação de uma interface sem edição.

Construir variantes independentes na cópia, cada uma comparada com Notas completo: ferramentas de IA (`AiTextTask`, `NotesAiMenu`, `NotesAiCompareSheet`); exportação (`NotesExportSheet`); seletores/menus/bloqueio; por último, renderização de blocos do editor mantendo o mesmo documento carregado. Começar pelo grupo IA, sem requisições externas; se houver ganho, dividir seus componentes. Preservar ou adaptar explicitamente as APIs referenciadas pelos handlers — uma falha ao construir não vale como economia.

Manter a mesma nota selecionada, quantidade/tipos de blocos, anexos e tamanho da janela. Medir instâncias construídas/destruídas por grupo, número de documentos residentes, tamanhos dos payloads em disco, representações derivadas, PSS/heap e latência de construção. Contagem de bytes serializados é escala dos dados, não tamanho exato do heap JS.

`NotesAppContent.selectedId` já escolhe a primeira nota; Loader condicionado apenas a uma seleção existente não adia o editor. A tela de desenho já possui Loader: não atribuir seu custo sem confirmar que foi instanciada. Fontes: [NotesDetail.qml](../../../modules/ii/notes/NotesDetail.qml), [NotesEditor.qml](../../../modules/ii/notes/editor/NotesEditor.qml), [NotesStore.qml](../../../services/notes/NotesStore.qml).

**Decisão:** se menus/IA explicarem a maior parcela, implementar construção tardia funcional daquele grupo. Se o custo persistir com blocos vazios e dados iguais, H1 deve separar código/componentes globais de dados. Em outra etapa, usar bases sintéticas de 10/100/1.000 notas, texto e anexos em matrizes separadas, para medir crescimento de `NotesStore`/projeções. Não misturar o teste de escalabilidade com o primeiro A/B de UI.

**Aceitação funcional:** mesma edição/seleção/undo/autosave, abrir a ferramenta adiada e usá-la, fechar e reabrir sem perder estado. Simular respostas de IA com dados de teste, registrando que o custo de rede/modelo não foi medido. O ganho antes de usar a ferramenta e o saldo depois de usá-la devem ser reportados separadamente.

<a id="c1"></a>
## 7. C1 — Calendário por parte, depois dados e heap restante

**Pergunta:** a diferença conjunta de lateral/pickers está em `EventSidebar`, num picker ou nas dependências acionadas por eles? Começar por Calendário completo versus somente `EventSidebar` ausente. Manter os pickers e adaptar a API mínima necessária sem abrir os controles suprimidos.

Se necessário, seguir com pares independentes: completo versus apenas `TimePickerPopup` ausente; completo versus apenas `DatePickerPopup` ausente. O teste histórico que retirava os três serve para conferir interação, não para repartir seus MiB por proporção. Separar depois as páginas da lateral: fontes/integrações, formulário de evento, tarefas e consulta do dia.

Mesmos mês, locale, primeira data da semana, quantidade de eventos/tarefas/aniversários e dimensões. Instrumentar contagem de células/Loaders, criação da lateral/pickers, consultas/auxiliares disparados e momento em que ficam residentes. Analisar PSS árvore e qs: os cerca de 39 MiB de helpers antigos não pertencem necessariamente ao heap da lateral.

Para os **275,8 MiB adicionais restantes na grade**, comparar dados completos versus fixture vazia mantendo a mesma UI; depois, mantendo os dados, substituir somente delegados visuais por placeholders de mesma geometria. São dois experimentos distintos: um pergunta por escala/dados, outro por construção visual. Declarar serviços substituídos e usar H1 se a maior parcela continuar em memória nativa/JS sem proprietário identificado.

Fontes: [MonthView.qml](../../../modules/ii/cheatsheet/timetable/MonthView.qml), [EventSidebar.qml](../../../modules/ii/cheatsheet/timetable/EventSidebar.qml) e [CalendarService.qml](../../../services/CalendarService.qml). Mês/semana já são alternados por Loaders; células já têm construção gradual. Não propor de novo esses mecanismos como ausentes.

**Validação funcional:** abrir/fechar fontes, criar/editar/mover evento, aceitar/cancelar hora e data, preservar rascunho e reabrir. Depois navegar em uma fixture de eventos para mês inicial, +12, +24 e +36 meses e voltar; registrar intervalo consultado, eventos e tamanho de `eventDetailsByUid`. Isso investiga crescimento de cache; não explica retrospectivamente o primeiro open sem navegação.

<a id="b1"></a>
## 8. B1 — resolver a contradição do layout da barra

Repetir `bar_reference` versus `bar_active_layout` em A–B–B–A após T0, com a mesma configuração, mídia e posição de ponteiro fora de hover. Verificar o protótipo contra a versão atual. A diferença histórica foi −5,3 pontos de CPU na rodada 1 e +11,8 na rodada 2.

Contar Repeaters/delegados ativos, criação dos widgets e processos `screensharestate.sh`; registrar widgets selecionados, modo/layout e a superfície. CPU por thread separa candidato QML de renderização, mas nomes de thread sozinhos não atribuem função. Se a inversão persistir, usar H1 em referência e variante na fase aberta.

Em seguida comparar barra completa versus barra sem conteúdo visual, mantendo janela/geometria; dividir os widgets em grupos e testar somente o grupo que explicar a diferença. Confirmar individualmente o widget vencedor. Comparar cada intervenção com a mesma referência completa; não somar uma sequência de remoções com dependências compartilhadas.

O loader de `BarComponent` pode construir widgets explicitamente desabilitados; medir preferência desligada com construção atual versus realmente adiada. Não usar “indicador vazio” como equivalente a desabilitado: ele pode precisar observar eventos para reaparecer. **Aceitação:** alternância Island/normal, modo de edição e indicadores corretos, redução repetida sem regressão de CPU/GPU ou latência.

<a id="d1"></a>
## 9. D1 — Dashboard: inicialização tardia versus retenção

Repetir `dashboard_keep`/`dashboard_unload` com dados e estilo iguais. Conferir contagens e estado efetivo dos cards tanto no controlador quanto aberto: mesmo nome de página não prova conteúdo igual. O cenário sem cache terminou 48,7 MiB maior após GC.

Instrumentar `deferredContentReady`, `activateDeferredContent()`, loaders de QuickPanel e `CenterWidgetGroup`, abertura dos diálogos e destruição dos cards no [SidebarDashboardContent.qml](../../../modules/ii/sidebarDashboard/SidebarDashboardContent.qml). O código já possui conteúdo adiado e hosts de diálogo: a pergunta é quando esses caminhos são ativados e liberados.

Comparar também uma primeira abertura adiada na variante sem cache para igualar a idade do processo ao início da medição; registrar tempo desde **construção** e desde **abertura**, sem confundi-los. Depois decompor cabeçalho, QuickPanel e grupo central, uma parte por par, preservando os dados dos demais.

**Decisão:** se a diferença desaparecer ao igualar conteúdo/tempo, registrar a interferência e repetir o par corrigido. Se existir mais construção/residência sem cache, localizar a transição; se contagens forem iguais mas PSS permanecer maior, seguir para heap/arenas em H1. Não contar a economia de controller como economia de pós-uso.

<a id="p1"></a>
## 10. P1 — Privacy e observadores de compartilhamento

O par Privacy off remove o monitor inteiro. Para explicar seus 4,2 pontos de diferença na árvore, instrumentar na cópia número, duração e CPU de consultas de câmera `/proc`, `pw-dump`/parse e GeoClue, além da quantidade de monitores de compartilhamento. Registrar somente contagens/tempos, sem publicar nomes de aplicativos ou descritores pessoais.

Comparar monitor completo com cada fonte isoladamente suprimida, em testes de diagnóstico separados. Depois comparar observação atual versus um observador compartilhado funcional, mantendo a mesma cobertura. Uma medição curta de duração de função não substitui CPU total de seus subprocessos.

Começar com estados sintéticos sem captura/gravação de conteúdo. A detecção de V4L2 direto não pode ser removida simplesmente por adicionar eventos de PipeWire. Validar cada sinal detectado, início/fim, latência de atualização e recuperação após erro. LocalSend e KDE Connect exigem contrato próprio: recebimento/autostart/notificações/operações podem continuar legitimamente com a UI fechada. Esses contratos e economia de cada serviço continuam pendentes.

Se a CPU diminuir e a RAM de qs aumentar como no par anterior, medir mapas e instâncias antes de declarar ganho total. **Entrega:** custo por fonte, custo dos subprocessos e matriz sinal detectado/latência/cobertura; não apenas “monitor off usa menos CPU”.

<a id="f1"></a>
## 11. F1 — custo contínuo da família e navegação correta

Primeiro medir a mesma família sem cache em dois estados controlados: playback pausado e ativo. Comparar dentro de cada estado a família completa com **um único grupo removido**: conteúdo da barra, Dock ou widgets do desktop. A ordem de remoção não deve transformar o último caso no baseline dos próximos.

Gravar consumidores de Cava, processos/threads, timers/callbacks do grupo, CPU de qs/árvore e VRAM. Manter uma janela final de idle de **120 s** em todos os pares dessa etapa, sem GC até ela terminar; acrescentar GC como fase separada. Os 33,0% anteriores foram com reprodução no idle; não constituem baseline pausado.

Depois repetir keep/unload com sequência validada por identidade: IA → Phone real → Atalhos → Calendário → Dashboard → Notas → Overview → tudo fechado. Fixar os dados e ações em cada página; não chamar essa seleção de cobertura de todos os módulos. Na variante sem cache, `closed` de um painel não deve descarregar toda a família; reservar unload global para fase explícita.

**Critério:** apontar qual grupo responde pela CPU residual e qual memória permanece depois da mesma sequência. Publicar CPU/VRAM junto da economia de RAM. A comparação com end-4 só pode usar uma sequência funcional comum; módulos exclusivos são acréscimos medidos separadamente.

<a id="r1"></a>
## 12. R1 — crescimento por ciclo e caches de dados

Executar somente depois de identificar um alvo, não em todos os módulos. Exige T0 com identidade de ciclo no driver e agregador. Abrir 20 s/fechar 40 s por **20 ciclos**, mesma entrada; depois **300 s de idle**, GC e mais **60 s** de observação. São pelo menos **26 min**, além de boot/controlador. Não aplicar GC entre ciclos do teste principal.

Medir PSS de cada final fechado, instâncias vivas/destruídas, documentos/eventos/detalhes no cache, bytes mapeados e helpers. Comparar mediana dos primeiros/últimos ciclos e tendência após aquecimento; um aumento inicial que estabiliza difere de crescimento contínuo. Distinguir saldo que responde a cache, dados intencionais, arenas e objetos ainda referenciados. Nenhuma janela finita prova permanência ou ausência universal de vazamentos.

Separar a matriz de conteúdo: ciclos do mesmo documento/mês; navegação por documentos/meses novos; fixture pequena versus grande. Para Notas, contar documentos residentes e projeções; para Calendário, intervalo e detalhes; para Policies, abas visitadas realmente retidas. Nunca limpar caches pessoais, reiniciar entre ciclos ou misturar hot-reload nesse ensaio. Se o alvo crescer, H1 deve buscar alocações/refs responsáveis.

<a id="g1"></a>
## 13. G1 — atribuir VRAM e atividade gráfica

Usar M1 para separar visualizador e animação. Para Background, comparar janela/fundo com widgets e sem widgets; depois uma capa/efeito por par, mantendo dimensões, resolução e formato de imagem conhecidos. Não confundir remover a janela inteira com economia exclusiva de uma textura.

Registrar tamanho e quantidade de superfícies, imagens carregadas, resolução solicitada/decodificada quando disponível, VRAM por PID, CPU das threads de renderização e amostras NVML com timestamp. Desduplicar amostras e melhorar a ponderação temporal antes de tratar SM como uma série precisa; encoder/decoder/memória têm métricas distintas. Não atribuir GPU global ao shell.

Overview/Dock: avaliar custo do caminho de preview já existente com fontes sintéticas quando necessário, sem capturas de tela do computador ou frames gravados pela auditoria. Dock já possui gates de captura; primeiro demonstrar quando estão ativos. A janela de widgets do Background também já tem controle de mapeamento. A/B de renderização deve preservar geometria e registrar o que deixou de ser desenhado.

**Critério:** identificar uma diferença repetível de VRAM ou trabalho gráfico e a mudança correspondente; não classificar toda a ocupação como desperdício. Avaliar artefatos funcionais/latência sem introduzir screenshot como requisito desta bancada.

<a id="h1"></a>
## 14. H1 — perfis de CPU e alocação quando o A/B não basta

Inventário somente leitura desta atualização: `perf`, `heaptrack`, `heaptrack_print`, `gdb`, `nvidia-smi` e `bwrap` encontrados no PATH. `qmlprofiler` e `valgrind` não foram encontrados no PATH; também não apareceu `qmlprofiler` nos dois caminhos Qt consultados. Isso não é busca exaustiva de instalações. `/proc/sys/kernel/perf_event_paranoid` retornou 2. **Nenhum profiler foi anexado/iniciado**, e existência do binário não prova permissão, símbolos ou suporte de debug do build.

| Ferramenta/caminho | Pergunta atendida | Como preparar e interpretar |
|---|---|---|
| `/proc/<pid>/task` | Thread principal, renderização ou auxiliares? | Incorporar amostragem a T0; baixo detalhe, não fornece pilhas. |
| `perf record` / relatório | Quais pilhas acumulam CPU no cenário reproduzido? | Validar coleta de eventos de usuário no PID de teste; registrar por 30 s de fase estável, como subetapa supervisionada. Usar frequência moderada, verificar amostras perdidas e pilhas/símbolos. |
| `heaptrack --record-only` + `heaptrack_print` | Quais pilhas alocam, liberam e mantêm memória nativa? | Iniciar o qs da cópia já sob heaptrack, dentro do processo supervisionado/sandbox. Conservar PID real de qs, árvore e shutdown. Comparar perfis, não usar seu PSS como baseline normal. |
| QML Profiler | Quais bindings/sinais/construções/animações trabalham? | Localizar cliente/build compatíveis e confirmar debug no lançamento; registrar overhead. Atualmente não está pronto nesta bancada. Não instalar dependências automaticamente. |

O help local de heaptrack alerta que anexação a processo em execução pode causar crashes. Planejar **lançamento instrumentado na cópia**, sem anexar ao shell normal. `perf` também deve mirar somente o PID pertencente ao supervisor, com término conhecido. Se permissão ou símbolos impedirem um perfil, registrar a limitação e continuar pelos A/B/contadores; não mudar permissões globais silenciosamente.

O wrapper atual lança `qs` diretamente; precisa aceitar o prefixo do profiler e capturar seu encerramento antes de usar heaptrack. Estender somente a fase de interesse no lote instrumentado, e alinhar timestamps com os marcadores. Heap nativo alocado/liberado não é idêntico a PSS devolvido ao sistema, e detalhes internos de objetos JS podem aparecer agregados em arenas. O perfil deve trazer pilhas relevantes e seus limites, não apenas um total de “leak”. Arquivos de perfil ficam privados até revisão de conteúdo.

<a id="e1"></a>
## 15. E1 — confirmação contra o end-4

Após uma intervenção funcional, comparar fork anterior, fork alterado e end-4 no mesmo ambiente. Separar dois protocolos: família visual já coberta pelo harness; boot integral, cujo bloco real de inicialização ainda precisa ser exercitado num harness próprio. Não apresentar família como boot completo.

Definir sequência comum suportada por ambos, dados equivalentes, mesmo estado de mídia, fundo, resolução e tempo final fechado. Medir features exclusivas do fork em uma segunda sequência, explicitando seu custo. Registrar avisos/funcionalidades ausentes no original; original parcialmente quebrado não estabelece meta equivalente.

**Aceitação:** aproximação demonstrada em PSS/RSS da árvore, CPU de idle, VRAM e latência, antes e depois de usar as funções. Não mover custo para processos fora da contagem, somar ganhos isolados ou comparar os 316 MiB históricos do original diretamente com o pós-navegação de outra rodada.

## 16. Formato de entrega de cada teste

Guardar na bancada privada e exportar somente os dados revisados:

- identificação de experimento/variante/execução/ciclo, revisão, hashes e diff;
- pergunta, única variável alterada e funções removidas/preservadas;
- estados esperados e observados, validade por fase e motivos de exclusão;
- métricas absolutas, incrementos ajustados pelo controlador, diferenças entre pares e dispersão;
- contadores/pilhas que sustentam a explicação, resultados funcionais e latência;
- conclusão como **reproduzido**, **atribuição parcial**, **inconclusivo**, **não reproduzido** ou **melhoria funcional validada**, com próxima ação e limite temporal.

Atualizar [PENDENCIAS.md](PENDENCIAS.md) e o registro A/B assim que um lote acabar. Um teste concluído pode deixar a causa pendente. O guia de execução permanece em [GUIA-DE-AUDITORIA.md](GUIA-DE-AUDITORIA.md); não executar os IDs deste plano antes de implementá-los e validar o piloto.
