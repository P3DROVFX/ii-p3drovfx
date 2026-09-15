# Auditoria de memória do Quickshell II

**Data:** 2026-09-15  
**Sistema:** Hyprland + Quickshell  
**Projeto auditado:** fork local do Illogical Impulse (II)  
**Referência:** Illogical Impulse original do end4  
**Escopo:** memória residente, memória privada/anônima, heap JavaScript/QML, processos filhos e custo isolado dos principais panel loaders.

## 1. Resumo executivo

O teste controlado confirma que o fork não é uniformemente mais pesado que o End4. A diferença relevante está concentrada em poucos componentes e também existe uma diferença de aproximadamente **97 MiB de RSS na baseline sem panel loader ativo** no harness equivalente.

Os maiores sinais específicos do fork foram:

- `Background`: aproximadamente **+162 MiB de RSS** sobre a baseline do fork, contra **+56 MiB** no End4.
- `Overview`: aproximadamente **+122 MiB** no fork, contra praticamente **0 MiB** no End4.
- `Dock`: aproximadamente **+70 MiB** no fork, contra praticamente **0 MiB** no End4 no sandbox do End4.
- `ScreenCorners`: aproximadamente **+28 MiB** no fork, contra praticamente **0 MiB** no End4.
- baseline `none`: fork em aproximadamente **325,5 MiB RSS**, End4 em aproximadamente **228,3 MiB RSS**.

O resultado também descarta a hipótese de que todo o consumo venha das sidebars: no teste isolado, `sidebarDashboard` e `sidebarPolicies` ficaram praticamente na baseline quando seus conteúdos não foram mantidos carregados. O mesmo teste mostrou que o `verticalBar` ativo do fork consumiu aproximadamente **+20 MiB**, portanto não explica sozinho o uso de 650–675 MiB observado no shell completo.

O maior achado estrutural foi a diferença entre heap QML/JavaScript e memória nativa:

- `Overview` e o `Bar` horizontal do fork aumentaram o `JSGCHeap` para aproximadamente **54 MiB**, indicando um grafo grande de objetos QML/JS.
- `Background` aumentou muito o RSS, mas manteve `JSGCHeap` próximo de 5 MiB; o custo parece estar principalmente em recursos nativos do Qt, surfaces, imagens, vídeo/parallax ou janelas Wayland.

Os próximos alvos de maior retorno são, nesta ordem, **Overview**, **Background** e **Dock**. A barra vertical não aparece como prioridade. `Cheatsheet`, `Lock`, `OSD`, `ScreenTranslator` e `WallpaperSelector` foram mais pesados no End4 durante este teste específico; portanto, não há evidência de que devam ser otimizados no fork antes dos três alvos acima.

## 2. Estado e histórico investigado

O problema original foi a elevação do uso em idle de aproximadamente **900 MiB para 1,3 GiB** no preset Crabcake. Ao retornar ao `config.json` padrão do shell, o uso caiu para aproximadamente **800 MiB**. Testes manuais posteriores encontraram custos aparentes em widgets, sidebars, sons de notificação, esportes, cheatsheet, edit mode e outros módulos.

O relatório combina:

1. Os resultados manuais fornecidos durante a investigação.
2. Testes instrumentados por processo limpo no fork.
3. Testes equivalentes no sandbox do End4.
4. Inspeção estática da arquitetura, loaders, serviços e singletons.

Os números manuais abaixo devem ser lidos como **observações do usuário**, não como a mesma medição instrumental de `/proc` usada nas tabelas principais.

### 2.1. Observações manuais do preset

