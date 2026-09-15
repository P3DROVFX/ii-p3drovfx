# Investigação dos maiores consumidores e soluções possíveis

Esta análise segue o [ranking de prioridades](PRIORIDADES.md). Usa os ensaios existentes e leitura de código, sem executar novas rodadas ou aplicar alterações ao produto. “Confirmado no código” identifica uma regra de construção/retenção/trabalho; não significa que sua parcela de MiB já foi isolada.

O snapshot da rodada 1 foi registrado em `842411d065ada2b95a714dbeacc1387ada258aac`; a preparação da rodada 2 registra `21ecdff37b8d7e48e0a359a5c12bf24ab217e949`; o checkout lido está em `21ecdff37b8d7e48e0a359a5c12bf24ab217e949`. Os arquivos examinados foram comparados por conteúdo com a cópia da bancada; [evidencias-de-codigo.json](evidencias-de-codigo.json) registra hashes e diferenças. Um commit sozinho não identifica todas as alterações locais contidas no snapshot.

Os resultados novos foram reconciliados com os dados brutos em [testes-ab.md](testes-ab.md) e [round2/](round2/README.md). A ordem de implementação atual está em [melhorias.md](melhorias.md); a numeração abaixo mantém a navegação por área do código. Valores sem indicação de rodada nos parágrafos históricos são da rodada 1.

## 1. Pré-carregamento: maior diferença já observada na família

**Rodada 1:** 903,7 → 666,3 MiB PSS antes de navegar, diferença de 237,4 MiB com interferência. **Rodada 2:** diferença de 131,8 MiB no idle final e 135,3 MiB após GC de uma sequência de 180 s. A fase chamada Phone aponta ao índice do Tradutor e MPRIS divergiu em uma fase; não comprova economia permanente nem cobertura de todos os painéis.

### Caminho de código

Em [Cheatsheet.qml](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/cheatsheet/Cheatsheet.qml:109), `cacheWanted` ativa um timer de 1,5 s. Ele define `cachePrepared`; em seguida, o `RetainedLoader` usa `requested: activeState || cachePrepared`. A última aba pode ser construída e permanecer residente sem a janela aparecer. A referência salva no ensaio era Calendário.

[SidebarDashboard.qml](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/sidebarDashboard/SidebarDashboard.qml:16) e [SidebarPolicies.qml](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/sidebarPolicies/SidebarPolicies.qml:24) incluem `keep*Loaded` no predicado de conteúdo. Em [SidebarPoliciesContent.qml](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/sidebarPolicies/SidebarPoliciesContent.qml:437), a condição é ainda mais ampla: aba atual **ou qualquer aba visitada**, enquanto `tabsWanted` for verdadeiro. Com cache ligado, fechar a sidebar não torna esse predicado falso.

Isso é retenção intencional sem um limite de abas visitadas, e não prova de objetos perdidos. Ela pode fazer o custo crescer durante navegação até todas as políticas habilitadas terem sido visitadas. Os testes atuais de IA e Phone separados não mediram essa soma dentro de uma sessão.

### Solução possível

Separar três decisões: preparar o chrome leve, conservar a aba ativa por um período e pré-carregar conteúdo pesado antes de qualquer uso. Para aproximar o boot do original, usar as opções existentes sem pré-carregamento; para preservar rapidez, reter apenas a aba recente ou um conjunto com orçamento definido. Guardar rascunhos/seleção em estado leve e liberar a árvore pesada ao expirar.

O caso de Phone com microfone/câmera ativos precisa de exceção funcional; esses serviços não podem parar por uma troca de aba. Idealmente, a operação reside no serviço e não exige manter toda a UI de Phone. O estado de uma geração de IA também precisa sobreviver ao descarte visual.

No original, [Cheatsheet.qml](/home/pedro/.config/quickshell/dots-hyprland/dots/.config/quickshell/ii/modules/ii/cheatsheet/Cheatsheet.qml:27) começa com Loader inativo e o desativa no fechamento. Ele não tem o mesmo Calendário. As sidebars do original possuem políticas próprias; não é correto dizer que o end-4 nunca retém conteúdo.

