# Metodologia e limites

Esta metodologia descreve a rodada 1. As fases e limites adicionais da rodada 2 estão em [round2/README.md](round2/README.md) e [testes-ab.md](testes-ab.md); o método de agregação de RAM/CPU foi mantido.

O usuário autorizou interromper o shell e testar módulos abertos/fechados em ambiente controlado. A sessão normal foi encerrada; cada cenário executou um único processo Quickshell, supervisionado por Python, em uma sandbox Bubblewrap com renderização Wayland/NVIDIA real. Um bloco `finally` encerra a árvore do ensaio e restaura a sessão normal.

## Isolamento

- Snapshot do fork em `842411d065ada2b95a714dbeacc1387ada258aac`.
- Fonte, `illogical-impulse/config.json`, estado do Quickshell e cache foram copiados para um diretório privado em disco. Cada processo começa com uma nova cópia dos dados de referência.
- O sistema de arquivos original é somente leitura; as gravações ficam nas cópias. As configurações globais do Qt/KDE também têm cópia gravável: sem isso, o carregador de ícones do KDE bloqueava em um `kdialog` síncrono. As tentativas de calibração com esse bloqueio foram descartadas.
- Rede externa isolada por namespace. Isso impede sincronizações, mas também elimina respostas remotas e pode mudar os custos de integrações online. DBus, PipeWire, GPU e Wayland locais permanecem acessíveis.
- Testes em um workspace vazio temporário; o workspace anterior foi restaurado. Outros aplicativos não foram encerrados. O uso global da GPU variou, portanto ele não serve como consumo do Quickshell.
- Nenhuma chamada de IPC do Quickshell, nenhuma captura de tela e nenhuma instalação de dependência foi usada.
- O harness é um `ShellRoot` mínimo, carrega o tema e espera Config/Persistent ficarem prontos. O módulo é importado e carregado por URL. Suas dependências reais são instanciadas por demanda. Isso não reproduz todos os serviços tocados no boot do `shell.qml` de produção.

## Fases e métricas

A primeira rodada teve 19 cenários: núcleo sem módulo (15 s), controlador fechado (15 s), aberto (25 s), fechado (25 s), controlador destruído (20 s). A validação acrescentou janelas maiores, segunda abertura/fechamento e uma coleta explícita `gc()`. Os tempos exatos estão em `data/<cenário>/measurements.json`.

Amostragem aproximadamente a cada segundo. São descartados os primeiros cinco segundos de cada fase para o resumo estável. RAM e VRAM são medianas. CPU é a diferença de tempo acumulado entre a primeira e a última amostra útil, dividida pelo tempo de parede. Os números de CPU seguem a convenção **100% = um processador lógico ocupado**; o computador possui 16 processadores lógicos.

- **RSS:** todas as páginas residentes mapeadas pelo processo, inclusive bibliotecas compartilhadas.
- **PSS:** cada página compartilhada é dividida entre os processos que a usam. É a métrica principal desta análise de RAM.
- **Private:** páginas residentes exclusivas; coletadas junto de RSS/PSS em `/proc/<pid>/smaps_rollup`.
- **Árvore PSS:** soma das amostras do Quickshell e de seus descendentes observados.
- **Árvore CPU:** inclui CPU própria e de filhos terminados/recolhidos; a soma de contadores da árvore evita perder grande parte dos processos auxiliares curtos. Processos completamente desacoplados da árvore não são atribuídos.
- **VRAM:** memória gráfica por PID reportada por `nvmlDeviceGetGraphicsRunningProcesses_v3`, no driver NVIDIA. Não é somada à RAM do processo e não inclui a VRAM do compositor.
- **GPU SM:** amostras por PID de `nvmlDeviceGetProcessUtilization`. A média aproxima intervalos sem amostra válida de atividade como inativos; o pico reportado é preservado. Zero significa ausência de atividade registrada na granularidade da NVML, não prova de custo gráfico literalmente nulo. Os retornos e timestamps brutos foram preservados. A utilização de memória da GPU é atividade do controlador, distinta de ocupação da VRAM.

Aberturas foram verificadas por marcadores QML (`Loader.Ready`, item existente e estado aberto) e inventário de superfícies via `hyprctl -j layers/clients`, sem conteúdo de janelas. Settings registrou a página escolhida. A repetição dos atalhos registrou `cheatTab=keybinds`; Phone isolado registrou `policyIcon=smartphone`.

## Como interpretar as diferenças

O valor de um cenário é o **processo isolado inteiro**, com seu núcleo Qt/QML, serviços e bibliotecas. O custo incremental de carregar/abrir é uma diferença entre fases, não uma leitura de bytes pertencentes exclusivamente a um arquivo QML. Não se podem somar os módulos para estimar a RAM do shell completo: muitos carregam os mesmos singletons e bibliotecas.

O estágio “controlador” já contém conteúdo pré-carregado quando o cache está ligado. Para Background e Dock, que são superfícies residentes, o estágio “aberto” instancia o módulo e “fechado” o destrói. Na barra, fechar muda `barOpen` e o controlador é destruído separadamente. No modo de mídia, “antes de abrir” já inclui Background; fechar mantém Background, e descarregar remove ambos. Settings imita a liberação de seu host e caches cinco segundos após fechar.

A referência inicial às vezes perde entre 5 e 20 MiB por acomodação/GC. As diferenças pequenas de RAM exigem cautela, especialmente entre processos. A segunda rodada usa referências mais longas e o mesmo conteúdo para confrontar o cache.

Fechar uma janela libera suas superfícies gráficas, mas não obriga a engine QML, o alocador nativo ou os singletons a devolverem todas as páginas ao sistema. `gc()` coleta objetos JavaScript elegíveis; não limpa arbitrariamente singletons, bibliotecas, caches C++ e fragmentação. Saldo após fechar/descarregar **não é, sozinho, prova de vazamento**. Dois ciclos tampouco provam ausência de vazamento em uso prolongado.

## Correções de validade

O cenário inicial `policies_phone` solicitou o índice Phone antes da construção completa do SwipeView. Não registrou a aba efetiva e ativou auxiliares da IA; não é usado para atribuir consumo a Phone. `phone_only` habilitou apenas a política Phone na cópia e validou a aba após a construção.

O cenário inicial `cheatsheet_keybinds_keep` pré-carregou o calendário salvo na sessão antes de abrir Atalhos. Ele é mantido como **Calendário pré-carregado → Atalhos** e não como comparação pura de cache de Atalhos. As repetições `repeat_keybinds_keep/unload` usaram a mesma aba desde o pré-carregamento.

## Referências técnicas

- [Qt — desempenho de Qt Quick](https://doc.qt.io/qt-6/qtquick-performance.html): custo de objetos, bindings, imagens e criação por demanda.
- [Qt — Loader](https://doc.qt.io/qt-6/qml-qtquick-loader.html): ciclo de vida do objeto carregado.
- [Qt — gerenciamento de memória JavaScript](https://doc.qt.io/qt-6/qtqml-javascript-memory.html): coleta incremental e alocação da engine.
- [NVIDIA — consultas NVML](https://docs.nvidia.com/deploy/nvml-api/group__nvmlDeviceQueries.html): memória e utilização por processo.