| Área | Observação registrada |
|---|---|
| System monitor bar widget | Acréscimo aparente de aproximadamente 30 MiB. |
| Sidebars mantidas carregadas | As duas sidebars aumentaram aproximadamente 200 MiB; Dashboard respondeu pela maior parte. Policies com AI chat, translator e phone aumentou cerca de 50 MiB. Sem Phone, cerca de 30 MiB. |
| Phone na policy | Remover Phone aumentou o consumo instantâneo em um teste, sugerindo que sua presença/desativação altera um serviço ou ciclo de vida adicional. |
| Sidebars sem keep-loaded | Com as duas sidebars descarregadas e a bar vazia, o shell ficou em aproximadamente 600 MiB; abrir Dashboard levou a aproximadamente 700 MiB. |
| Notificações | Uma notificação chegou a provocar aproximadamente 100–150 MiB momentâneos; com system sounds desabilitados, o acréscimo caiu para aproximadamente 20 MiB. |
| Quick toggles | Acréscimo de aproximadamente 20 MiB no teste controlado. |
| Connect mode | Dashboard consumiu aproximadamente 100 MiB a mais em idle que no modo default. |
| Dock | Dock completa aumentou aproximadamente 100 MiB. O Sports widget foi o maior custo, cerca de 65 MiB. |
| Dynamic island | Aproximadamente 70 MiB, considerado dentro do esperado. |
| Background | Aproximadamente 30 MiB; a maior parte veio de parallax. Sem anomalia evidente no teste manual. |
| Overview | Aproximadamente 20 MiB; animações de background adicionaram outros 20 MiB apenas ao abrir. |
| Lockscreen | Sem acréscimo relevante em idle com efeitos ativos. |
| Search, overlays e OSD | Sem acréscimo relevante em idle no teste manual. |
| Cheatsheet | `keepLastTabReady` aumentou aproximadamente 50 MiB. Timetable adicionou aproximadamente 80 MiB ao abrir; typing test aproximadamente 60 MiB. |
| Modes and routines | Aproximadamente 40 MiB após abrir. |
| Usage | Aproximadamente 50 MiB após abrir; ainda precisa ser validado se existe timeout de liberação. |
| Clock bar widget | Aproximadamente 40 MiB. |
| Policies panel button | Aproximadamente 35 MiB. |
| System monitor widget | Aproximadamente 20 MiB, independente da quantidade de itens. |
| AI Usage widget | Aproximadamente 20 MiB. |
| Portwatcher | Aproximadamente 30 MiB. |
| Shell update indicator | Aproximadamente 50 MiB; candidato para investigação. |
| Calendar bar widget | Aproximadamente 30 MiB, apesar de ser estático. |
| Weather widget | Aproximadamente 30 MiB. |
| Sports widget da bar | Aproximadamente 70 MiB sem esportes rastreados e 100 MiB com esportes. |
| Desktop widgets | Aproximadamente 30–50 MiB; considerados baixa prioridade. |
| Edit mode | Aproximadamente 150 MiB ao abrir; deve liberar tudo ao fechar, sem cache permanente. |
| Welcome | Aproximadamente 50 MiB; deve liberar tudo imediatamente após fechar. |

O teste instrumental abaixo não reabriu cada popup nem reproduziu todos os eventos de usuário. Seu objetivo foi primeiro separar o custo de cada `PanelLoader` em um processo novo e compará-lo com o End4.

## 3. Ambiente e fontes comparadas

### 3.1. Fork auditado

- Working tree lógico: `/home/pedro/.config/quickshell/ii`
- Working tree real: `/home/pedro/Downloads/ii-vynx/dots/.config/quickshell/ii`
- Preset/configuração do usuário: `/home/pedro/.config/illogical-impulse/config.json`
- Família usada no shell normal: `ii`
- Estado final após os testes: família normal restaurada; nenhum harness temporário permanece no fork.

### 3.2. End4

- Fonte original encontrada em: `/home/pedro/.config/quickshell/dots-hyprland`
- Sandbox de teste: `/tmp/end4-ii-memory`
- Commit-base anotado para a comparação: `2f0c8bf4`
- Configuração isolada do sandbox: `/tmp/end4-ii-xdg/config/illogical-impulse/config.json`

O End4 foi executado em diretório e XDG state/config/cache/data separados para evitar alteração no fork e para evitar que os arquivos persistentes dos dois shells fossem misturados.

### 3.3. Estado da instância ao finalizar

Após restaurar o fork, a verificação mostrou uma única instância ativa:

```text
qs -c ii
PID: 481049
shell id: 76d274969eac68cddbfc49b5d8700aa0
```

O PID é apenas uma fotografia do momento da auditoria; ele não deve ser reutilizado em uma reprodução futura.

## 4. Inspeção estática antes das medições

Os seguintes números são indicadores de superfície arquitetural, não atribuições diretas de RAM:

| Estrutura | Fork | End4 | Interpretação |
|---|---:|---:|---|
| `shell.qml` | aproximadamente 358 linhas | aproximadamente 77 | O fork concentra mais bootstrap, serviços e loaders no shell. |
| `panelFamilies/IllogicalImpulseFamily.qml` | 48 `PanelLoader` | 20 `PanelLoader` | O fork instancia ou conhece uma superfície maior de componentes. |
| `panelFamilies/PanelLoader.qml` | 40 linhas | 9 linhas | O loader do fork tem mais lógica de ciclo de vida. |
| Serviços QML | 277 arquivos | 53 arquivos | O fork possui uma camada de serviços significativamente maior. |
| Módulos `modules/ii` | 869 arquivos | 199 arquivos | A superfície visual do fork é muito maior. |
| Declarações de singleton | 241 | 68 | Mais singletons podem aumentar imports, objetos vivos e referências globais. |
| `GlobalStates.qml` | aproximadamente 2.820 linhas | aproximadamente 54 | O estado global do fork é muito mais abrangente. |
| `services/HyprlandData.qml` | 399 linhas | 166 | Há mais integração e estado de Hyprland no fork. |

