# Como executar a auditoria e escrever o relatório

Este guia permite repetir a bancada em outra sessão deste computador. Ele não autoriza, por si só, parar o shell de outro usuário: confirme a autorização na conversa. Nesta auditoria houve autorização explícita para interromper a instância e operar uma sessão controlada. Respeite sempre a proibição de IPC do Quickshell e de capturas de tela.

## 1. Arquivos e responsabilidades

| Arquivo | Uso |
|---|---|
| `tools/prepare.py` | Copia código/configuração/estado/cache para diretório privado; não inicia nem para o shell. |
| `tools/runner_template.py` | Supervisor e driver QML; `prepare.py` o instala como `run.py` na bancada. Não executar diretamente dentro do repositório. |
| `tools/cases.json` | Catálogo de IDs e opções de cada cenário. |
| `tools/proc_reader.py` | Leitura de `/proc`, árvore de processos e categorias de memória. |
| `tools/build_report.py` | Gera tabelas, JSON de resumo, validação de superfícies e hashes dos dados. Não gera conclusões automaticamente. |
| `tools/bar-active-layout-prototype.diff` | Demonstra exatamente a alteração experimental dos Repeaters. Não é uma correção aplicada ao shell. |
| `tools/historical/` | Scripts exatos das rodadas originais; preservados para rastreabilidade. |
| `data/<id>/measurements.json` | Amostras, marcadores, categorias de memória e superfícies de cada ensaio desta auditoria. |

Os scripts históricos foram executados. A versão reutilizável foi revisada e validada por sintaxe/consistência, mas **não recebeu uma nova execução completa depois de empacotada**, para atender ao pedido de encerrar as rodadas. Faça um cenário piloto antes de uma auditoria nova.

## 2. Pré-requisitos e verificação inicial

São necessários Python padrão, `qs`, `bwrap`, `cp` com reflinks, `git`, `tar`, `hyprctl`, `playerctl`, `/proc` legível e a biblioteca `libnvidia-ml.so.1`. NVML torna o coletor atual específico para NVIDIA; AMD/Intel precisam de um adaptador de telemetria. O driver não implementa fallback silencioso para GPU ausente.

Use o terminal da sessão Wayland do próprio usuário. Verifique `qs list --all --no-color` e `pgrep -x qs`; deve haver **uma única instância de produção**. O supervisor identifica seu PID e início do processo e aborta se houver ambiguidade. Verifique os monitores com `hyprctl -j monitors` e ajuste `eDP-1` no driver caso necessário.

O harness usa as APIs Lua de Hyprland 0.56 (`hl.dsp.focus({ workspace = ... })`). Versões anteriores podem exigir adaptar os comandos de troca e restauração de workspace. Não use `hyprctl reload` para reiniciar o shell.

Leia `git status --short` e registre o commit de ambos os códigos. A cópia preserva as alterações locais; um SHA sozinho não identifica modificações não commitadas. Não faça restore/reset/checkout na árvore live para “limpar” um teste.

Antes de um lote grande, registre o estado de reprodução dos aplicativos, a resolução/escala/refresh, energia e carga externa. Congele as variáveis do A/B: mesma aba, mesmo conteúdo, mesma reprodução, mesmo cache inicial. “PC parado” não impede um dispositivo MPRIS de começar a tocar.

## 3. Preparar a bancada

Execute a partir da raiz do ii. Escolha **um diretório novo em disco**, fora do código live. `/tmp` e `/run/user/1000` são tmpfs neste sistema e distorcem a contabilização de RAM se usados para os snapshots.

```bash
python3 docs/performance/audit-2026-09-08-controlled/tools/prepare.py \
  --output /home/pedro/.local/state/ii-audit-NOVA-SESSAO
```

O comando recusa um diretório existente. Para caminhos diferentes, use `--source /caminho/do/ii` e `--upstream /caminho/do/end4/ii`.

