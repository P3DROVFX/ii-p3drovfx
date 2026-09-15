# Pendências após a revisão das duas rodadas

Nenhum novo ensaio está em execução ou agendado por esta revisão. Foram reavaliados 46 registros de cenário, com limites por caso. **Ter um A/B de remoção ou ler um contrato de serviço não encerra a investigação causal nem valida uma otimização funcional.** Prioridades em [PRIORIDADES.md](PRIORIDADES.md); diferenças e interferências em [testes-ab.md](testes-ab.md).

O plano operacional agora está em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md): variantes, controles, duração, métricas, interpretação e critério de encerramento. **Os IDs desse plano ainda não são novos casos implementados no supervisor.** Esta atualização documentou o trabalho; não iniciou ensaios nem adaptou o código de produção ou da bancada.

A ordem imediata é **A0 (extrair séries/helpers dos dados existentes) → T0 (corrigir validade/instrumentação) → um par de M1 para CPU ou N1 para RAM**. Uma triagem de dois processos leva 6 min 30 s programados no protocolo genérico; a confirmação A–B–B–A leva 13 min, além de boot/preparação/restauração. Encerrar e relatar cada lote antes de escolher outro.

## 1. Próximas perguntas, com critério de encerramento

| Plano | Prioridade | Pergunta | Estado atual | Próximo passo / critério de encerramento |
|---|---|---|---|---|
| [A0](PROXIMOS-TESTES.md#a0) | **Imediata, offline** | O que as séries existentes revelam além das medianas? | Dados por processo, fase, mapas e MPRIS já preservados. Análise suplementar ainda não feita. | Gerar séries e tabela de helpers com identidade de PID; localizar quando a memória cresce e quem mantém CPU. Não atribuir threads à rodada 2 sem nova coleta. |
| [T0](PROXIMOS-TESTES.md#t0) | **Pré-requisito de novos pares** | Como impedir outra comparação interferida? | Seleção por índice, MPRIS incompleto e agregação sem ciclo persistem no runner. | Validar identidade da aba, áudio/player efetivo, seeds/revisões iguais, IDs de réplica/ciclo e recuperação. Pilotar instrumentação e medir overhead. |
| [N1](PROXIMOS-TESTES.md#n1) | **Alta RAM** | Quanto do editor de Notas pode ser adiado sem perder edição? | Remoção completa: −151,1 MiB no incremento; MPRIS diferente. Não separa editor/menus/IA. | Repetir par com reprodução igual; decompor ferramentas ocultas. Validar edição, autosave, reabertura e latência na implementação funcional. |
| [C1](PROXIMOS-TESTES.md#c1) | **Alta RAM** | O que explica o Calendário restante? | Remoção lateral/pickers: −52,6 MiB no incremento; grade ainda +275,8 MiB aberta / +231,9 MiB pós-GC. | Medir lateral e pickers separadamente, implementar carga tardia funcional e perfilar grade/dependências/heap residual. Não considerar todas as alocações resolvidas. |
| [M1](PROXIMOS-TESTES.md#m1) | **Alta CPU** | O que explica 57,5% de CPU própria na mídia sem visualizador/animação? | Há trabalho de Cava/listener sem demanda explícita, mas nenhuma atribuição de toda a CPU a eles. | A/B separado de serviço e listener; perfil QML/nativo. Exigir queda reproduzível e funcionamento dos outros consumidores. |
| [F1](PROXIMOS-TESTES.md#f1) | **Alta contínua** | Por que a família sem cache usa 33,0% de um núcleo no idle? | Novo resultado após navegação com reprodução; VRAM permanece 222,9 MiB. | Isolar widgets/serviços e playback, contabilizar árvore e compositor separadamente. Identificar o trabalho que permanece e medir correção. |
| [B1](PROXIMOS-TESTES.md#b1) | **Alta anomalia** | Por que o layout único aumenta CPU na rodada 2? | Rodada 1: −5,3 pontos; rodada 2: +11,8. RAM também varia entre pares. | Repetir A/B alternando ordem, com estado idêntico, perfilar fase aberta e cada widget. Não atribuir a oscilação transitória sem evidência. |
| [D1](PROXIMOS-TESTES.md#d1) | **Alta anomalia** | Por que Dashboard sem cache termina maior? | −91,2 MiB antes de abrir; +50,0 aberto / +48,7 após GC. IA, diferentemente, converge. | Perfil por card e ordem de inicialização; repetir até separar estado/variabilidade de efeito causal. |
| [F1](PROXIMOS-TESTES.md#f1) | **Alta validade** | A navegação correta mantém a economia por mais tempo? | −131,8 MiB idle / −135,3 GC em sequência curta; fase Phone seleciona índice do Tradutor no snapshot e uma fase MPRIS divergiu. | Selecionar/validar por identidade, incluir Phone real e demais painéis relevantes; manter reprodução igual, ampliar idle e ciclos. Medir latência junto de RAM. |
| [P1](PROXIMOS-TESTES.md#p1) | **Concluído** | Quanto Privacy e screen share podem economizar preservando detecção? | **Concluído em [achados-p1.md](achados-p1.md)**: 95,6% do tempo da sonda é gasto no `pw-dump` (PipeWire). O script `screensharestate.sh` foi identificado como observador redundante. A variante unificada (`p1_unified`) eliminou o loop bash e economizou ~3,4 p.p. de CPU de helpers. | Adotar observador unificado no produto; substituir polling de `pw-dump` por listener orientado a eventos. |
| [R1](PROXIMOS-TESTES.md#r1) | **Seguinte** | IA, Phone e Overview retêm quais alocações? | Medições completas de painel; IA converge entre modos, porém sem cache ainda +142,0 MiB pós-GC. | Atribuir singletons, UI, dados e arenas com perfil; testar conteúdo grande e crescimento por ciclo. |
| [P1](PROXIMOS-TESTES.md#p1) | **Seguinte** | Quais serviços devem sobreviver à UI? | Contratos inventariados por código, não todos medidos causalmente. | Matriz consumidores/operações para LocalSend, KDE Connect, Privacy, ResourceUsage e outros; testar encerramento sem quebrar tarefas de fundo. |
| [H1](PROXIMOS-TESTES.md#h1) | **Seguinte** | Avisos de Dock e NetworkToggle afetam recursos? | Um binding loop em Dock e aviso de atribuição em NetworkToggle em cada navegação; Dashboard também tem atribuição. | Inspecionar dependências e frequência real. Não tratar uma linha de log como prova da causa da CPU/RAM. |
| [G1](PROXIMOS-TESTES.md#g1) | **GPU** | Qual recurso mantém VRAM/atividade? | Mídia separou duas opções juntas; família mantém 222,9 MiB com/sem cache. | Separar efeitos, superfícies, imagens e widgets; validar timestamps NVML e medir CPU junto, sem capturas de tela. |
| [H1](PROXIMOS-TESTES.md#h1) | **Atribuição profunda** | Quais pilhas explicam o custo restante? | perf/heaptrack encontrados; nenhum perfil lançado. QML Profiler não localizado nos caminhos consultados. | Integrar o profiler ao único processo supervisionado, conferir permissões/símbolos e overhead; publicar pilhas pertinentes com limites. |
| [E1](PROXIMOS-TESTES.md#e1) | **Confirmação da meta** | O ganho aproxima o fork do end-4 depois do uso? | Comparação end-4 só na rodada 1; boot integral ainda não comparado. | Mesma sequência e funções comuns, mais cenário separado para extras; RAM/CPU/VRAM/latência e repetições. |

## 2. Estabilidade, caches e alocações

Protocolos detalhados: [R1 — ciclos e dados](PROXIMOS-TESTES.md#r1), [H1 — pilhas e threads](PROXIMOS-TESTES.md#h1).

- **Vazamento versus retenção:** pelo menos 20 ciclos com mesmo conteúdo e fases identificadas por ciclo; janelas prolongadas após fechar. Procurar crescimento por ciclo que não estabiliza. As atuais duas aberturas não respondem essa pergunta.
- **Heap nativo/QML:** obter pilhas de alocação e destruição com ferramenta disponível, iniciando o processo sob o profiler quando exigido. QML Profiler requer suporte de debug no lançamento; medir seu overhead em execução separada. Não usar números sob profiler como baseline direto de produção.
- **Referências globais:** mapear quais singletons são tocados por cada painel e quando dados/modelos são limpos. Categorias anônimas em `smaps` não identificam automaticamente QObject, pixmap ou fragmentação.
- **Imagens/texturas:** medir pixmaps decodificados, capas, wallpapers, thumbnails, previews e limites/evicção de cache, com quantidades e resoluções conhecidas. Diferenciar cache em disco, page cache, heap e VRAM; não apagar caches pessoais para produzir uma comparação artificial.
- **Calendário com dados variados:** mês/semana, agenda vazia/grande, eventos recorrentes, múltiplos calendários, anexos, edição e troca de datas. Medir `eventDetailsByUid` e cópias derivadas antes/depois da sincronização.
- **Efeito do histórico:** comparar processo novo, uso normal, muitas trocas de painel e hot-reloads. O perfil da primeira auditoria tinha mudanças de código; não isola a causa da retenção por reload.
- **Alocador:** só depois de identificar o proprietário das alocações, avaliar fragmentação/liberação de arenas. GC de JavaScript não substitui essa análise. Não há benefício comprovado de trocar alocador ou forçar coleta periódica.

## 3. Cobertura de interface que falta

Há medições de 16 módulos/páginas principais. O [inventário da primeira auditoria](../audit-2026-09-08/module-inventory.md) continua sendo a lista de navegação do código; a existência de uma linha lá não indica teste runtime individual.

| Área | Já medido | Ainda sem isolamento suficiente |
|---|---|---|
| Dashboard | Painel completo com/sem cache | Cada card, aba, gráfico, integração e popup interno; conteúdo ativo versus vazio. |
| Policies | IA e Phone | Translator, player, wallpapers, weeb e outras políticas habilitáveis; conversas longas, streaming, downloads e mídia ativa. |
| Cheatsheet | Calendário mensal, Atalhos e Comandos | Email, demais abas, mapas/edição de teclado, Typing Test, calendário semanal, formulários, anexos, editor/busca e navegação entre todas as abas. |
| Settings | Cores e Barra | Outras páginas, índice de busca, muitos resultados, preview de temas/wallpapers e sequência longa de navegação. |
| Barra | Vertical completa; layout ativo; Privacy off | Horizontal, modos alternativos, cada widget/popup, bandeja, controles, notificações, áudio, rede/VPN e recursos; diferentes arranjos. |
| Background | Fundo + conjunto de widgets | Cada widget do desktop, janela de widgets vazia, diferentes wallpapers/resoluções, capas e fontes de vídeo. |
| Media Mode | Rodada 1 interferida; rodada 2 com Playing registrado por fase | Animação, visualizador, serviço Cava e listener separadamente; letras, vídeo, capas e modos; fixar playback continuamente. |
| Overview e Dock | Módulos completos | Capturas ao vivo on/off, hover/previews, muitas janelas, pesquisa, lançador e conteúdo interativo. |
| Notas, Usage, Wallpaper Selector | Abertura/fechamento principal | Bases grandes, imagens/anexos, gráficos longos, busca, edição e repetição de navegação. |
| Outros módulos do shell | Inventário estático | OSD, notificações/histórico, clipboard, overlays, menus, launcher, lock/session, controles e integrações não contemplados nos IDs da bancada. |

Catálogos de IDs do supervisor são seleções de cenários, não cobertura automática de todos os componentes. O runner final da rodada 2 é uma versão histórica distinta do pacote reutilizável. Adicionar novos casos somente com estado aberto verificável e limpeza definida.

## 4. CPU, GPU e ambiente

- **MPRIS controlado:** os A/B históricos só registraram reprodução antes de algumas execuções. A rodada 2 registrou por fase e revelou diferenças em Notas e navegação; isso ainda não fixa o estado. Registrar código de saída/stderr sanitizado para distinguir saída vazia de playback pausado. Para causalidade, usar uma fonte estável e confirmar player/estado/conjunto de helpers durante todas as fases.
- **Capturas ao vivo:** separar custo de `ScreencopyView` de animações/bindings no Overview e Dock; medir quantidade de janelas e taxa de atualização, além de CPU/GPU do compositor.
- **VRAM:** separar superfícies, buffers de swapchain, texturas e efeitos; investigar barra com superfície de tela inteira e janela adicional do Background. Ainda não há atribuição de bytes gráficos a cada recurso Qt.
- **Atividade gráfica:** a média SM atual é uma aproximação por amostras NVML. Falta agregação ponderada por timestamp e avaliação de encoders/decoders, transferências e frames. Não inferir energia ou watts de SM/VRAM.
- **Carga externa:** registrar interferência de outros aplicativos, frequência/energia/temperatura; repetir pares na mesma condição. Uso global da GPU não pertence automaticamente ao Quickshell.
- **Latência e fluidez:** medir tempo até primeiro frame útil, reabertura e p95/p99 de frame quando aplicável. Os números atuais de RAM não demonstram que desligar cache preserva a experiência.
- **Outras condições:** bateria/tomada, 60/120 Hz, HiDPI, múltiplos monitores, desconexão de tela, suspend/resume e reprodução de vídeo. AMD/Intel precisam de telemetria específica; o coletor atual é NVIDIA.

## 5. Comparação equivalente com o end-4

1. Executar o boot completo dos dois shells em snapshots, separando custo do `shell.qml` e da família visual. A bancada atual mede a família e dependências demandadas.
2. Definir uma matriz de funções equivalentes; comparar também defaults próprios de cada versão. O mesmo JSON não habilita necessariamente as mesmas funções.
3. Resolver ou explicar os avisos do original nessa versão de Qt/Quickshell, preservando uma referência original documentada. Não mascarar uma falha removendo funcionalidades sem registrar.
4. Usar os mesmos dados, wallpaper, fontes, resolução, reprodução, janela temporal e estado frio/quente; alternar ordem e repetir.
5. Separar custo de recursos adicionados do custo evitável. Os 587,7 MiB de diferença de PSS entre famílias não foram decompostos integralmente.

## 6. Serviços online e auxiliares transitórios

O isolamento de rede foi intencional e limita conclusões sobre custo online. Faltam ciclos completos e controlados de VPN, email/calendário remoto, Drive/rclone, letras, IA, sincronização de telefone e transferência de arquivos. Usar dados de teste e respostas controladas quando possível; preservar as restrições de envio/publicação da conversa.

Medir início, sucesso, erro, timeout, cancelamento e concorrência. Consultas de ProtonVPN de 103 MiB e auxiliares de email de longa residência são observações da sessão real, ainda sem um A/B da solução proposta. Processos desacoplados da árvore ou que nascem e somem entre amostras precisam de rastreamento complementar para atribuição completa.

## 7. Pendências do ferramental

[T0](PROXIMOS-TESTES.md#t0) define as alterações mínimas e suas evidências de aceitação. As lacunas abaixo continuam abertas até implementação e piloto; documentar uma exigência não a torna disponível no script.

- **Piloto do pacote reutilizável:** houve 15 execuções adicionais com um runner derivado e alterado. Isso não valida automaticamente a versão genérica empacotada. Preservar a distinção entre as versões e verificar um piloto finito quando houver uma nova coleta.
- **Falhas parciais:** salvar amostras incrementalmente e em qualquer exceção; hoje nem toda interrupção preserva o resultado parcial, e uma falha antes de criar o diretório pode prejudicar o registro de `failed.json`.
- **Recuperação verificável:** `restored: true` histórico registra o caminho de restauração executado; confirmar também PID/config/saúde real da instância. Ampliar testes do supervisor para crash, timeout, sinal, disco cheio e reinício abrupto.
- **Exclusão entre supervisores:** há checagem de uma instância e `--no-duplicate`, mas falta lock exclusivo de bancada e tratamento de gerenciador externo que relance produção durante o ensaio.
- **Fases e ciclos:** validar `stages.json` antes de interromper produção; o formato atual agrega pelo nome da fase. Para 20 ciclos, adicionar identidade de ciclo no driver, amostras e agregador, sem misturar todas as aberturas numa só estatística.
- **Validação automática:** além de `Loader.Ready`, conferir aba/flag/superfície esperadas e classificar erros. A navegação da rodada 2 repetiu o problema de usar índice sem validar a identidade da aba; emitir `policyIcon` também nos cenários de família. Um loader pronto não garante que o conteúdo solicitado está aberto.
- **Snapshot reproduzível:** registrar hashes de código e diferenças locais, versão de todos os scripts, tamanho dos conjuntos de teste, dependências, estado energético e configuração reduzida sem segredos. SHA sozinho não registra trabalho não commitado.
- **Adaptação de máquina:** remover suposições de monitor, API Hyprland, GPU 0, caminhos e configuração de usuário; testar a preparação com symlinks diferentes, diretórios ausentes e submódulos já inicializados.
- **Relatório:** o gerador produz tabelas/hashes, não causalidade. Adicionar metadados estruturados de validade, interferências, dispersão de repetições e comparações; manter revisão humana/modelo antes de concluir.
- **Retenção da bancada privada:** decidir com o usuário quando arquivar ou remover snapshots/logs contendo dados pessoais. Nenhuma remoção foi feita nesta consolidação; não publicar a pasta privada.

## 8. Ponto de retomada

Ler primeiro [prioridades](PRIORIDADES.md), [A/B revisados](testes-ab.md) e este backlog. A rodada 1 está em `data/`, `summary.json` e `manifest.json`; a rodada 2 em [round2/](round2/README.md), com IDs independentes. Não substituir um resultado antigo por outro de mesmo nome sem indicar a rodada.

As bancadas privadas permanecem em `/home/pedro/.local/state/ii-controlled-audit-20260908` e `/home/pedro/.local/state/ii-controlled-audit-round2`. Contêm dados pessoais e logs; os artefatos compartilháveis foram preservados separadamente. Não publicar a pasta privada nem ficar aguardando os scripts encerrados.

Escolher uma pergunta da tabela e seu protocolo em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md); seguir o [guia](GUIA-DE-AUDITORIA.md) para executar. Usar primeiro A0/T0 e um par pequeno, sem relançar todo o catálogo. Para RAM, priorizar decomposição funcional de Notas/Calendário; para CPU, Media Mode e trabalho contínuo da família. Nenhuma alteração de produto foi feita por esta revisão documental.