Esses valores explicam por que a baseline do fork pode ser mais alta, mas não provam qual item retém a memória. A atribuição foi feita com o harness isolado.

## 5. Metodologia instrumental

### 5.1. Princípio do teste

Foi criado temporariamente um arquivo de família de panel loaders que mantém os mesmos imports e declarações principais, mas ativa somente o componente indicado pela variável de ambiente:

```qml
readonly property string selectedItem: Quickshell.env("II_MEMORY_ITEM") || "none"

PanelLoader {
    extraCondition: root.selectedItem === "overview"
    component: Overview {}
}
```

Cada item foi executado em um processo novo. O item `none` fornece a baseline do mesmo harness, com os mesmos imports e sem um panel loader ativo. O delta foi calculado como:

```text
delta(item) = métrica(item) - métrica(none)
```

Isso reduz a influência do custo fixo do runtime, embora não elimine diferenças de alocador, páginas compartilhadas, caches do Qt ou processos filhos.

### 5.2. Janela de estabilização

Cada processo foi deixado aproximadamente 10 segundos em execução antes da leitura. A leitura foi feita em `/proc/<pid>/smaps_rollup`; o heap JavaScript/QML foi obtido com `pmap -x`; e o RSS dos processos filhos diretos foi somado com `ps --ppid`.

Métricas coletadas:

- `RSS`: páginas residentes totais do processo.
- `PSS`: custo proporcional, dividindo páginas compartilhadas entre processos.
- `Private_Dirty`: memória privada modificável, normalmente o indicador mais útil para custo exclusivo.
- `Anonymous`: memória anônima residente.
- `JSGCHeap`: heap do motor JS/QML conforme exposto por `pmap`.
- `children_rss`: RSS de processos filhos diretos, como `gamma-control`, `nmcli` e helpers do módulo.

### 5.3. Teste de núcleo do fork

Antes do teste item a item, houve uma medição sem família e outra com os 20 loaders mínimos:

| Estado | RSS | PSS | Private Dirty | Anonymous | JSGCHeap | Observação |
|---|---:|---:|---:|---:|---:|---|
| Core sem panel loader, 60 s | 266.112 KiB | 147.862 KiB | 113.516 KiB | 113.516 KiB | 5.164 KiB | Boot mínimo e serviços imediatos reduzidos. |
| 20 loaders mínimos, 60 s | 626.988 KiB | 497.911 KiB | 442.112 KiB | 430.348 KiB | 53.720 KiB | Família equivalente ao conjunto mínimo usado na comparação. |
| Fork normal limpo, 30 s | 649.532 KiB | 520.491 KiB | 464.720 KiB | não repetido nessa leitura | 55.120 KiB | Instância normal após restauração. |
| Fork normal limpo, 81 s | 650.036 KiB | 520.964 KiB | 465.224 KiB | não repetido nessa leitura | 55.120 KiB | Mostra estabilidade próxima de 650 MiB antes de outros eventos. |

O conjunto de 20 loaders adicionou aproximadamente **361 MiB de RSS** sobre o core sem família. A diferença restante até o shell normal é compatível com serviços e módulos adicionais, e não com um único widget isolado.

### 5.4. Serviços usados no harness

Para tornar a comparação repetível, o shell temporário manteve apenas o bootstrap mínimo necessário para iniciar o ambiente:

- `MaterialThemeLoader.reapplyTheme()`
- `Hyprsunset.load()`
- `ConflictKiller.load()`
- `Cliphist.refresh()`
- `Wallpapers.load()`
- `Updates.load()`

O timer de serviços adiados foi explicitamente desativado para que serviços não relacionados não contaminassem a leitura de cada item.

## 6. Resultados brutos do fork

Baseline `none` do fork, aproximadamente 10 segundos após o boot:

| RSS KiB | PSS KiB | Private Dirty KiB | Anonymous KiB | JSGCHeap KiB | Filhos KiB |
|---:|---:|---:|---:|---:|---:|
| 325.536 | 207.292 | 167.180 | 167.180 | 5.352 | 4.352 |

### 6.1. Fork por item