A preparação copia a fonte, os dados `illogical-impulse`, o estado e cache do Quickshell, e a configuração global Qt/KDE. Há arquivos pessoais e possivelmente credenciais nesses snapshots: o diretório tem modo 0700. **Nunca adicione `seed-*`, `run-*`, `config-root`, `private.log` ou o snapshot inteiro ao Git/relatório.** Nesta máquina a preparação inicial ocupou aproximadamente 2,6 GB lógicos; cópias por cenário aumentam o total lógico. Reflinks podem reduzir a ocupação física.

O end-4 requer o submódulo `rounded-polygon-qmljs`. Se estiver vazio, a preparação tenta extrair a revisão fixada usando o objeto já disponível no clone local do fork. Se não encontrar o objeto, ela para antes de tocar na sessão. Não substitua por uma versão arbitrária.

A cópia inclui `VerticalBarAudit.qml` e `VerticalBarContentAudit.qml`, variantes apenas para o A/B de layout. A preparação valida os dez padrões esperados; se o código mudar, adapte o experimento em vez de ignorar a falha.

## 4. Rodar um piloto e depois um lote

Veja os IDs em `cases.json`. O supervisor reutilizável exige IDs explícitos; sem argumentos ele não para o shell. Não execute duas bancadas ao mesmo tempo.

```bash
python3 /home/pedro/.local/state/ii-audit-NOVA-SESSAO/run.py dashboard_keep \
  > /home/pedro/.local/state/ii-audit-NOVA-SESSAO/progress.log 2>&1
```

O comando fica em primeiro plano ou em uma sessão de terminal **supervisionada pela ferramenta**, com PID/identificador conhecido e timeout suficiente. Não use `qs -p arquivo.qml &`, `nohup qs` de teste ou uma instância extra por módulo. O supervisor cria um único `qs -c ii` por vez dentro da sandbox e encerra sua árvore antes do próximo.

Depois de validar o piloto, rode os outros IDs na mesma preparação, desde que ainda não existam resultados para eles:

```bash
python3 /home/pedro/.local/state/ii-audit-NOVA-SESSAO/run.py \
  dashboard_unload policies_ai_keep policies_ai_unload phone_only \
  repeat_keybinds_keep repeat_keybinds_unload repeat_timetable \
  overview settings_colors settings_bar usage notes wallpaper_selector \
  > /home/pedro/.local/state/ii-audit-NOVA-SESSAO/progress-paineis.log 2>&1
```

Um conjunto separado compara variantes e famílias:

```bash
python3 /home/pedro/.local/state/ii-audit-NOVA-SESSAO/run.py \
  bar_reference bar_active_layout bar_no_privacy \
  media_reference media_static family_fork family_fork_no_prewarm family_upstream \
  > /home/pedro/.local/state/ii-audit-NOVA-SESSAO/progress-comparacao.log 2>&1
```

Uma repetição do **mesmo ID** exige outra preparação, para preservar os resultados anteriores. `core/controller/open/closed/reopen/closed_again/unloaded/gc` somam 195 segundos por cenário na versão reutilizável, mais preparação e boot. Dez cenários levam pelo menos 33 minutos. Planeje um lote pequeno com objetivo definido; não execute todo o catálogo sem necessidade.

Para outros tempos, crie `stages.json` na raiz da bancada antes de iniciar. Exemplo de uma primeira passagem sem reabertura/GC:

```json
[
  {"phase":"core","seconds":20},
  {"phase":"controller","seconds":20},
  {"phase":"open","seconds":30},
  {"phase":"closed","seconds":30},
  {"phase":"unloaded","seconds":20}
]
```

Mantenha ao menos 15–20 s por fase e registre os tempos usados. Os primeiros cinco segundos são descartados do resumo. Para provar vazamento, use mais ciclos e janelas de minutos, sem confundir esse protocolo com um ensaio curto de carga/descarga.

## 5. O que o supervisor faz