**Validação restante:** identidade das abas, mesmos dados/reprodução, sequência mais longa e latência. IA economiza 105,3 MiB no controlador e converge após abrir; Dashboard economiza 91,2 MiB no controlador, mas termina 48,7 MiB maior após GC sem cache. Essa anomalia impede generalizar que toda desativação de cache melhora o pós-uso. Não somar as duas diferenças isoladas para explicar a família.

## 2. Calendário: pior incremento individual de RAM

**Medida:** +336,3 MiB PSS ao abrir; +272,0 MiB em relação ao controlador após unload; +257,3 MiB após GC. CPU própria aberta foi baixa, 0,3% de um núcleo. Prioridade principal: construção e retenção de memória.

### 2.1 A lateral fechada constrói páginas que não estão sendo usadas

[MonthView.qml](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/cheatsheet/timetable/MonthView.qml:951) instancia `EventSidebar` diretamente. Largura/visibilidade do slot escondem a lateral, mas não impedem sua construção. Dentro de [EventSidebar.qml](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/cheatsheet/timetable/EventSidebar.qml:762), os modos dia, tarefas, fontes, detalhes, editor e escopo são majoritariamente árvores simultâneas, selecionadas por `visible`.

A página de fontes, por exemplo, existe em [linha 1104](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/cheatsheet/timetable/EventSidebar.qml:1104) e contém `GoogleCalendarSetupGuide`, controles e bindings para CalendarSubscriptions, importadores, Email e Outlook. Há propriedades de dados do dia e Repeaters que não dependem de a lateral estar aberta. Referenciar esses singletons pode inicializar seus estados e dependências; esconder o item não oferece uma política de liberação.

**Rodada 2 — remoção experimental:** trocar lateral e pickers por `Item`s sem funcionalidade reduziu 55,2 MiB PSS absolutos no processo aberto e 94,6 MiB na árvore (aproximadamente 39,4 MiB em auxiliares). A redução do incremento, corrigindo controladores, foi 52,6 MiB; após GC a diferença absoluta foi 24,4 MiB. Não houve implementação funcional de carga sob demanda, nem separação entre lateral e pickers. A grade restante ainda acrescenta 275,8 MiB ao abrir e 231,9 MiB após GC; essa parcela precisa de perfil.

**Solução:** manter um controlador leve com `mode`, evento, rascunho e sinais; carregar por URL somente a página solicitada. Adiar “Fontes de calendário” até sua abertura e manter sincronizações globais necessárias num serviço separado. Os métodos atuais escrevem diretamente em IDs de inputs: a migração precisa fornecer uma API de página, como inicializar formulário e obter estado, preservando rascunhos e animação de fechamento. Simplesmente embrulhar o código num Loader quebraria essas referências.

### 2.2 Pickers inteiros existem antes de serem abertos

[MonthView.qml:1037](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/cheatsheet/timetable/MonthView.qml:1037) instancia `TimePickerPopup` e `DatePickerPopup` diretamente. São mostrador/controles e outro grid de datas que existem mesmo quando o usuário está apenas consultando o mês.

**Solução:** criar o picker correspondente na primeira solicitação, passar os valores iniciais e conectar a aceitação ao controlador. Destruir depois de concluir a animação, preservando a possibilidade de reabertura antes do descarte. Benefício individual em MiB ainda não medido; o A/B removeu os dois pickers junto da lateral.

### 2.3 A janela de eventos só aumenta

[CalendarService.qml:220](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/CalendarService.qml:220) inicia `rangeStart/rangeEnd` aproximadamente três meses antes/depois. [ensureRangeCovers():244](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/CalendarService.qml:244) expande as bordas ao navegar para fora e nunca as contrai. `loadEvents()` consulta novamente todo o intervalo; [eventsByDay:295](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/CalendarService.qml:295) reconstrói o índice de todos os eventos carregados.

