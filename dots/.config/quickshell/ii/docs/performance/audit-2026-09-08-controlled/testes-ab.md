# Última rodada: resultados e validade dos A/B

**As seções iniciais são históricas, da rodada 1.** A seção “Rodada 2” apresenta os 15 ensaios novos, com diferenças recalculadas e limites de validade.

Cada cenário dessa rodada usou 20 s de núcleo, 20 s de controlador, 35 s aberto, 25 s fechado e 20 s descarregado. Os resumos descartam os primeiros cinco segundos de cada fase. A família com pré-carregamento habilitado veio da rodada anterior, com janela aberta de 30 s. Cada linha abaixo representa um processo novo.

## Barra: instanciar apenas o layout ativo

O protótipo modifica os dez Repeaters de `VerticalBarContent.qml`: os cinco da Island recebem modelo vazio no layout normal; os cinco do normal recebem modelo vazio na Island. O patch está em [bar-active-layout-prototype.diff](tools/bar-active-layout-prototype.diff). Somente a cópia privada recebeu a alteração.

| Aberto | Referência | Apenas layout ativo | Diferença |
|---|---:|---:|---:|
| RSS MiB | 579,148 | 577,762 | −1,386 |
| PSS MiB | 454,450 | 452,957 | −1,493 |
| PSS árvore MiB | 508,496 | 506,564 | −1,932 |
| CPU Quickshell % | 16,324 | 15,857 | −0,467 p.p. |
| CPU árvore % | 30,604 | 25,344 | −5,260 p.p. |
| VRAM MiB | 44,930 | 44,930 | 0 |
| Instâncias de screensharestate.sh | 2 | 1 | −1 |

A mudança eliminou uma cópia do monitor e a CPU da árvore caiu cerca de 17,2% relativamente. É um par de execuções, sem distribuição estatística de repetições; tratar a magnitude como observada, não constante. A diferença de RAM está na escala de variação da bancada. Este protótipo é prioridade de CPU, mas não explica centenas de megabytes.

O ensaio separado `bar_no_privacy` chegou a 11,1% de CPU da árvore, contra 31,3% da barra inicial. Ele ocorreu em outra rodada, sem controle suficiente de reprodução para atribuir toda a diferença ao Privacy. Desligar privacidade foi uma intervenção diagnóstica; não é a recomendação de produto.

## Mídia: resultado interferido, sem economia demonstrada

`media_static` desligou `background.mediaMode.backgroundAnimation.enable` e definiu `visualizerMode=0` na cópia.

| Aberto | Referência | Fundo estático / visualizador desligado |
|---|---:|---:|
| PSS MiB | 429,416 | 453,641 |
| CPU Quickshell % | 25,922 | 56,115 |
| CPU árvore % | 25,956 | 68,178 |
| VRAM MiB | 231,305 | 225,305 |
| GPU SM média aproximada % | 6,897 | 8,931 |

A referência não tinha Cava nas amostras abertas. A variante tinha Cava em todas as 34 amostras abertas, em 22 de 25 fechadas e em todas as 19 descarregadas. Na fase descarregada, a CPU da árvore chegou a **48,272%**, embora o Quickshell próprio estivesse em 0,899%.

Os registros MPRIS anteriores aos dois ensaios mostravam YouTube Music pausado. Antes do ensaio seguinte apareceu também KDE Connect em reprodução. Os registros históricos não acompanham a reprodução a cada fase: o momento preciso da mudança não ficou demonstrado. A presença de Cava é uma diferença concreta que impede considerar o A/B equivalente.

No código inspecionado, `CavaService.active` depende de `MprisController.activePlayer?.isPlaying`, e seu `Process.running` usa essa propriedade. `MediaMode.qml` acessa os pontos e conecta suas atualizações sem condicionar essa dependência a `visualizerMode`. Depois que o singleton é tocado, a reprodução pode manter Cava mesmo sem visualizador visível. O próximo experimento deve fixar MPRIS e separar consumidor, animação e captura de áudio. Não declarar que desligar os efeitos reduz CPU com base nestes dados.