| Item | RSS KiB | PSS KiB | Private Dirty KiB | Anonymous KiB | JSGCHeap KiB | Filhos KiB |
|---|---:|---:|---:|---:|---:|---:|
| `bar` | 464.288 | 335.226 | 283.096 | 282.672 | 54.268 | 16.204 |
| `background` | 487.732 | 364.684 | 315.928 | 304.592 | 5.392 | 16.388 |
| `cheatsheet` | 333.844 | 215.619 | 175.612 | 175.612 | 7.076 | 4.108 |
| `dock` | 395.308 | 269.953 | 214.296 | 210.764 | 15.156 | 4.352 |
| `lock` | 346.524 | 225.193 | 180.348 | 180.156 | 7.020 | 4.172 |
| `mediaControls` | 337.144 | 218.867 | 178.448 | 178.448 | 7.012 | 4.092 |
| `notificationPopup` | 340.540 | 220.984 | 178.560 | 178.560 | 7.032 | 4.352 |
| `osd` | 337.356 | 217.855 | 177.088 | 177.088 | 7.016 | 4.352 |
| `onScreenKeyboard` | 325.392 | 207.355 | 167.468 | 167.468 | 5.296 | 4.352 |
| `overlay` | 326.544 | 208.276 | 168.096 | 168.096 | 5.292 | 4.360 |
| `overview` | 447.824 | 321.154 | 274.020 | 273.828 | 54.964 | 16.680 |
| `polkit` | 335.776 | 216.072 | 175.928 | 175.928 | 7.012 | 4.356 |
| `regionSelector` | 323.728 | 205.592 | 165.820 | 165.820 | 5.352 | 4.352 |
| `screenCorners` | 353.124 | 230.373 | 182.456 | 182.084 | 5.288 | 4.040 |
| `screenTranslator` | 324.356 | 206.408 | 166.296 | 166.296 | 5.288 | 4.356 |
| `sessionScreen` | 324.416 | 206.195 | 166.188 | 166.188 | 5.288 | 4.356 |
| `sidebarPolicies` | 324.404 | 206.129 | 165.612 | 165.612 | 5.292 | 4.104 |
| `sidebarDashboard` | 324.828 | 206.776 | 166.632 | 166.632 | 5.352 | 4.356 |
| `verticalBar` | 345.808 | 222.988 | 174.400 | 174.156 | 5.360 | 4.356 |
| `wallpaperSelector` | 325.332 | 207.223 | 167.032 | 167.032 | 5.352 | 4.356 |

### 6.2. Deltas de RSS do fork

| Item | Delta RSS aproximado |
|---|---:|
| `background` | +162,2 MiB |
| `bar` | +138,8 MiB* |
| `overview` | +122,3 MiB |
| `dock` | +69,8 MiB |
| `screenCorners` | +27,6 MiB |
| `lock` | +21,0 MiB |
| `verticalBar` | +20,3 MiB |
| `notificationPopup` | +15,0 MiB |
| `osd` | +11,8 MiB |
| `mediaControls` | +11,6 MiB |
| `polkit` | +10,2 MiB |
| `cheatsheet` | +8,3 MiB |
| `overlay` | +1,0 MiB |
| `onScreenKeyboard`, `regionSelector`, `screenTranslator`, `sessionScreen`, `sidebarPolicies`, `sidebarDashboard`, `wallpaperSelector` | aproximadamente 0 MiB dentro do ruído |

\* O item `bar` foi forçado em uma configuração em que a barra normal não era a barra ativa; ele não deve ser usado para estimar o custo da barra vertical. Para o modo ativo investigado, usar `verticalBar` (+20,3 MiB).

## 7. Resultados brutos do End4

Baseline `none` do End4, aproximadamente 10 segundos após o boot:

| RSS KiB | PSS KiB | Private Dirty KiB | Anonymous KiB | JSGCHeap KiB | Filhos KiB |
|---:|---:|---:|---:|---:|---:|
| 228.300 | 109.082 | 85.620 | 85.620 | 1.184 | 0 |

### 7.1. End4 por item

