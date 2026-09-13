# Auditoria de CPU e RAM do ii — 8 de setembro de 2026

**Complemento posterior:** a [auditoria consolidada com testes individuais de RAM, CPU e GPU](../audit-2026-09-08-controlled/auditoria.md) reúne esta investigação e os ensaios controlados concluídos depois. Este documento preserva os resultados e limites da primeira rodada.

O fork apresentou **1.050,953 MiB de RSS, 854,041 MiB de PSS e 4,117% de um núcleo de CPU** na medição de confirmação de 60 segundos. A árvore do shell, incluindo auxiliares, apresentou mediana conjunta de **1.036,573 MiB de PSS**. O maior desperdício de CPU identificado foi o polling duplicado de compartilhamento de tela, somado ao monitor de privacidade: **18,583% de um núcleo**, incluindo os subprocessos dessas três rotinas.

**Nesta primeira rodada, os painéis QML não foram isolados individualmente.** Esta auditoria mede processos, subárvores de processos e regiões de memória; inspeciona os ciclos de vida dos módulos e os compara com o checkout local do end-4. Não atribui megabytes de heap compartilhado a um módulo pelo seu tamanho de código. Os resultados permitem priorizar trabalho, mas não provam que uma mudança específica economizará os aproximadamente 400 MB mencionados pelo usuário. O complemento posterior mede incrementos por painel em processos isolados; a atribuição exclusiva por objeto/alocação continua pendente.

As propostas, escritas após esta análise, estão em [melhorias.md](melhorias.md).

## 1. Escopo e método

- Instância `ys5qvs01lt`, PID **1220578**, iniciada às 00:38:55 de 08/09, horário da Bahia. Um único processo principal `qs -c ii` estava ativo.
- Fedora, Qt **6.11.1**, jemalloc carregado, bibliotecas NVIDIA **610.57.04**, **16 CPUs lógicas**. Um monitor **1920 × 1080, escala 1, 120 Hz**.
- Fork: commit `698c4ffaaa6f75d8bf1a5b8758456f8179cebf55`, com alterações locais. Houve alterações de desenvolvimento e recarregamentos durante a investigação; os arquivos relevantes foram registrados por hash em [manifest.json](manifest.json).
- Original local: `/home/pedro/.config/quickshell/dots-hyprland/dots/.config/quickshell/ii`, origin `end-4/dots-hyprland`, commit `97c5bc651f68092351b24aaa935af708b1e04514`, de 27/08/2026. Comparação de código; **não foi executado um benchmark novo do original**.
- Ferramentas: `/proc/PID/stat`, `/proc/PID/smaps_rollup`, `/proc/PID/smaps`, estatísticas de threads, árvore de descendentes, duas capturas de amostras de CPU com `perf`, leitura de logs, metadados de arquivos e revisão do código.
- Sem chamadas IPC do Quickshell, capturas de tela, atalhos simulados, reinícios, segunda instância, instalação de dependências ou alterações de comportamento/configuração. Os monitores foram finitos e encerraram.
- O shell permaneceu em uso natural. Não houve controle de interação, reprodução de áudio ou abertura de painéis; **estas medições não são um benchmark de idle estritamente controlado**.