1. Registra PID, identidade dos processos, hash do config e commit em `recovery.json`.
2. Encerra a instância normal e os auxiliares identificados. Não usa um `pkill -f` amplo.
3. Muda para um workspace vazio temporário.
4. Restaura cópias de dados de referência antes de cada cenário.
5. Inicia Bubblewrap com filesystem original somente leitura, cópias graváveis, namespace de PID e rede isolada. `/tmp` é privado; GPU/Wayland/DBus/PipeWire locais continuam acessíveis.
6. Carrega o driver QML e avança por temporizadores internos. Não chama IPC do Quickshell.
7. Amostra `/proc` e NVML, guarda marcadores QML e inventários de superfícies sem títulos/conteúdo de janelas.
8. Encerra a árvore do teste. Um watchdog detecta travamento e falha de carga.
9. No `finally`, encerra qualquer teste ainda ativo, restaura o workspace e inicia uma única instância normal, com `--no-duplicate`.

`SIGINT`/`SIGTERM` do **supervisor Python** passam pelo `finally`. Não mate o supervisor com SIGKILL se quiser essa recuperação. Em um desligamento abrupto, use `recovery.json` para identificar os processos; confira instâncias e recupere o shell pelo procedimento oficial do projeto. Nunca inicie produção antes de confirmar que a bancada terminou.

O script atual salva `failed.json` para cenários interrompidos, mas não serializa todas as amostras parciais em qualquer exceção. Essa limitação é registrada em PENDENCIAS.md. Não use uma tentativa incompleta como resultado válido.

## 6. Acompanhar sem desperdiçar chamadas ou tokens

O `progress.log` registra transições e o fim de cada cenário. A execução é autônoma; ler o log não faz o teste avançar. Não consulte o arquivo a cada poucos segundos nem releia o mesmo código enquanto aguarda. Faça a documentação/análise independente que estiver pendente e depois use a conclusão da sessão de terminal como sinal para examinar o lote.

Ao retomar, verifique uma vez se o comando terminou e leia somente as últimas transições/resumos. Se o usuário pedir apenas consolidar os dados, **não inicie novas medições**. Não transforme cada resultado em outro A/B sem um objetivo e um critério de término definidos.

## 7. Validar os dados antes de escrever conclusões

Em `results/<id>/measurements.json`, confira:

- Todas as fases previstas e amostras suficientes, com PID/identidade contínuos.
- `Loader.Ready` (`status=1`), item existente e flag aberta nos marcadores `settled`.
- Superfície correspondente em `surfaces.open`, ausente em `surfaces.closed`, exceto módulos que devem continuar residentes, como Background no teste de Media Mode.
- Aba real (`cheatTab`, `policyIcon`, `currentPage`), não apenas a função que foi chamada.
- Erros de QML no log privado: distinguir erro de rede esperado, aviso compatível e componente que não carregou.
- `playbackByPhase` na versão reutilizável. A versão histórica só registrou MPRIS antes de alguns A/B; isso foi insuficiente para excluir mudanças durante o teste.
- Existência de helpers novos, retornos NVML e mudança na carga externa.
- Restauração no fim do lote, hash original do config e uma única instância normal. Uma sessão posterior/reboot não deve ser confundida com o PID restaurado pelo experimento.

Cache ligado precisa da **mesma aba inicial** do teste sem cache. O primeiro `policies_phone` foi invalidado porque o SwipeView voltou à IA. O teste foi substituído por Phone como única política ativa. A versão reutilizável remove esse caso inválido do catálogo.

## 8. Gerar tabelas e escrever o relatório

```bash
python3 /home/pedro/.local/state/ii-audit-NOVA-SESSAO/build_report.py
```

Saídas em `report/`: `medicoes.md`, `summary.json`, `manifest.json`, `validacao.json` e cópias dos dados por cenário. O gerador não lê conversas, senhas, títulos de janelas nem logs privados. Ele gera números; **não determina se um A/B é causalmente válido**.

Escreva primeiro `auditoria.md` com:

1. Resultado principal, versões, condições e abrangência.
2. Tabela por módulo: antes, aberto, fechado, descarregado; RAM, CPU e VRAM.
3. Diferenças incrementais, sempre nomeando a referência.
4. Comparações de cache e A/B, com variáveis alteradas e interferências.
5. Quais dados foram descartados e por quê.
6. Limites: serviços compartilhados, comportamento de GC/allocator, intervalo de observação e compatibilidade.

Depois escreva `melhorias.md`, separando ganhos medidos de hipóteses, e `PENDENCIAS.md`, com experimento, variável controlada, métrica e critério de conclusão de cada item.