| Item | RSS KiB | PSS KiB | Private Dirty KiB | Anonymous KiB | JSGCHeap KiB | Filhos KiB |
|---|---:|---:|---:|---:|---:|---:|
| `bar` | 228.280 | 109.128 | 85.700 | 85.700 | 1.184 | 0 |
| `background` | 284.360 | 142.858 | 108.408 | 108.392 | 4.848 | 12.344 |
| `cheatsheet` | 392.844 | 252.717 | 208.896 | 189.800 | 3.660 | 12.052 |
| `dock` | 228.764 | 109.297 | 85.636 | 85.636 | 1.184 | 0 |
| `lock` | 336.380 | 202.154 | 162.320 | 157.900 | 3.640 | 0 |
| `mediaControls` | 228.280 | 108.820 | 85.464 | 85.464 | 1.208 | 0 |
| `notificationPopup` | 230.508 | 110.873 | 86.528 | 86.528 | 1.188 | 0 |
| `osd` | 325.552 | 190.706 | 147.668 | 143.560 | 2.368 | 0 |
| `onScreenKeyboard` | 231.232 | 110.003 | 85.992 | 85.992 | 1.204 | 0 |
| `overlay` | 228.476 | 108.921 | 85.512 | 85.512 | 1.264 | 0 |
| `overview` | 229.056 | 109.512 | 85.968 | 85.968 | 1.184 | 0 |
| `polkit` | 247.804 | 126.102 | 97.516 | 97.516 | 6.264 | 12.100 |
| `regionSelector` | 230.772 | 109.625 | 86.140 | 86.140 | 1.184 | 0 |
| `screenCorners` | 228.532 | 108.927 | 85.236 | 85.236 | 1.184 | 0 |
| `screenTranslator` | 315.468 | 184.461 | 150.696 | 150.288 | 1.212 | 0 |
| `sessionScreen` | 226.040 | 106.325 | 82.664 | 82.664 | 1.184 | 0 |
| `sidebarLeft` | 228.892 | 109.188 | 85.408 | 85.408 | 1.184 | 0 |
| `sidebarRight` | 256.600 | 128.962 | 100.888 | 100.888 | 4.280 | 0 |
| `verticalBar` | 289.196 | 144.042 | 108.644 | 108.452 | 2.768 | 12.188 |
| `wallpaperSelector` | 284.696 | 145.064 | 109.440 | 109.424 | 5.108 | 12.356 |

### 7.2. Deltas de RSS do End4

| Item | Delta RSS aproximado |
|---|---:|
| `cheatsheet` | +164,5 MiB |
| `lock` | +108,1 MiB |
| `osd` | +97,3 MiB |
| `screenTranslator` | +87,2 MiB |
| `verticalBar` | +60,9 MiB |
| `wallpaperSelector` | +56,4 MiB |
| `background` | +56,1 MiB |
| `sidebarRight` | +28,3 MiB |
| `polkit` | +19,5 MiB |
| `onScreenKeyboard` | +2,9 MiB |
| `regionSelector` | +2,5 MiB |
| `notificationPopup` | +2,2 MiB |
| `overlay` | +0,2 MiB |
| `dock`, `bar`, `mediaControls`, `screenCorners`, `sessionScreen`, `overview`, `sidebarLeft` | aproximadamente 0 MiB dentro do ruído |

## 8. Comparação fork versus End4

### 8.1. Diferença de baseline

O fork começou em aproximadamente **325,5 MiB RSS** com `none`; o End4 começou em aproximadamente **228,3 MiB RSS**. A diferença é de aproximadamente **97,2 MiB RSS antes de um panel loader ser ativado**.

Essa diferença confirma que o fork possui custo fixo maior no runtime/import graph, mas ela não identifica uma causa única. As prováveis fontes estruturais são:

- mais serviços e singletons conhecidos pelo shell;
- `GlobalStates.qml` muito maior;
- `PanelLoader` com ciclo de vida mais complexo;
- mais imports e componentes auxiliares;
- lógica de bootstrap e estado persistente mais extensa.

### 8.2. Itens em que o fork é mais pesado

| Item | Fork | End4 | Diferença aproximada | Leitura |
|---|---:|---:|---:|---|
| `background` | +162,2 MiB | +56,1 MiB | fork +106,1 MiB | Principal discrepância nativa; investigar vídeo, parallax, surfaces e lifecycle. |
| `overview` | +122,3 MiB | +0,8 MiB | fork +121,5 MiB | Maior discrepância QML/JS; investigar árvore criada mesmo sem abrir a Overview. |
| `dock` | +69,8 MiB | +0,5 MiB | fork +69,3 MiB | No End4 a dock estava desativada; precisa de teste com config equivalente antes de concluir. |
| `screenCorners` | +27,6 MiB | +0,2 MiB | fork +27,4 MiB | Fork cria mais surfaces/objetos; verificar se quatro janelas ficam vivas sem necessidade. |
| `notificationPopup` | +15,0 MiB | +2,2 MiB | fork +12,8 MiB | Compatível com maior infraestrutura de notificação/som do fork. |

### 8.3. Itens em que o End4 foi mais pesado

| Item | Fork | End4 | Diferença aproximada | Leitura |
|---|---:|---:|---:|---|
| `cheatsheet` | +8,3 MiB | +164,5 MiB | End4 +156,2 MiB | O custo não é um defeito geral do fork; o End4 mantém mais dados/abas nesse harness. |
| `lock` | +21,0 MiB | +108,1 MiB | End4 +87,1 MiB | Não priorizar no fork sem um cenário reproduzível que contradiga este resultado. |
| `osd` | +11,8 MiB | +97,3 MiB | End4 +85,5 MiB | End4 criou mais objetos nativos nesse teste. |
| `screenTranslator` | aproximadamente 0 | +87,2 MiB | End4 +87,2 MiB | Não aponta problema no fork. |
| `wallpaperSelector` | aproximadamente 0 | +56,4 MiB | End4 +56,4 MiB | Não priorizar no fork com base nesta comparação. |
| `verticalBar` | +20,3 MiB | +60,9 MiB | End4 +40,6 MiB | A barra vertical do fork não é a causa do consumo alto observado. |