## Família: desligar pré-carregamento

| Família aberta | Preferências originais | Três pré-carregamentos desligados | Diferença |
|---|---:|---:|---:|
| RSS MiB | 1.055,795 | 799,301 | −256,494 |
| PSS MiB | 903,735 | 666,297 | −237,438 |
| PSS árvore MiB | 975,672 | 736,518 | −239,154 |
| CPU Quickshell % | 4,449 | 6,020 | +1,571 p.p. |
| CPU árvore % | 17,376 | 21,867 | +4,491 p.p. |
| VRAM MiB | 225,742 | 225,742 | 0 |

A variante desabilita os caches de Sidebar esquerda, Sidebar direita e última aba do Cheatsheet. É a maior diferença de RAM observada numa variante da família. A VRAM igual é consistente com as mesmas superfícies visíveis; a redução vem principalmente de conteúdo/serviços antecipados em RAM.

A reprodução MPRIS estava diferente na execução sem pré-carregamento. As janelas também vieram de lotes distintos. Por isso, os valores são uma comparação observada com interferência registrada, não um efeito isolado estimado com intervalo de confiança. A CPU não melhorou. Falta medir a RAM depois de visitar todos os painéis e o custo de latência da primeira abertura.

## end-4

A última etapa da rodada 1 também concluiu o original após restaurar seu submódulo exato na cópia. Resultado: **442,688 MiB RSS, 316,026 MiB PSS e 84,492 MiB VRAM** para a família visual. As diferenças de boot, funções e avisos de compatibilidade estão na [comparação específica](comparacao-end4.md).

---

## Rodada 2: reavaliação dos 15 ensaios adicionais

Os números abaixo foram conferidos contra as 2.477 amostras preservadas em [round2/](round2/README.md). RAM é mediana da fase; CPU é calculada pela diferença de tempo de CPU, em % de um núcleo. Diferenças são calculadas antes de arredondar. Os pares têm uma execução por variante, duas aberturas no mesmo processo; isso não equivale a duas réplicas independentes. “Após GC” descreve a janela medida, não retenção permanente nem vazamento comprovado.

### 1. Calendário: lateral e pickers são parte do custo

A variante substituiu `EventSidebar`, `TimePickerPopup` e `DatePickerPopup` por `Item`s com métodos vazios. **Não implementou carga sob demanda funcional.** O experimento localiza uma subárvore relevante, mas remove edição, fontes e seletores. Ver [diffs exatos](round2/variants.json).

| Fase | Métrica | Completo | Sem lateral/pickers | Variação |
| --- | --- | --- | --- | --- |
| controller | pssMiB | 123,0 | 120,4 | -2,6 |
| open | pssMiB | 451,4 | 396,1 | -55,2 |
| closed | pssMiB | 410,7 | 366,7 | -44,0 |
| reopen | pssMiB | 477,4 | 415,7 | -61,7 |
| closed_again | pssMiB | 408,3 | 377,2 | -31,1 |
| unloaded | pssMiB | 401,7 | 377,3 | -24,4 |
| gc | pssMiB | 376,7 | 352,2 | -24,4 |

| Fase | Métrica | Completo | Sem lateral/pickers | Variação |
| --- | --- | --- | --- | --- |
| open | rssMiB | 594,7 | 533,6 | -61,0 |
| open | treePssMiB | 490,8 | 396,1 | -94,6 |

A diferença aberta é **55,2 MiB PSS no processo**, **94,6 MiB na árvore**; a parcela de auxiliares observados cai cerca de **39,4 MiB**. Corrigindo a diferença entre controladores, a redução do incremento do processo é **52,6 MiB**, aproximadamente **16,0%** do incremento completo de 328,4 MiB. A antiga conclusão de 29% misturava diferença da árvore com incremento do processo.