**Problema concreto de crescimento:** navegar longe e voltar não reduz o horizonte residente nem o volume das próximas consultas. Isso não explica, sozinho, a primeira abertura medida: o ensaio não navegou anos de calendário.

**Solução:** cache por janelas/meses, com intervalo solicitado pelos consumidores e evicção de janelas antigas. Ao fechar a visualização, liberar sua solicitação, conservando apenas o horizonte exigido por alarmes, próximos eventos e outros consumidores. Não encolher arbitrariamente o singleton sem identificar esses dependentes. Objetos de eventos são referenciados pelos buckets; o índice `eventsByDay` não duplica necessariamente o payload inteiro de cada evento.

### 2.4 Detalhes de eventos sem limite por consulta

[finishCalendarRequest():535](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/CalendarService.qml:535) acrescenta cada resposta `read` a `eventDetailsByUid`, criando uma cópia rasa do mapa. Não há limite de quantidade/bytes nem expiração no caminho de leitura. Certas mutações limpam o mapa; fechar a lateral não o limpa.

**Solução:** cache limitado por tamanho/uso recente, com invalidação por UID e consumidores explícitos; remover entradas sem uso, mantendo edições pendentes protegidas. É um problema potencial de navegação longa. Não atribuir a ele o pico inicial sem demonstrar que houve consultas de detalhes.

### O que já está otimizado

[CheatsheetTimetable.qml:232](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/cheatsheet/CheatsheetTimetable.qml:232) já alterna mês/semana com Loaders mutuamente exclusivos e construção assíncrona. O grid mensal também usa carregamento gradual das células. A primeira intervenção deve ser a lateral/pickers, não repetir essas otimizações existentes. As 42 células visíveis não constituem, por si só, duplicação indevida.

**Próximo experimento de código:** a remoção já foi medida; manter mês/dados e validar uma implementação funcional com lateral/pickers sob demanda, medindo cada parte separadamente. Depois, em outro teste, navegar por datas distantes para avaliar cache de eventos. Não misturar as duas mudanças na mesma medição causal.

## 3. Barra: duplicação estrutural e resultados de CPU contraditórios

**Rodada 1:** +300,9 MiB PSS; layout ativo poupou 5,3 pontos de CPU e 1,5 MiB PSS. **Rodada 2:** referência +255,6 MiB; layout ativo poupou 39,2 MiB absolutos, mas CPU da árvore subiu 14,8 → 26,6%. A estrutura duplicada é confirmada; ganho consistente de CPU ainda não. Não há perfil para explicar essa inversão como renderização transitória.

### 3.1 Dois layouts construídos e processos por widget

[VerticalBarContent.qml:361](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/verticalBar/VerticalBarContent.qml:361) e o bloco normal mantêm cinco Repeaters cada. `visible` escolhe o desenho. [ScreenShareIndicator.qml:29](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/bar/widgets/indicators/ScreenShareIndicator.qml:29) inicia um processo por indicador. [screensharestate.sh:8](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/scripts/screenShare/screensharestate.sh:8) executa `pw-dump | jq | sort | paste` a cada 1,5 s. Duas cópias também disputam o mesmo nome de arquivo temporário.

**Solução estrutural candidata, com ganho de CPU a revalidar:** modelo vazio para o layout inativo ou criação exclusiva de sua árvore. Depois, um único observador compartilhado de screen share, independente do número de indicadores. O [protótipo preservado](tools/bar-active-layout-prototype.diff) cobre apenas a primeira parte.

### 3.2 Widget desabilitado continua sendo carregado

[BarComponent.qml:78](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/bar/BarComponent.qml:78) lê a preferência `widgetSelfVisible`, mas o [itemLoader:632](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/bar/BarComponent.qml:632) possui `active: true`. Ocultar um widget na configuração não impede sua construção e os efeitos de inicialização dele.