Use MiB e explique RSS/PSS. CPU 100% equivale a um núcleo lógico. Não some módulos isolados. Não use GPU global como GPU do shell. Não chame todo saldo após fechar de vazamento. Não extrapole uma redução de boot para uma sessão que já visitou todas as telas.

Para publicar no repositório, copie apenas `report/` e os scripts sem dados pessoais. Revise links, hashes, tabelas, origem dos números e estado Git. As conclusões textuais precisam ser reescritas para os novos dados; não copie percentuais desta auditoria como se fossem permanentes.

## 9. Adicionar um módulo ou experimento

Use uma preparação nova. Altere somente o driver/código da cópia e registre o diff exato. Em `run.py`, cada entrada de `CASES` possui `id`, `path` relativo ao ii e `kind`. As opções adicionais controlam intervenções como `keep`, `tab`, `samePrewarm`, `policyOnly`, `noPrivacy`, `staticMedia`, `productionConfig` e `upstream`. Atualize o catálogo JSON junto do supervisor; editar somente `cases.json` não muda o driver.

`DRIVER` contém o QML do harness. `load()` instancia o caminho por URL; `open()` e `close()` mudam os estados globais correspondentes ao `kind`; `next()` executa as fases. Para um novo painel, leia primeiro seu host e `GlobalStates.qml`, acrescente um ramo de abertura/fechamento e um marcador que confirme a aba ou conteúdo real. Não substitua todos os serviços por mocks se o objetivo é medir seu custo real; se usar fixtures/mocks para controle, declare quais custos foram excluídos.

Para um widget interno, crie na cópia um host mínimo compatível com suas propriedades e janela. Compare esse host vazio, host com widget e host após destruição. Muitos widgets precisam de propriedades do pai, singletons ou estado de reprodução: falha de construção não é consumo baixo. Use a mesma superfície nas variantes quando quiser isolar apenas o conteúdo.

`mark()` registra estado sem conteúdo pessoal; `snapshots()` lê apenas metadados de superfícies. Acrescente uma condição objetiva de validade para o novo caso e confira o log privado. O teste histórico de Phone demonstra por que `Loader.Ready` sozinho é insuficiente.

`summarize()` calcula medianas e CPU após cinco segundos de acomodação; `build_report.py` apresenta as fases conhecidas. Para muitos ciclos, acrescente identidade de ciclo à amostra e ao agrupamento antes de repetir nomes de fase. Sem isso, o resumo mistura todos os períodos chamados `open` e inclui intervalos intermediários na CPU.

Ao interpretar um A/B, registre o que mudou além da opção pretendida: configuração derivada, serviços criados, reprodução, cache e superfícies. Calcule a diferença entre pares equivalentes; faça repetições antes de chamar um ganho pequeno de estável. Só amplie o catálogo depois que o piloto provar carregamento, fechamento e restauração.

## 10. Reconciliar rodadas novas antes de mudar o ranking

A [rodada 2 preservada](round2/README.md) é um exemplo de resultados que exigiram revisão das conclusões. Para analisar material já concluído, não interromper a produção nem relançar cenários: ler manifestos, amostras, variantes e marcadores.