Ainda restam **275,8 MiB adicionais ao abrir a grade** e **231,9 MiB acima do controlador após GC**. O par não separa lateral, pickers, dependências globais, componentes compilados e arenas. O ganho absoluto pós-GC é 24,4 MiB; não esperar recuperar os 55,2 MiB após uso só adicionando um Loader.

### 2. Pré-carregamento: IA converge; Dashboard é uma anomalia

| Módulo/fase | Cache ligado | Cache desligado | Variação sem cache |
| --- | --- | --- | --- |
| Dashboard / controller | 226,7 | 135,5 | -91,2 |
| Dashboard / open | 272,9 | 322,9 | 50,0 |
| Dashboard / closed | 264,6 | 296,5 | 31,9 |
| Dashboard / unloaded | 249,7 | 300,1 | 50,3 |
| Dashboard / gc | 248,3 | 297,0 | 48,7 |
| IA / controller | 240,9 | 135,6 | -105,3 |
| IA / open | 279,6 | 280,7 | 1,1 |
| IA / closed | 275,3 | 277,5 | 2,2 |
| IA / unloaded | 278,0 | 277,9 | -0,1 |
| IA / gc | 278,0 | 277,7 | -0,3 |

IA economiza **105,3 MiB antes da primeira abertura** e chega a patamares próximos ao abrir e após GC. Isso não significa memória devolvida ao controlador: sem cache ainda há **142,0 MiB acima dele após GC**.

Dashboard economiza **91,2 MiB antes de abrir**, mas usa **50,0 MiB a mais aberto e 48,7 MiB a mais após GC** sem cache. Sua economia de boot não se manteve neste ensaio isolado. Investigar ordem de inicialização, cards, modelos e dependências, com repetições alternadas; nenhum perfil de alocação identifica ainda a causa.

**Não somar 105,3 + 91,2 para explicar a economia da família.** Os painéis isolados compartilham dependências no shell completo e os pares pertencem a execuções diferentes.

### 3. Barra: menos auxiliares, mas sinais contraditórios

| Métrica aberta | Referência | Layout único | Privacy off |
| --- | --- | --- | --- |
| pssMiB | 394,8 | 355,5 | 444,4 |
| treePssMiB | 447,0 | 408,2 | 484,7 |
| cpuPercent | 0,8 | 15,8 | 0,8 |
| treeCpuPercent | 14,8 | 26,6 | 10,7 |
| vramMiB | 44,7 | 44,7 | 45,2 |

O layout único reduziu **39,2 MiB PSS** aberto, mas elevou a CPU da árvore em **11,8 pontos percentuais** (14,8 → 26,6%). Na rodada 1, a redução foi só 1,5 MiB e a CPU caiu 5,3 pontos. Há duplicação estrutural confirmada no código, mas **o benefício de CPU não se reproduziu**. Não há evidência para chamar a piora de mera oscilação transitória de renderização; a busca pelos padrões selecionados de erros não encontrou binding loops nos três logs da barra.

Desligar Privacy reduziu a CPU da árvore em **4,2 pontos** e a parcela de auxiliares em **12,0 MiB**, enquanto o processo subiu **49,7 MiB PSS** e a árvore subiu **37,7 MiB**. É um sinal favorável para reduzir o trabalho do monitor, não uma economia líquida de RAM. O par remove o monitor inteiro: não atribui os 4,2 pontos exclusivamente à varredura de câmera em `/proc`.

### 4. Notas: maior diferença de RAM em uma subárvore removida

| Fase | Métrica | Completo | Sem NotesDetail | Variação |
| --- | --- | --- | --- | --- |
| controller | pssMiB | 126,4 | 121,3 | -5,1 |
| open | pssMiB | 332,3 | 176,1 | -156,2 |
| closed | pssMiB | 297,5 | 172,7 | -124,8 |
| reopen | pssMiB | 317,6 | 179,4 | -138,2 |
| closed_again | pssMiB | 313,2 | 176,1 | -137,2 |
| unloaded | pssMiB | 305,4 | 175,8 | -129,6 |
| gc | pssMiB | 299,8 | 168,9 | -130,9 |