**Solução possível:** separar “widget habilitado pelo usuário” de “indicador temporariamente vazio”. O primeiro pode bloquear a criação do conteúdo, com placeholder leve no modo de edição. O segundo pode precisar continuar observando eventos para reaparecer. Não condicionar o Loader a `item.visible`: isso cria dependência circular e pode impedir que o indicador detecte o evento que o tornaria visível. A economia específica desta alteração ainda não foi medida.

### 3.3 A RAM que o primeiro patch não resolveu

`BarComponent.qml` contém 76 definições `Component` e um resolvedor para estilos/widgets. Elas **não são 76 widgets instanciados simultaneamente**. Há, porém, custo potencial de metadados, componentes compilados e dependências, além do widget selecionado e dos singletons. Os A/B deram diferenças de RAM distintas (1,5 e 39,2 MiB), ambas insuficientes para atribuir todo o incremento à duplicação. Esse caminho merece perfil, não inferência por tamanho do arquivo.

**Solução a testar, condicionada ao perfil:** registro leve de caminhos e construção por URL somente do widget/estilo escolhido, separando wrappers de implementações pesadas. Comparar o controlador, barra vazia, widget individual e barra completa. Não contabilizar linhas/imports como bytes de heap e não reescrever o registro inteiro sem medir seu efeito.

### 3.4 Privacy faz outra varredura

[Privacy.qml:32](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/Privacy.qml:32) usa intervalo padrão de 1,2 s. [privacy_probe.py:94](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/scripts/privacy_probe.py:94) percorre descritores de processos para câmera, além da consulta PipeWire para outros sinais. Esse é trabalho global, distinto das duas cópias do indicador. Na rodada 2, Privacy off reduziu 4,2 pontos de CPU da árvore e 12,0 MiB de auxiliares, mas elevou PSS do processo em 49,7 MiB. Não é economia líquida de RAM nem isolamento exclusivo da busca de câmera em `/proc`.

**Solução:** compartilhar observação de áudio/screen share e aproveitar eventos quando disponíveis; manter apenas as verificações de recuperação ou câmera que exigirem consulta, com escopo e frequência adequados. Não remover a detecção de privacidade para melhorar números.

## 4. Notas: terceiro maior incremento, mas a base era pequena

**Medida:** +206,3 MiB PSS; +190,9 MiB após unload. A janela já é destruída por [NotesApp.qml:46](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/notes/NotesApp.qml:46), portanto a proposta não pode ser simplesmente “adicionar um Loader”.

### 4.1 Todos os documentos ativos ficam residentes

[NotesStore.qml:63](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/notes/NotesStore.qml:63) explicita a política. `refreshResidents()` seleciona todas as notas fora da lixeira, e o [Instantiator:151](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/notes/NotesStore.qml:151) cria um `NotesDocumentFile` por ID. O serviço singleton permanece além da janela.

[NotesDocumentFile.qml:139](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/notes/NotesDocumentFile.qml:139) mantém o documento parseado e a representação serializada usada na gravação. [NotesService.rebuildProjection():549](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/NotesService.qml:549) percorre todas as notas e gera `tabsData` com conteúdo para consumidores legados, serializando a projeção antiga e a nova para compará-las. Isso acrescenta representações e trabalho proporcional à base; não implica que cada string ocupe uma cópia física integral, devido a compartilhamentos internos possíveis.

**Limite importante da evidência:** o snapshot tinha **11 documentos JSON, oito notas ativas, apenas 9.187 bytes de documentos e 7.891 bytes de índice**; cinco assets totalizavam 104.895 bytes em disco. Os conteúdos não foram expostos. Esse volume não sustenta explicar 206 MiB como “texto de notas em cache”. Assets podem expandir ao decodificar; ainda falta medir suas dimensões/uso. Os mapas existentes apontam aumento aproximado de 131 MiB em páginas anônimas nativas e 48 MiB no heap JS entre controlador e abertura, em fotografias de fase, sem atribuição por objeto.

**Solução de escalabilidade:** migrar widgets/overlay para índice e preview; carregar documento apenas para editor/consumidor ativo; manter um cache limitado de documentos limpos. Documento com gravação pendente deve permanecer até confirmação de persistência. Não introduzir LRU antes de corrigir os consumidores que atualmente pedem todas as notas, pois eles recarregariam imediatamente tudo.