### 8.4. Sidebars

No fork, `sidebarDashboard` e `sidebarPolicies` ficaram praticamente na baseline porque o preset medido não mantinha o conteúdo carregado. Isso é coerente com os testes anteriores: o aumento grande aparece quando sidebars ou seus conteúdos são mantidos em memória, não apenas porque o `PanelLoader` existe.

No End4, `sidebarRight` aumentou aproximadamente 28 MiB, mas o sandbox tinha `keepRightSidebarLoaded: true`. Portanto esse número não é uma comparação justa com as sidebars descarregadas do fork.

Conclusão: as sidebars continuam importantes para investigar em cenários de `keep loaded`, mas não explicam o custo fixo alto do fork no teste `none`.

## 9. Heap QML/JS versus memória nativa

Este é o ponto mais importante para interpretar a diferença de “heap” e “memória anônima privada”.

### 9.1. Evidência no fork

- Core sem família: `JSGCHeap` aproximadamente 5 MiB; memória anônima aproximadamente 113 MiB.
- 20 loaders mínimos: `JSGCHeap` aproximadamente 54 MiB; memória anônima aproximadamente 430 MiB.
- `overview`: `JSGCHeap` aproximadamente 55 MiB e `Anonymous` aproximadamente 274 MiB.
- `bar`: `JSGCHeap` aproximadamente 54 MiB e `Anonymous` aproximadamente 283 MiB.
- `background`: `JSGCHeap` aproximadamente 5 MiB, mas `Anonymous` aproximadamente 305 MiB.

Isso indica dois tipos distintos de custo:

1. **Grafo QML/JavaScript:** muitos objetos, bindings, modelos, delegates, componentes carregados e referências vivas. `Overview` e `Bar` apresentam esse padrão.
2. **Memória nativa do Qt/Wayland:** imagens, texturas, scenegraph, surfaces, buffers, vídeo, processos auxiliares e alocações fora do heap JS. `Background` apresenta esse padrão.

Por isso, limpar referências JS ou forçar garbage collection não resolveria automaticamente todo o caso. Para `Background`, o caminho provável é destruir explicitamente recursos nativos ao fechar/desativar, parar players/timers e descarregar surfaces. Para `Overview`, o caminho provável é impedir a criação antecipada de componentes e reduzir modelos/bindings vivos.

### 9.2. O que não pode ser somado

Os deltas dos itens não devem ser somados para estimar o shell completo. Cada processo foi iniciado separadamente e o Qt compartilha páginas, importa módulos uma vez, cria arenas do alocador e pode manter caches. O valor é atribuição relativa, não decomposição aditiva perfeita.

## 10. Limitações e diferenças de configuração

A comparação é útil para priorização, mas não é uma equivalência perfeita.

### 10.1. Configuração do fork

No arquivo `/home/pedro/.config/illogical-impulse/config.json`, o estado relevante incluía:

- `panelFamily: "ii"`;
- barra vertical ativa;
- background ativo;
- music/video do background ativo;
- dock desativada;
- sidebars sem `keepLeftSidebarLoaded`/`keepRightSidebarLoaded`;
- overview desativada;
- `useAppDrawer` desativado;
- `cheatsheet.keepLastTabLoaded` desativado;
- corner-open da sidebar desativado.

### 10.2. Configuração do End4

No sandbox do End4, havia diferenças importantes:

- `bar.vertical: true`;
- `dock.enable: false`;
- `sidebar.keepRightSidebarLoaded: true`;
- `overview.enable: true`;
- `sidebar.cornerOpen.enable: true`;
- várias opções específicas do fork não existiam.

Consequências:

- O `dock` do End4 não é uma prova de custo zero em configuração habilitada; é um limite inferior do componente desativado.
- O `sidebarRight` do End4 foi medido com keep-loaded e não é comparável ao fork descarregado.
- O `overview` foi isolado pelo harness, mas suas condições internas e defaults divergiam.
- A diferença `bar` versus `verticalBar` exige cuidado: a medição `bar` do fork foi forçada em uma configuração vertical e não representa o caminho ativo.

### 10.3. Ambiente de sandbox

O End4 emitiu avisos benignos de sandbox:

- arquivo de cores geradas do `MaterialThemeLoader` ausente;
- falha de refresh do Cliphist com código 1/status 0.

Esses avisos devem ser eliminados em uma segunda rodada se for necessária uma comparação de produção, pois qualquer serviço que não inicialize pode reduzir artificialmente a memória do End4.