Na abertura, o incremento passou de **205,9 para 54,9 MiB PSS**: redução ajustada pelo controlador de **151,1 MiB**; a diferença absoluta foi 156,2 MiB (161,1 MiB RSS). Após GC, o saldo sobre o controlador caiu de **173,4 para 47,7 MiB**, diferença ajustada de **125,7 MiB**; a diferença absoluta foi 130,9 MiB.

A base tinha apenas 9.187 bytes de documentos. Isso enfraquece a hipótese de centenas de MiB em texto de notas. Mas o teste **removeu todo o editor**, não isolou seus menus, IA ou canvas — este último já possui carregamento tardio. Os 54,9 MiB restantes também não são custo exclusivo de `NotesStore`.

Há uma variável externa diferente: `notes` registrou saída MPRIS vazia em todas as fases; `notes_list_only` registrou `kdeconnect Playing`. Saída vazia não comprova estado pausado, pois o coletor não guardou código de saída/stderr. O tamanho da diferença justifica priorizar o editor, mas exige repetir o par sob reprodução idêntica antes de atribuir exatamente todos esses MiB a ele.

**Cuidado com a proposta de Loader:** `NotesAppContent.selectedId` já escolhe automaticamente a primeira nota. Condicioná-lo apenas a `selectedId !== ""` carrega o editor imediatamente. Preservando a experiência atual, decompor primeiro ferramentas ocultas dentro do editor; uma tela inicial só de lista mudaria o fluxo de uso.

### 5. Mídia: maior custo de CPU e GPU aberto

| Fase | Métrica | Referência | Estática/sem visualizador | Variação |
| --- | --- | --- | --- | --- |
| open | pssMiB | 430,5 | 445,0 | 14,5 |
| open | cpuPercent | 67,8 | 57,5 | -10,3 |
| open | treeCpuPercent | 68,8 | 58,7 | -10,2 |
| open | vramMiB | 237,6 | 214,1 | -23,5 |
| open | gpuSmMeanApprox | 13,6 | 4,7 | -8,9 |
| open | gpuSmPeak | 38,0 | 18,0 | -20,0 |
| closed | cpuPercent | 2,8 | 3,2 | 0,4 |
| closed | treeCpuPercent | 5,0 | 5,4 | 0,4 |
| unloaded | cpuPercent | 1,1 | 0,9 | -0,2 |
| unloaded | treeCpuPercent | 3,3 | 3,0 | -0,3 |

Ambos registraram `kdeconnect Playing` nas consultas por fase. Isso melhora a comparação com a rodada 1, mas não fixa nem monitora continuamente o fluxo. Desligar **duas opções juntas** reduziu atividade SM aproximada de 13,6 para 4,7% e VRAM em 23,5 MiB; não separa animação e visualizador. A RAM subiu 14,5 MiB.

Os **57,5% de CPU própria** restantes são a maior anomalia a perfilar. O código confirma `CavaService` ativado por reprodução sem demanda explícita e um listener do `MediaMode` que continua processando pontos com modo zero. **Isso não prova que esses caminhos expliquem os 57,5%.** O auxiliar é só parte pequena da CPU aberta; medir Cava/listener desligados separadamente e obter perfil de CPU QML/nativo.

A CPU da árvore após unload foi **3,3% / 3,0%**, não repetindo os 48,3% do caso interferido da rodada 1. Ainda existe trabalho residual, porém o extremo anterior não deve ser apresentado como comportamento universal.

### 6. Navegação curta: ganho de RAM observado, cobertura incompleta

O driver solicita IA → índice 1 de Policies → Atalhos → Calendário → Dashboard. Na configuração principal preservada, IA, Tradutor e Phone estão habilitados; o modelo do código ordena IA, Tradutor, Phone. Portanto **o índice 1 corresponde ao Tradutor**, e não ao Phone descrito no nome histórico `nav_policies_phone`. Os marcadores da família não registraram `policyIcon`; não há validação runtime da aba. Este ensaio não comprova uma visita a Phone.