### 4.2 Investigar construção do editor e ferramentas ocultas

[NotesDetail.qml:251](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/notes/NotesDetail.qml:251) instancia seletores, exportação, menus e bloqueio ocultos; [NotesEditor.qml:763](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/notes/editor/NotesEditor.qml:763) inclui seleção e ferramentas de IA na árvore do editor. São candidatos para construção sob demanda e para rastrear dependências. A implementação já adia a tela de desenho e páginas de Settings/Stats/Templates; preservar essas otimizações.

**Experimento da rodada 2:** a substituição inteira de `NotesDetail` por um `Item` vazio reduziu a diferença absoluta aberta em 156,2 MiB (161,1 MiB RSS), ou **151,1 MiB no incremento corrigido pelos controladores**. Após GC, diferença absoluta de 130,9 MiB e ajustada de 125,7 MiB. Não prova retenção permanente ou custo integral de editor/IA; menus, canvas e ferramentas não foram medidos separadamente. `notes` registrou MPRIS vazio; a variante, Playing. Repetir sob estado igual antes de atribuir o valor exato.

**Solução prioritária:** decompor ferramentas ocultas mantendo a edição funcional. [NotesAppContent.qml:77](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/notes/NotesAppContent.qml:77) seleciona automaticamente a primeira nota; um Loader condicionado apenas a `selectedId` carrega imediatamente. Abrir só a lista seria uma mudança de fluxo, e não reproduz a experiência do editor atual. O custo remanescente de +54,9 MiB aberto inclui lista, serviços e dependências, não só `NotesStore`.

## 5. Cava/Media Mode: maior anomalia de CPU

**Medida na Rodada 2 sob reprodução ativa (`media_reference` vs `media_static`):**
- Registrando a reprodução MPRIS ativa nas consultas por fase (`kdeconnect Playing`), a variante com fundo estático e `visualizerMode: 0` consumiu **57,5% de CPU no Quickshell** (vs 67,8% na referência com visualizador e animação de fundo).
- A redução de GPU foi confirmada (VRAM caiu de 237,6 para 214,1 MiB e atividade SM média de 13,6% para 4,7%), mas a alta CPU em Quickshell permaneceu.

**Caminhos de trabalho dispensável confirmados no código; parcela da CPU não isolada:**
1. [CavaService.qml:15](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/CavaService.qml:15) ativa o processo somente a partir de `isPlaying`. Não existe demanda de consumidores no predicado.
2. [MediaMode.qml:157](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/background/MediaMode.qml:157) conecta as mudanças de `CavaService.onVisualizerPointsChanged` a cada ~33 ms (30 FPS) sem verificar se `visualizerMode > 0`. Ele instancia continuamente novos arrays JS e dispara bindings reativos na thread principal do QML mesmo com o visualizador desligado na interface.

O par desligou animação e visualizador juntos. Não prova que os 57,5% restantes sejam causados por Cava/listener; medir cada caminho e perfilar a CPU própria. A árvore após unload caiu a 3,3% / 3,0%, sem repetir o extremo de 48,3% da rodada 1.

Há consumidores adicionais em MediaControls, widget de mídia do desktop, DockMediaWidget, FloatingNotchMedia, NeuralMedia e VerticalNeuralMedia.

**Solução:**
- Implementar contagem de consumidores ativos (`consumerCount > 0`) no singleton `CavaService`.
- Executar o processo `cava` apenas quando `isPlaying && consumerCount > 0`.
- Proteger o listener em `MediaMode.qml` pela demanda efetiva da UI e pelo modo habilitado, interrompendo as alocações quando o visualizador não estiver em uso. Balancear registros/liberação em todos os consumidores e preservar um único processo compartilhado.

## 6. IA/Phone: retenção do container primeiro