**Unidades:** MiB = 1.048.576 bytes. RSS conta páginas residentes integralmente; PSS divide páginas compartilhadas; privada = `Private_Clean + Private_Dirty`. PSS é a comparação mais útil do custo físico proporcional. VIRT não mede RAM consumida. Referência: [documentação do kernel sobre `/proc`](https://docs.kernel.org/filesystems/proc.html).

**CPU:** 100% significa um núcleo completamente ocupado. 18,583% de um núcleo corresponde a aproximadamente 1,16% da capacidade agregada das 16 CPUs lógicas; não significa 18,583% da máquina inteira. CPU medida por diferenças de ticks, não pela média histórica de `ps %CPU`.

## 2. Memória e CPU do processo principal

| Janela | Amostras | RSS mediano | PSS mediano | Privada mediana | CPU média |
|---|---:|---:|---:|---:|---:|
| Inicial, cerca de 30 s, atividade de recompilação no perfil próximo | 121 | 1.094,453 MiB | 889,465 MiB | 856,188 MiB | 54,03% |
| Investigação de 120 s, inclui recarregamento no início | 60 | 1.129,625 MiB | 937,719 MiB | 907,387 MiB | 11,975% |
| Trecho de 89,256 s, após os primeiros 30 s dessa investigação | 45 | 1.129,262 MiB | 937,389 MiB | 907,051 MiB | 4,795% |
| Confirmação independente de 60 s | 31 | **1.050,953 MiB** | **854,041 MiB** | **823,285 MiB** | **4,117%** |

Dados: [resumo inicial](baseline-summary.json), [amostras de 120 s](runtime.json), [trecho posterior](stable-window.json), [confirmação](confirmation.json). A confirmação ocorreu de **01:05:18 a aproximadamente 01:06:19**, horário da Bahia. Swap do processo: **zero** nas janelas medidas.

A primeira janela chegou a **1.262,090 MiB de RSS**; usá-la como repouso inflaria a conclusão. A leitura de 2.000 linhas recentes de log encontrou sete mensagens de recarregamento, oito de configuração carregada e nenhum `Binding loop` ou `String.arg()` naquele trecho. Isso não demonstra ausência desses erros em todas as sessões.

Na investigação de 120 s, o PSS caiu de aproximadamente **940 para 848 MiB** entre os instantes 112 e 114 s, sem troca do PID. Essa queda comprova que parte da memória é liberável nessa sessão. Não identifica se a liberação veio de uma janela, imagens, garbage collector ou arenas do alocador. A sessão observada **não permite diagnosticar um vazamento contínuo** nem separar o custo de início limpo do custo acumulado por hot-reload.

## 3. Em que tipo de memória estão os megabytes

Snapshot de `smaps` ao final da confirmação. As categorias abaixo são mutuamente exclusivas dentro deste snapshot.

| Categoria | PSS | Interpretação |
|---|---:|---|
| Alocações anônimas nativas e outras sem nome | **596,484 MiB** | Maior bloco; pode conter QObjects, strings, metadados QML, imagens, buffers e arenas retidas. Não é um contador de cache. |
| Bibliotecas compartilhadas, incluindo drivers gráficos | **110,518 MiB** | Qt, Quickshell, multimídia, drivers e demais bibliotecas; não atribuível a um painel isolado. |
| Heap JavaScript identificado como `JSGCHeap:QtQml` | **86,016 MiB** | Páginas residentes administradas pelo GC; não equivale ao tamanho dos objetos vivos. |
| Mapeamentos de dispositivos | **33,754 MiB** | Principalmente NVIDIA; não é a VRAM total do shell. |
| Arquivos de fontes | **14,771 MiB** | PSS de fontes mapeadas; atlas de glifos e estruturas nativas podem estar nas outras categorias. |
| JIT e pilhas da VM QML | **4,996 MiB** | Código e pilhas identificáveis pelo nome dos mapeamentos. |
| Outros mapeamentos | **6,866 MiB** | Executável, arquivos e regiões restantes. |
| Cache QML de disco diretamente mapeado | **0,004 MiB** | Não mede o cache de componentes compilados mantido no heap. |

A soma do `smaps` é **853,408 MiB de PSS**; o `smaps_rollup` próximo deu **853,725 MiB**. Pequenas diferenças decorrem da precisão por mapeamento e das leituras não simultâneas. A mediana da janela é outra medida, 854,041 MiB.

**Não há evidência para afirmar “596 MB são cache desperdiçado” ou “AI usa 400 MB”.** A Qt aloca os QObjects no heap C++, enquanto wrappers/propriedades JavaScript usam a memória gerenciada; strings também têm buffers externos. Heaptrack sozinho não cobre corretamente todo esse modelo. Referência: [gerenciamento de memória JavaScript da Qt](https://doc.qt.io/qt-6/qtqml-javascript-memory.html).

Foram encontradas cópias de Google Sans Flex em diretórios diferentes. Isso merece organização futura, mas **todas as fontes mapeadas somam somente cerca de 15 MiB de PSS**: não são uma explicação principal para a diferença relatada.

## 4. Custos atribuídos a processos auxiliares

RAM abaixo é a mediana do processo indicado, sem somar bibliotecas por RSS. CPU dos dois monitores inclui o tempo dos filhos finalizados e contabilizados pelo próprio monitor (`cutime/cstime`). Isso captura `pw-dump`, `jq` e outros comandos curtos que uma fotografia de `ps` normalmente perde.

| Subsistema / processo | PSS na confirmação | CPU própria | CPU incluindo filhos contabilizados | Observação |
|---|---:|---:|---:|---|
| Privacidade: `privacy_probe.py` | **18,718 MiB** | 5,867% | **9,083%** | Um daemon, intervalo configurado de 1,2 s. |
| Compartilhamento: `screensharestate.sh`, PID 1309610 | 0,451 MiB | 0,050% | **4,867%** | Primeiro monitor; memória transitória dos comandos não incluída nesta célula. |
| Compartilhamento: `screensharestate.sh`, PID 1309682 | 0,453 MiB | 0,050% | **4,633%** | Segundo monitor simultâneo, mesmo script. |
| BudsLink: `gjs` / `bridge.js` | **20,128 MiB** | 0,000% | — | Custo residente, CPU abaixo da resolução útil desta janela. |
| KDE Connect: `monitor.py` | **15,678 MiB** | 0,000% | — | Watcher de integração com telefone. |
| Agente Bluetooth: `agent.py` | **15,091 MiB** | 0,000% | — | Serviço distinto do BudsLink. |
| LocalSend: bridge Python + CLI Rust | **aprox. 20,194 MiB** | aprox. 0,067% | — | Soma das medianas dos dois processos, não heap do QML. |
| App Usage: `app_stats` | **5,163 MiB** | 0,167% | 0,167% | Amostragem configurada a cada 10 s; custo relativamente baixo. |
| NetworkManager: `nmcli monitor` | 3,997 MiB | 0,017% | — | Monitor de eventos. |
| Teclado automático: `osk_autoshow` | 0,858 MiB | 0,067% | — | Baixo custo absoluto. |
| Contatos: `gio monitor` | 0,752 MiB | 0,000% | — | Watcher separado. |
| Touch gestures | 0,314 MiB | 0,117% | — | Baixo custo absoluto. |
| Controle gamma | 0,367 MiB | 0,000% | — | Baixo custo absoluto. |

Detalhes: [confirmation.json](confirmation.json) e [confirmation-summary.json](confirmation-summary.json). Os dois monitores de compartilhamento também coexistiram por mais de 110 segundos na janela anterior; não foi só uma sobreposição instantânea de startup.

**Não somar indiscriminadamente `cutime` do shell com os contadores das subárvores:** isso pode contar trabalho mais de uma vez. Não apresentamos um total exato de CPU de toda a árvore, pois processos curtos e trocas de geração exigiriam rastreamento completo de nascimento/saída.

### Compartilhamento e privacidade: duplicação confirmada

- `modules/ii/bar/widgets/indicators/ScreenShareIndicator.qml:29` cria um `Process { running: true }` por instância do widget. O processo continua existindo quando `visible` é falso.
- `scripts/screenShare/screensharestate.sh:8` executa `pw-dump | jq | sort | paste`, aguarda 1,5 s e repete. Duas cópias executam a mesma descoberta e usam o mesmo arquivo de estado e o mesmo nome temporário.
- `services/Privacy.qml:170` inicia outro helper. `scripts/privacy_probe.py:128` também executa `pw-dump`; a partir da linha 94 percorre diretórios de descritores dos processos para detectar câmeras.
- As preferências tinham `watchCamera`, `watchMicrophone` e `watchScreen` ativos. O indicador separado estava no layout da barra com `visible: false`; isso não o desinstancia.
- O custo combinado confirmou **9,500% + 9,083% = 18,583% de um núcleo**. É custo observado das rotinas existentes, **não promessa de economia integral** de uma implementação nova.
- A origem exata das duas instâncias visuais não foi inspecionada em runtime. O local de criação por widget é conhecido; não atribuímos a duplicação a dois monitores, pois havia somente um monitor físico.

### Picos e requisições que permanecem residentes

- **VPN:** processos `protonvpn` foram amostrados com até **102,983 MiB de PSS** na investigação. São fotografias de processos curtos, não pico máximo garantido nem memória permanente. `VpnService.qml:141` consulta todos os provedores instalados; a linha 153 repete o refresh a cada **10 s**, mesmo com backend configurado como `networkmanager`.
- **Email/calendário:** quatro helpers permaneceram presentes durante os 60 s completos da confirmação: `fetch_emails.py`, `fetch_all_accounts.py`, `fetch_labels.py`, `list_ics_attachments.py`. Somaram aproximadamente **49,387 MiB de PSS** pelas medianas. Os três primeiros fazem chamadas `urllib.request.urlopen` sem timeout explícito; o helper ICS usa timeout de 20 s por chamada. Não foi provado que estavam travados: o fato medido é residência prolongada com quase nenhuma CPU.
- **Google Drive:** `rclone` apareceu com aproximadamente **78,7 MiB de PSS** durante uma operação. Não continuou na janela de confirmação.
- **Letras:** `ytmusic-lyrics.py` permaneceu por mais de 110 s na primeira coleta, com **21,218 MiB de PSS** e 0,062% de CPU própria; não permaneceu na confirmação. Não deve ser contado como daemon permanente sem observar seu ciclo completo.
- **AI/settings index:** `ai_settings_index.py` teve um trecho de cerca de 2,1 s próximo de um núcleo ocupado. É atividade de construção observada no início da janela, não custo de idle da AI.

## 5. O que o perfil de CPU mostra dentro do Quickshell

Primeira coleta: 45 s, 49 Hz, evento `cpu-clock:u`, pilhas DWARF, **1.397 amostras**, herança de subprocessos habilitada. Inclui recompilação QML e ferramentas Python; não é perfil exclusivo do processo principal. O símbolo `QV4::Compiler::ScanFunctions::calcEscapingVariables()` apareceu com 7,02% das amostras de todo esse perfil. Isso aponta trabalho de compilação, não um binding loop identificado.

Segunda coleta: 45 s, 49 Hz, **sem herdar subprocessos**, **114 amostras**, zero amostras perdidas. Distribuição do tempo de CPU amostrado:

| Biblioteca | Parcela das amostras |
|---|---:|
| NVIDIA EGL core | 24,56% |
| Qt QML | 22,81% |
| Qt Core | 12,28% |
| libc | 11,40% |
| Qt Quick | 7,89% |
| Qt GUI | 4,39% |
| Demais | 16,67% |

Essas porcentagens **não são porcentagens da CPU da máquina**, nem medições de tempo GPU. A amostra é pequena e serve para direção da investigação: renderização/driver, execução QML, animações e eventos. O processo não foi iniciado com servidor QML profiler nem mapa de símbolos JIT; o `perf` não forneceu nomes de arquivo/linha para repartir esse trabalho entre todos os painéis.

Relatórios: [perfil com auxiliares](perf-processes.txt), [perfil do segundo intervalo](perf-second.txt), [símbolos](perf-second-symbols.txt). Os binários locais do `perf` ficam em `/tmp/ii-audit-2026-09-08*.perf.data`; não são necessários para ler esta auditoria e não foram publicados.

## 6. Auditoria de módulos e caches QML

Esta tabela registra evidência de lifecycle e prioridade de investigação. **“Não isolada” não significa zero.** O inventário completo das árvores e dos 276 arquivos QML em `services/` está em [module-inventory.md](module-inventory.md).

| Módulo | Evidência no código/configuração | RAM/CPU QML exclusivas |
|---|---|---|
| Sidebar Policies / esquerda | `keepLeftSidebarLoaded: true`; `visitedTabs` conserva abas visitadas; Loaders usam `isCurrentItem || visitedTabs[index]`. Hoje AI, Translator e Phone estão habilitados; Media, Wallpapers e Anime estão desabilitados. | Não isoladas; prioridade alta de teste de retenção. |
| Sidebar Dashboard / direita | `keepRightSidebarLoaded: true`; o conteúdo pode continuar residente. Listas pesadas aguardam a abertura; abas To-Do/Timer e páginas de toggles já têm carregamento seletivo. | Não isoladas; prioridade alta de teste. |
| Cheatsheet | `keepLastTabLoaded: true`; mantém somente a última aba, sem acumular todas. | Medição anterior do Corne: **+17,646 MiB PSS**, **+26,922 MiB RSS** na primeira construção. Não medida de todas as abas. |
| Settings | Descarrega após 5 s na configuração atual; `SearchRegistry.clearIndex`, `ThemePreviewCache.release` e `WallpaperPreviewCache.release` já estão conectados ao unload. | Não isoladas; custo residual de compilação/engine não é liberado por apagar apenas a árvore visual. |
| Background | Wallpaper JPEG de **3087 × 1612**, `scaleLargeWallpapers: false`. Sem Wallpaper Engine, blur com janelas desligado e wallpaper separado de lock desligado. | Não isoladas; buffer RGBA nativo de referência **18,983 MiB**, antes de cópias, texturas e mipmaps. |
| Lock e transições de wallpaper | `LockBlur` depende do estado/animação de lock; `TransitionImage` já destrói os ShaderEffectSources após a transição e limpa a imagem anterior. | Não isoladas; não tratar correções já presentes como trabalho novo. |
| Media Mode | Loader começa inativo; fechar desmonta a janela após liberar o foco. | Não isoladas; não é uma árvore permanentemente carregada por definição. |
| Cava | Depois de instanciado, roda sempre que o player MPRIS toca; não exige consumidor visual ativo. Configuração de 30 Hz e 32 barras. Foi visto inicialmente, ausente das duas coletas longas. | Sem medição comparável por janela; risco condicional de CPU, não causa demonstrada do 1 GB. |
| Overview/Search | Descarrega a janela após fechar, com exceção explícita de conteúdo que pede `keepAlive`. | Não isoladas; testar também painéis registrados que conservam estado. |
| AI | Limite atual de **1.000 mensagens vivas**; cache web com teto de 32 entradas e TTL de 120 s. | Não isoladas; limite por número não limita o volume de texto por mensagem. Sem prova de excesso nesta sessão. |
| App Usage | Janela é descartada; singleton `AppStats.history` conserva documentos dos dias consultados. `clearHistory()` é operação de apagar histórico em disco, não uma API de liberar só cache. | Helper medido em 5,163 MiB PSS; cache QML não isolado. |
| Wallpaper Browser | Acumula respostas/páginas no singleton; não foi encontrado teto de histórico nessa lista. `clearResponses()` zera referências. Aba desabilitada na configuração observada. | Risco em sessões de navegação; não apontado como culpado atual. |
| Wallpaper Selector | Janela ativa apenas quando o seletor está aberto; caches de previews têm serviços próprios. | Não isoladas. |
| Notes / Usage / Scratchpad | Loaders condicionais ao estado de abertura. Notes preserva dados no serviço. | Não isoladas. |
| Game Overlay | Loader existe quando aberto **ou** quando há widgets fixados. | Não isoladas; fechar overlay não implica necessariamente descarregar widgets fixados. |
| Dock, barra e widgets do desktop | Superfícies de longa duração; helpers colocados nos widgets podem multiplicar por instância. | Não isoladas; duplicação de ScreenShare medida separadamente. |
| OSD, notificações, polkit, Bluetooth e popups | Controladores e árvores transitórias têm políticas diferentes; imports/compilação não implicam janela visível. | Não isoladas; ver inventário para os demais módulos. |

A medida histórica da cheatsheet, de 07/09 e com outro PID, foi preservada em [historical-cheatsheet.md](historical-cheatsheet.md). Ela não pode ser somada ao PSS atual como heap exclusivo, nem extrapolada para Email, Commands ou calendários.

## 7. Comparação com end-4

| Estrutura inspecionada | Fork | Original local |
|---|---:|---:|
| Arquivos QML em raiz, modules, services e panelFamilies | **2.163** | **586** |
| Fonte QML nessas árvores | **20,457 MiB** | **1,883 MiB** |
| Arquivos QML em services, incluindo subcomponentes | **276** | **53** |
| Declarações de singleton em services | **168** | **45** |
| Declarações PanelLoader na família ii | **47** | **20** |

Dados estáticos: [static-inventory.json](static-inventory.json). São tamanhos de código, não RAM. O fork tem cerca de **10,9 vezes mais fonte QML** nessas árvores e muitas integrações adicionais; isso aumenta a superfície potencial de compilação e instanciação, mas não estabelece uma proporção de memória.

Diferenças relevantes:

1. O fork inicializa integrações adicionais em `shell.qml` e contém muito mais serviços e famílias de componentes. O custo precisa ser separado entre controlador, serviço ativo e UI sob demanda.
2. O fork mantém a última aba da cheatsheet preparada; o original começa esse Loader inativo.
3. O fork já melhora pontos do original: famílias externas são carregadas por URL, sem compilar antecipadamente a família Waffle; o Settings libera índices/previews; Overview e efeitos transitórios têm descarregamento seletivo.
4. O original também mantém controladores/superfícies e tem opção de manter a sidebar direita. **“O original não usa cache” seria uma conclusão incorreta.**
5. O valor de aproximadamente **600 MB** do original é uma referência fornecida pelo usuário, com métrica, configurações e histórico de uso não controlados nesta auditoria. Não se deve subtrair 600 MB desse PSS para atribuir a diferença a um módulo. Um teste válido requer mesma máquina, resolução, fonte, conteúdo, preferências equivalentes, protocolo de abertura e estado de início.

## 8. Cache em disco e logs em RAM

| Local / categoria | Espaço alocado | Relação com a RAM do processo |
|---|---:|---|
| `.cache/quickshell/crashes` | **1,600 GiB** | Arquivos em disco, não 1,6 GiB de heap do shell. |
| `.cache/quickshell/media` | **38,199 MiB** | Imagens/arquivos em disco; só viram buffers do processo quando lidos/decodificados. |
| `.local/state/quickshell` | **385,105 MiB** | Inclui ambiente Python e dados persistentes; não tratar tudo como cache descartável. |
| Histórico AppStats em disco | **2,773 MiB** | Tamanho em disco não fornece o tamanho da representação JS. |
| Logs órfãos em `/run/user/1000/quickshell/by-id` | **156,313 MiB** | Tmpfs: consome memória do sistema ou swap de tmpfs, fora do PSS principal. |
| Logs da instância ativa | **9,953 MiB** | Não remover durante a execução. |

Fonte: [storage.json](storage.json). O runtime estava em cerca de **11% de ocupação**, portanto não estava cheio. Os logs órfãos são uma oportunidade concreta de manutenção de memória do sistema, **mas removê-los não reduz em 156 MiB o RSS mostrado para `qs`**. Nada foi removido ou movido.

## 9. Limites e conclusão da análise

**Confirmado:** o processo se aproxima do 1 GB de RSS relatado; os auxiliares adicionam custo significativo; existe polling duplicado; consultas VPN têm picos transitórios relevantes; as duas sidebars conservam conteúdo por preferência; logs órfãos ocupam tmpfs; boa parte das otimizações de unload citadas no AGENTS já está implementada.

**Ainda não determinado:** megabytes exclusivos de cada painel/serviço QML; objetos vivos versus arenas livres dentro dos aproximadamente 596 MiB nativos; custo residual de cada hot-reload; VRAM por superfície; comparação de execução equivalente com end-4; economia final após aplicar mudanças.

`qmlprofiler-qt6`, heaptrack e gdb estão instalados, mas o processo atual foi iniciado sem infraestrutura de profiling QML. O QML profiler exige a infraestrutura de debug habilitada; sua saída separa criação, bindings, JavaScript, memória e pixmaps. Referência: [QML profiling](https://doc.qt.io/qt-6/qtquick-profiling.html), [opções de qmlprofiler](https://doc.qt.io/qt-6/qtqml-tooling-qmlprofiler.html). A própria ajuda local de heaptrack alerta que a injeção em processo em uso pode causar crash, e ela tampouco reconstrói as pilhas das alocações que ocorreram antes do attach.

Por isso, **o ranking quantitativo confiável desta etapa é por processo/subárvore e por categoria de memória**. O ranking de painéis é uma lista de hipóteses sustentadas pelo lifecycle, com lacunas declaradas. A medição causal por módulo requer a etapa controlada descrita nas propostas; não foi substituída por estimativas inventadas.