| Fase histórica | PSS keep | PSS unload | Variação PSS | Árvore keep | Árvore unload |
| --- | --- | --- | --- | --- | --- |
| core | 848,8 | 645,5 | -203,4 | 924,9 | 720,3 |
| open_policies_ai | 862,0 | 660,3 | -201,8 | 938,6 | 736,3 |
| nav_policies_phone | 869,4 | 662,5 | -206,9 | 946,4 | 738,8 |
| policies_closed | 879,0 | 663,0 | -216,0 | 956,6 | 739,7 |
| open_cheatsheet_keybinds | 877,4 | 692,7 | -184,6 | 955,0 | 769,7 |
| nav_cheatsheet_timetable | 929,4 | 882,3 | -47,1 | 1007,1 | 960,2 |
| cheatsheet_closed | 914,8 | 864,6 | -50,1 | 992,7 | 942,6 |
| open_dashboard | 926,3 | 819,0 | -107,3 | 999,3 | 897,1 |
| dashboard_closed | 923,6 | 814,5 | -109,1 | 1001,8 | 892,8 |
| idle_settled | 920,3 | 788,5 | -131,8 | 998,9 | 866,9 |
| gc | 914,5 | 779,1 | -135,3 | 993,0 | 857,8 |

`core` já contém a família inteira carregada; não é um núcleo vazio. A sequência tem **180 s programados**, incluindo **25 s de idle final e 15 s de GC**; descartar os cinco segundos iniciais de cada fase reduz ainda mais a janela útil. O benefício observado foi **131,8 MiB PSS no idle e 135,3 MiB pós-GC**, sem evidência de permanência por horas ou de cobertura de todos os painéis pesados. Notas e Overview, por exemplo, não foram visitados.

O registro de MPRIS foi `Playing` em todas as fases de `unload`; em `keep`, `open_dashboard` registrou **Paused**, e as demais Playing. A comparação não ficou inteiramente controlada. Ambos os logs registraram um aviso de binding loop em `Dock.qml` e um de atribuição em `AndroidNetworkToggle.qml`; não foram quantificados como causa de consumo.

**RAM menor não trouxe idle barato:** a CPU da árvore no idle final foi **34,5% com cache / 33,0% sem cache**; VRAM foi **222,9 MiB em ambos**. Após GC, CPU foi 33,2% / 30,5%. Desligar retenção não resolve o custo contínuo da família. Não há execução do end-4 com essa mesma sequência na rodada 2.

### 7. Serviços: preservar o contrato funcional

O inventário de código informa o que cada serviço deve fazer; não é um A/B que mede economia para todos eles.

| Serviço | Direção de otimização | Função a preservar |
|---|---|---|
| LocalSend | Adiar inicialização quando `autoStart` estiver desligado; encerrar trabalho sem consumidor/operação. | Com `autoStart` ligado, receber arquivos em segundo plano é intencional. Visibilidade do popup não pode ser a única condição. |
| Privacy / screen share | Compartilhar observadores e preferir eventos onde houver cobertura; medir recuperação/polling restante. | Acesso direto à câmera pode exigir fallback próprio; não assumir que somente PipeWire/portais cobrem tudo que o código atual detecta. |
| KDE Connect | Separar sessão, consultas da UI e operações ativas; atribuir custo por helper. | Notificações, recebimento, sincronização e operações de câmera/microfone podem continuar com a página fechada. |
| ResourceUsage | Reutilizar o padrão de demanda já existente para GPU e leitura direta de `/proc`. | O padrão é referência arquitetural, não prova de custo ótimo nem motivo para suspender dados usados pela barra. |

As próximas perguntas e seus critérios de encerramento estão em [PENDENCIAS.md](PENDENCIAS.md).