IA acrescentou 183,0 MiB; Phone, 163,8 MiB. A retenção de todas as abas visitadas, descrita na seção 1, é um alvo confirmado e comum. Limitar esse conjunto e manter estado operacional nos serviços tem mais base do que atribuir tudo ao histórico do chat ou à lista de dispositivos.

A IA já usa `StyledListView` para mensagens; não é correto propor trocar um Repeater inexistente por ListView. [Phone.qml:1457](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/sidebarPolicies/phone/Phone.qml:1457) já carrega subpáginas por URL e atividade do overlay. Investigar a página principal, bindings/Connections que tocam serviços de câmera/microfone/telefone, e separar observadores necessários de consultas sob demanda. Quantificar o custo interno de cada parte continua pendente.

## 7. Overview, Dock e Background: GPU com controles já existentes

[OverviewWindow.qml:156](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/overview/OverviewWindow.qml:156) permite captura ao vivo via configuração. Comparar frames congelados e atualizações por evento é um A/B útil, principalmente com muitas janelas. O descarte do painel já existe.

Uma correção à leitura superficial de `live: true`: [DockLivePreviewWidget.qml:43](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/dock/DockLivePreviewWidget.qml:43) já exige Dock revelado, janela visível, widget habilitado, monitor/privacidade adequados e seleção válida; [captureSource:291](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/dock/DockLivePreviewWidget.qml:291) vira nulo quando a captura está inativa. Há limite de escala de captura. Portanto, não há evidência de captura universal enquanto escondido. Investigar se a preferência “visível” versus “hover” e os widgets de mídia explicam a CPU aberta medida.

[BackgroundWidgetsWindow.qml:175](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/background/BackgroundWidgetsWindow.qml:175) já evita manter a superfície mapeada quando nenhum widget precisa dela, com exceções de edição/bloqueio/transição. Não propor esse mecanismo como se estivesse ausente.

[FloatingArtBackground.qml:87](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/modules/ii/background/FloatingArtBackground.qml:87) possui animação infinita condicionada a `animationEnabled`; a imagem já usa um quarto da resolução e blur condicional. Separar animação, blur, superfícies e visualizador em ensaios diferentes. A VRAM de 145 MiB do Background e 231 MiB com mídia não foi decomposta por textura/buffer; não é toda ela desperdício.

## 8. Auxiliares: reduzir picos e residência sem perder funções

[VpnService.qml:141](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/services/VpnService.qml:141) consulta os provedores instalados durante refresh; o timer repete a cada dez segundos. A sessão anterior observou um ProtonVPN transitório de 103 MiB. Descobrir provedores com menor frequência e consultar status só dos relevantes pode reduzir picos, preservando detecção de uma VPN externa ativa.

Os helpers [fetch_emails.py:12](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/scripts/email/fetch_emails.py:12), [fetch_all_accounts.py:11](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/scripts/email/fetch_all_accounts.py:11) e [fetch_labels.py:7](/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii/scripts/email/fetch_labels.py:7) fazem requests sem timeout explícito nessas chamadas. Aplicar deadline total, cancelamento e concorrência limitada é uma solução possível para residência prolongada. Os 49,4 MiB da auditoria anterior foram observados, não ganho validado de uma correção.

## Decisão técnica

Para **RAM**, investigar primeiro as subárvores de Notas e Calendário e a retenção transversal, preservando funcionalidade. Notas deu a maior diferença de remoção; Calendário mantém a maior parcela residual mesmo sem lateral/pickers. Para **CPU**, perfilar Media Mode e a família em idle; revalidar a barra porque o benefício inicial se inverteu na rodada 2. Dashboard sem cache é outra anomalia prioritária.

A investigação de serviços é estática onde não há A/B específico: LocalSend em autostart, recebimento, notificações, sincronização e operações do telefone podem legitimamente sobreviver à UI. Não impor visibilidade como único critério. Não recuperar os 587,7 MiB históricos de diferença via `gc()` periódico ou soma de economias isoladas. O [backlog](PENDENCIAS.md) define atribuição de heap, repetições, limites de dados, cobertura funcional e comparação final com end-4.