## 11. Como reproduzir

### 11.1. Regras de segurança

Antes de iniciar ou reiniciar qualquer Quickshell:

```bash
qs list --all --no-color
```

Não iniciar `qs -c ii`, `qs -p ...` ou `nohup qs ...` se uma instância já estiver ativa. Não usar IPC do Quickshell nem capturas de tela para esta auditoria. Não usar `hyprctl reload` como substituto de reinício do shell.

### 11.2. Preparar uma medição limpa no fork

O harness temporário usado na auditoria foi:

```text
panelFamilies/IllogicalImpulseFamilyMemoryEachTest.qml
```

Ele foi removido ao final. Para repetir, recrie-o a partir de `panelFamilies/IllogicalImpulseFamily.qml`, mantendo os mesmos imports e os 20 componentes, e substitua cada condição por:

```qml
extraCondition: root.selectedItem === "nome-do-item"
```

Adicione na raiz:

```qml
readonly property string selectedItem: Quickshell.env("II_MEMORY_ITEM") || "none"
```

Durante o teste, o `shell.qml` deve apontar temporariamente para a família de teste. Desative o timer de serviços adiados e mantenha apenas os seis serviços imediatos descritos na seção 5.3.

Depois confira as instâncias:

```bash
qs list --all --no-color
```

Inicie uma seleção:

```bash
II_MEMORY_ITEM=overview setsid -f sh -c 'exec qs -c ii' \
  >/tmp/ii-memory-each.log 2>&1
```

O comando deve ser usado somente depois que não houver outra instância do shell.

### 11.3. Medir o processo

Obter o PID da instância:

```bash
pid=$(qs list --all --no-color | awk '/Process ID:/ {print $3; exit}')
```

Após aproximadamente 10 segundos, coletar RSS/PSS/memória privada/anônima:

```bash
awk '
/^Rss:/ {rss=$2}
/^Pss:/ {pss=$2}
/^Private_Dirty:/ {dirty=$2}
/^Anonymous:/ {anon=$2}
END {
    printf "rss=%dKB pss=%dKB private_dirty=%dKB anonymous=%dKB\n", rss, pss, dirty, anon
}' /proc/$pid/smaps_rollup
```

Coletar o heap JS/QML exposto pelo `pmap`:

```bash
pmap -x "$pid" | awk '/JSGCHeap/ {rss += $3} END {printf "jsgc=%dKB\n", rss+0}'
```

Coletar RSS dos filhos diretos:

```bash
ps --ppid "$pid" -o rss= | \
  awk '{sum += $1} END {printf "children_rss=%dKB\n", sum+0}'
```

Encerrar a instância após a medição, confirmar que não restou processo e só então iniciar o próximo item:

```bash
kill "$pid"
qs list --all --no-color
```

### 11.4. Repetir todos os itens sem erro de shell

Ao automatizar no Bash, use um array real:

```bash
items=(
  none bar background cheatsheet dock lock mediaControls
  notificationPopup osd onScreenKeyboard overlay overview polkit
  regionSelector screenCorners screenTranslator sessionScreen
  sidebarPolicies sidebarDashboard verticalBar wallpaperSelector
)

for item in "${items[@]}"; do
  echo "=== $item ==="
  # iniciar processo limpo com II_MEMORY_ITEM="$item"
  # aguardar aproximadamente 10 s
  # coletar smaps_rollup, pmap e filhos
  # encerrar o PID
done
```

Não use uma string escalar contendo todos os nomes dentro de um loop Zsh/Bash: isso resulta em uma seleção inválida única e invalida a série.

### 11.5. Reproduzir o End4 sem tocar no fork

O End4 deve continuar em uma cópia separada:

```text
/tmp/end4-ii-memory
```

Use XDG isolado:

```bash
env \
  XDG_CONFIG_HOME=/tmp/end4-ii-xdg/config \
  XDG_STATE_HOME=/tmp/end4-ii-xdg/state \
  XDG_CACHE_HOME=/tmp/end4-ii-xdg/cache \
  XDG_DATA_HOME=/tmp/end4-ii-xdg/data \
  II_MEMORY_ITEM=overview \
  setsid -f sh -c \
    'exec qs -p /tmp/end4-ii-memory/dots/.config/quickshell/ii/shell.qml' \
    >/tmp/end4-memory-each.log 2>&1
```

O `shell.qml` do End4 deve apontar temporariamente para a família de teste equivalente. Repetir as mesmas leituras de `/proc`, `pmap` e `ps` no PID do processo. Sempre restaurar o `shell.qml` para:

```qml
component: IllogicalImpulseFamily {}
```

### 11.6. Logs e validação