1. Separar cada rodada em seu diretório. Um mesmo `case.id` pode ter valores distintos por revisão/protocolo; manter a origem em tabelas e JSON. O `stages.json` final de um runner pode representar somente o último lote: usar `measurements.json.stages` de cada caso.
2. Recalcular medianas e CPU com o mesmo descarte temporal; subtrair antes de arredondar. Informar diferença absoluta (`open_B − open_A`) e diferença de incrementos (`(open_B − controller_B) − (open_A − controller_A)`). Não dividir diferença de árvore por incremento só do processo.
3. Ler o diff da variante. Substituir editor/picker por `Item` com métodos vazios mede remoção de funcionalidade, não carga tardia funcional. Uma proposta de Loader precisa preservar a função e respeitar seleção automática/referências existentes.
4. Conferir identidade da aba também nos cenários de família. Índice 1 não significa sempre Phone. Em uma futura versão, selecionar pelo identificador estável e exigir marcador da aba esperada; não alterar os IDs ou amostras históricos para ocultar a falha.
5. Registrar MPRIS por fase e distinguir saída vazia, ausência de player e erro do comando. Guardar código de saída e erro sanitizado; uma consulta por fase não equivale a fixar reprodução. Revisar também os pares de RAM, não apenas os de mídia.
6. Tratar regressões de outras métricas como achados: economia de RAM com CPU maior, boot menor com pós-uso maior, menos auxiliares com maior RAM total. Não explicar anomalias por renderização/ruído sem perfil ou repetição.
7. Distinguir saldo pós-GC de vazamento/permanência. Explicitar duração, ciclos, conteúdo visitado e janela útil; GC só trata parte das alocações. Observação curta não mede horas de uso.
8. Atualizar `PRIORIDADES.md`, investigação, A/B, pendências e abertura da auditoria. Um item passa de “não medido” para “medido parcialmente”, “anomalia” ou “implementação a validar”; não marcar toda uma área resolvida por um único par.

Conferência offline da rodada 2 preservada (sem iniciar shell ou tocar na sessão):

```bash
python3 docs/performance/audit-2026-09-08-controlled/round2/verify.py
```

O runner final preservado em `round2/historical/` é evidência histórica, com fases/seleção que precisam das correções acima; não substitui o procedimento de preparação e piloto. O relatório não deve concluir saúde atual da produção a partir de um PID restaurado numa rodada antiga.

## 11. Executar a próxima investigação planejada

O roteiro atual é [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md), com o estado de cada frente em [PENDENCIAS.md](PENDENCIAS.md). A0 usa resultados existentes sem reiniciar a sessão; T0 prepara a validade/instrumentação; M1/N1/C1 e os demais descrevem variantes futuras. **Não passar esses IDs de planejamento ao `run.py`: não estão implementados no catálogo.** Os comandos da seção 4 continuam exemplos dos casos existentes.

Para começar um lote novo:

1. Escolher uma pergunta e duas variantes; declarar funções preservadas/removidas, entrada e métrica de decisão. Preparar snapshot privado novo e conferir o código atual contra o histórico.
2. Implementar as adaptações de T0 relevantes ao par, o diff da variante e um marcador que confirme o alvo real. Acrescentar o ID ao driver e ao catálogo; mudar só `cases.json` não altera o comportamento do runner.
3. Validar fases/IDs antes de qualquer interrupção da produção. Fazer um piloto finito, com coleta incremental e recuperação verificável. Fixar o seed, player realmente selecionado e áudio de entrada; o isolamento atual ainda compartilha DBus/PipeWire.
4. Executar dois processos novos para triagem, analisar, depois A–B–B–A para confirmar somente se o resultado justificar. Conservar seeds idênticos: preparações novas recopiadas do estado live podem diferir. O runner atual rejeita sobrescrever um ID; usar preparações distintas ou implementar `runId` antes de repetir.
5. Produzir resumo por fase e execução, séries/contadores, validação funcional e limites. Para ciclos longos, adaptar o agrupamento por ciclo antes de executar: o agregador atual combina fases pelo nome.
6. Atualizar resultado A/B, conclusão e pendência. Encerrar com dados incompletos/inconclusivos quando essa for a evidência, sem transformar toda discrepância em outro lote automático.

Protocolo curto do supervisor genérico: 195 s por execução, 6 min 30 s por par e 13 min por A–B–B–A, além do overhead. A sequência de 20 ciclos em R1 e perfis H1 usam outros tempos, declarados separadamente; o lote instrumentado não serve como baseline de consumo normal. `stages.json` pode alterar durações existentes, mas não implementa novas ações, seleção de aba ou identidade de ciclo.

Antes de usar perf/heaptrack, seguir [H1](PROXIMOS-TESTES.md#h1): presença no PATH não certifica suporte, permissões ou símbolos. Integrar ao processo de teste e manter encerramento supervisionado; não anexar heaptrack à produção. Não instalar ferramentas nem alterar permissões globais como efeito colateral de uma auditoria documental.