Para consultar logs sem IPC:

```bash
qs log -c ii -t 50
qs log -c ii -t 120
```

Validar o working tree e o JSON:

```bash
git diff --check
jq empty /home/pedro/.config/illogical-impulse/config.json
git status --short
```

O teste original terminou com `git diff --check` limpo, nenhum harness temporário restante no fork e nenhum erro `Memory`, `TypeError`, `ReferenceError`, `Cannot read`, `Unable to assign` ou `WARN scene` nos logs consultados.

## 12. Ferramentas usadas

| Ferramenta | Uso |
|---|---|
| `qs list --all --no-color` | Enumerar instâncias e impedir processos duplicados. |
| `qs -c ii` | Iniciar o fork em teste limpo. |
| `qs -p <shell.qml>` | Iniciar a cópia do End4 fora do registro/configuração do fork. |
| `qs log -c ii -t N` | Verificar erros e avisos do shell. |
| `/proc/<pid>/smaps_rollup` | RSS, PSS, Private Dirty e Anonymous. |
| `pmap -x <pid>` | Identificar e somar `JSGCHeap`. |
| `ps --ppid <pid>` | Medir RSS de processos filhos diretos. |
| `awk` | Extrair e somar métricas sem alterar o shell. |
| `git diff --check` | Verificar whitespace e integridade textual das alterações. |
| `jq` | Validar o JSON persistente do usuário. |
| `rg` | Buscar declarações de loaders, serviços, singletons, erros e referências arquiteturais. |
| `git` | Comparar a estrutura do fork, preservar o estado do usuário e inspecionar modificações. |

Não foram usados IPC do Quickshell, capturas de tela, `hyprctl reload`, instâncias simultâneas ou processos `qs -p` deixados em background.

## 13. Próximas otimizações recomendadas

### Prioridade 1: Overview

O fork cria uma diferença de aproximadamente 121 MiB contra o End4 mesmo antes de a Overview ser aberta. Investigar:

- loaders que deveriam permanecer inativos até `overviewOpen`;
- modelos de app drawer e search criados no boot;
- componentes de background/animação instanciados antecipadamente;
- bindings em `GlobalStates` conectados à Overview;
- retenção após abrir e fechar;
- `JSGCHeap` alto, indicando objetos QML/JS vivos.

### Prioridade 2: Background

O custo é majoritariamente nativo. Investigar:

- `musicVideo` e players ativos mesmo quando não visíveis;
- parallax e texturas armazenadas;
- surfaces ou `PanelWindow` que continuam mapeadas;
- timers e conexões de frame;
- destruição explícita de player, source, texture e helper no close/disable;
- diferença entre `background.enable` e subopções habilitadas.

### Prioridade 3: Dock

O fork adicionou aproximadamente 70 MiB no harness, mas o End4 estava desativado. Repetir com os dois lados habilitados e o mesmo conjunto de widgets. O Sports widget continua candidato forte devido às medições manuais de 65–100 MiB.

### Prioridade 4: Widgets de alto custo

Depois dos três componentes estruturais, medir individualmente com a mesma técnica:

- Sports widget, inclusive com e sem competições rastreadas;
- Shell update indicator;
- Clock;
- Calendar;
- Weather;
- Portwatcher;
- Policies panel button;
- AI Usage.

Os testes devem separar custo de inicialização, custo de dados/serviço e retenção após remoção.

### Prioridade 5: eventos e liberação

Criar uma segunda matriz, com processo limpo e coleta em 0 s, 10 s, 60 s e após abrir/fechar:

- notificação com system sound ligado/desligado;
- cheatsheet, especialmente timetable e typing test;
- Usage;
- edit mode;
- welcome;
- dock Sports;
- Overview aberta e fechada;
- Background alternando enable/disable.

O critério de sucesso deve ser a volta do `Private_Dirty`, `Anonymous`, `JSGCHeap` e RSS próximo do baseline após um intervalo fixo, não apenas o desaparecimento visual do painel.

## 14. Conclusão

O consumo de aproximadamente 650–675 MiB do fork não é explicado pela barra vertical nem pelas sidebars quando descarregadas. O shell possui uma baseline estrutural aproximadamente 97 MiB maior que o End4 no harness equivalente, e alguns módulos adicionam memória de forma desproporcional.

O alvo mais urgente é a **Overview**, seguida por **Background** e **Dock**. O padrão de memória mostra que Overview/Bar estão ligados a um grafo grande de QML/JS, enquanto Background usa memória nativa fora do heap JavaScript. Essas duas classes exigem otimizações diferentes.

Os testes temporários foram removidos e o fork foi restaurado para a família normal. As alterações de usuário já existentes no working tree foram preservadas; este relatório é a única adição desta auditoria.
