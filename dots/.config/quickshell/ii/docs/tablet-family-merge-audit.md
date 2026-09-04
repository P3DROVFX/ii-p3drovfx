# Auditoria de merge — Tablet Panel Family → `dev`

> **Data:** 2026-09-03, revisto em 2026-09-04 · **Branch:** `agent/tablet-family-base`
> **Alvo:** `origin/dev` (já mesclada para dentro desta branch)
> **Documentos irmãos:** [`tablet-family-plan.md`](./tablet-family-plan.md) (o que foi
> construído) e [`tablet-family-audit.md`](./tablet-family-audit.md) (o que falta para isso
> ser um tablet).
>
> Este documento responde a uma terceira pergunta, que os outros dois não respondem:
> **o que falta para isto entrar na `dev` sem quebrar quem não usa tablet?**

---

## 1. Veredito

**Falta uma coisa: validar em hardware com toque** (§3, M2). Os outros dois bloqueadores
foram resolvidos em 2026-09-04.

O risco nunca esteve no `modules/tablet/` — isolado, coberto por um guarda automático, e
não carregado por nenhuma outra family — e sim nos **326 arquivos compartilhados** que a
branch toca fora dele. Esses foram exercitados: a `dev` foi mesclada para dentro, as três
families foram carregadas, e a `ii` foi percorrida superfície a superfície sem um único
erro de carga.

| Número | Valor |
|---|---|
| Commits à frente da `dev` | 124 (inclui o merge da `dev`) |
| Commits atrás da `dev` | **0** — a `dev` já está dentro |
| Arquivos alterados | 403 |
| Dos quais em `modules/tablet/` | 77 |
| **Fora de `modules/tablet/`** | **326** |
| Conflitos ao mesclar a `dev` | **0** textuais · **1** semântico, corrigido |
| Violações de camada | **0** (baseline vazia, guarda passando) |
| Suíte QML | **228 passam, 0 falham** |
| Contratos Python | 6 arquivos falham — **os seis também falham na `dev`** |
| Erros de carga na family `ii` | **0** |

---

## 2. O que foi feito nesta sessão

Seis itens levantados no uso real, cada um com commit e teste próprios.

| # | Sintoma relatado | Causa | Commit |
|---|---|---|---|
| 1 | Apps e botões da dock somem ao entrar numa workspace com programa | `autoHideOnOccupiedWorkspace` vinha ligado por padrão, e nada na tela dizia isso | `406b8b7a6` |
| 2 | Hub mode existe mas não há como testar | Gatilho é "carregando + 2 min sem toque", e tocar é o que o dispensa | `f6ef99f82` |
| 3 | "Raise keyboard when text field is tapped" nunca funciona | Quatro causas distintas com o mesmo sintoma silencioso | `45080b8e5` |
| 4 | Alças de toque não acompanham a janela e pulam ao soltar | Hyprland não emite evento para `movewindowpixel` | `d51115e96` |
| 5 | Grade da gaveta alinhada à esquerda | `GridView` deixa o resto da divisão como espaço morto à direita | `3be9519a6` |
| 6 | *(feature)* Live Draw | — | `6dd19c59f` |

E uma segunda passagem em 2026-09-04, com a Huion HS64 ligada:

| # | Sintoma relatado | Causa | Commit |
|---|---|---|---|
| 7 | O OSK continua não subindo, agora **com caneta conectada** | O daemon descartava qualquer dispositivo com "virtual" no nome — e o OTD chama o dele de "OpenTabletDriver **Virtual** Artist Tablet" | `8235d9eba` |
| 8 | *(pedido)* Avisar que os helpers não estão compilados | — | `ada5517c5` |
| 9 | *(pedido)* Pen mode: cursor de caneta e botões da caneta | — | `b142bc2c7` |
| 10 | *(auditoria P2)* Nenhuma UI para trocar de family | — | `6a2c0cae1` |

- **#7 é a causa raiz do item 3.** O filtro existe para o OSK não se fechar sozinho quando
  o usuário aperta uma tecla *dele* — essas chegam por um dispositivo que nós injetamos.
  Mas ele rodava antes da classificação e por nome apenas, então engolia a caneta inteira:
  `devices 0 0 6`, zero canetas, com um tablet funcionando. Agora o filtro roda **depois**
  da classificação e só vale para teclados e ponteiros, que são os únicos papéis que
  alguém sintetiza em nosso nome. Com o tablet ligado: `devices 0 2 6`.
- **#9 responde à pergunta sobre o OpenTabletDriver**: não é preciso integração nenhuma. O
  OTD repassa os botões da caneta como `BTN_STYLUS`/`BTN_STYLUS2` ordinários no dispositivo
  do tablet, que o daemon do teclado já observa. A alternativa — escrever combinações de
  teclas no `settings.json` do OTD e vincular essas combinações no Hyprland — são três
  arquivos que têm de concordar, e abrir a UI do próprio OTD reescreve o primeiro.

Detalhes que valem para quem for revisar:

- **#1** mudou um *default*. Um valor já gravado sempre vence um default novo, então há uma
  migração v17 que vira a chave nos arquivos existentes — sem ela a correção erraria
  exatamente quem relatou o problema.
- **#3** encontrou um bug real no daemon Rust: com `/dev/input` ilegível ou sem touchscreen,
  ele ligava o input method, emitia `activate` e nunca emitia `touch`. O shell esperava a
  correlação para sempre, e as quatro causas — helper não compilado, helper não redetectado
  sem restart, sem touchscreen, sem permissão — eram indistinguíveis. O daemon agora reporta
  `devices <t> <p> <m>` e `denied`, e a página de Settings transforma isso nas duas frases
  que separam os casos. **Nesta máquina o daemon reporta `devices 0 0 6`**: não há
  touchscreen nem caneta, e é por isso que o recurso parecia quebrado aqui.
- **#4** era a mesma causa dos dois sintomas: `hyprctl clients` só é relido em evento, e
  mover uma janela em pixels não gera evento nenhum.
- **#6** encontrou um **limite do Quickshell que vale documentar**: `Canvas.save(path)` não
  funciona, porque resolve o nome do arquivo contra a base URL do componente, que aqui é
  sempre `qs:`. Use `grabToImage` + `saveToFile("file://" + path)`. Está no `AGENTS.md`.

---

## 3. Bloqueadores de merge

Três, todos pequenos.

### M1 — ~~Trazer a `dev` para dentro~~ ✅ **feito em 2026-09-04**

`git merge origin/dev` correu **sem um único conflito textual**, com onze commits da `dev`
tocando quinze arquivos que esta branch também toca — `GlobalStates.qml`, `Config.qml`,
`shell.qml`, o chrome do edit mode, a Welcome.

> **`currentConfigVersion`**: a `dev` estava em **16** e a branch em **18** — sem colisão,
> e as migrações v17/v18 sobreviveram intactas. Se a `dev` andar de novo antes do merge
> final, **confira este número antes de qualquer teste**: duas numerações iguais colidem
> sem o git dizer nada.

**Ausência de conflito textual não é ausência de conflito semântico**, e o merge produziu
exatamente um. A `dev` acrescentou `test_bar_timer_widget_contract` lendo
`modules/ii/sidebarDashboard/pomodoro/CountdownTimer.qml`; esta branch moveu esse arquivo
para `modules/common/dashboardWidgets/timer` no `e24b18ccb`, para que a tablet family
pudesse usá-lo sem importar a ii. Nenhum dos dois lados estava errado e o git não viu nada
— o teste passou a levantar `FileNotFoundError`. Corrigido em `80ae9c306`.

É a mesma classe do que já tinha mordido em `10f4412e1`, e é o motivo de **procurar
consumidores dos caminhos antigos ser um passo do checklist, não uma sugestão**: essas
quebras falham *ao compilar ou ao abrir um arquivo*, não numa asserção, e é por isso que
passam despercebidas.

### M2 — Validar em hardware com toque e caneta 🔴 **o único que resta**

Metade disto destravou em 2026-09-04: a Huion HS64 está ligada e o daemon a enxerga
(`devices 0 2 6` — dois nós de caneta, nenhum touchscreen). O que continua sem validação é
tudo que precisa de um **dedo ou de uma ponta de caneta encostando na tela**, que nenhuma
ferramenta aqui pode simular.

```
[ ] Tocar um campo de texto com a caneta faz o teclado subir
[ ] hyprctl devices  →  lista uma seção "Touch Devices"   (ainda vazia nesta máquina)
[ ] Live draw: um traço de caneta varia de espessura com a pressão
[ ] Live draw: a ponta de borracha da caneta apaga sem passar pela bandeja
[ ] Live draw: com o desenho "mantido", tocar na tela chega ao aplicativo embaixo
[ ] Alças de janela: arrastar e soltar não dá salto nenhum
[ ] Pen mode: apertar o botão inferior da caneta e arrastar move a janela flutuante
[ ] Pen mode: o botão superior dispara a ação vinculada
```

O que **foi** validado em runtime, sem toque:

- dock persistente com uma janela aberta (screenshot);
- preview do hub mode (screenshot);
- grade da gaveta centrada — medida em pixels, centro do bloco 856 → 954 numa tela de 960;
- alças seguindo a janela depois de um `move` (a posição relatada acompanha o dispatch);
- tinta por workspace — 11 608 px de tinta na ws 2, 165 na ws 4, e de volta ao trocar;
- recorte e gravação do PNG, e a nota criada com o caminho certo;
- a janela de setup nos quatro estados, incluindo o build ao vivo com barra e contador;
- o cursor de caneta aplicado e restaurado (`hyprctl setcursor`), e o tema derivado gerado
  a partir do `pencil` do próprio tema do usuário;
- a family `ii` carregada e percorrida — bar, sidebars, overview, cheatsheet — com zero
  erros e nenhuma superfície de tablet vazando.

> Diagnóstico já embutido: Settings › Tablet › Pen diz "aperte uma vez para confirmar" ao
> lado do botão inferior, e `qs -c ii ipc call penMode status` reporta o último botão
> visto. Se ele continuar `-1` depois de apertar, o problema está entre a caneta e o
> daemon, não entre o daemon e o shell.

### M3 — ~~Os dois helpers Rust~~ ✅ **feito em 2026-09-04**

`scripts/osk/osk_autoshow` e `scripts/touchGestures/touch_gestures` são **fonte, não
binário** — corretamente ignorados pelo git. Numa instalação nova, nem gestos de toque nem
auto-show do teclado funcionavam até alguém compilar, e a única saída oferecida era colar
um comando num terminal: circular num aparelho cujo teclado é justamente o que falta.

Resolvido de forma mais completa que a opção que o rascunho previa. Os dois helpers
compartilham `services/RustHelperBuild.qml`, e a tablet family abre uma **janela na
primeira execução** quando algum deles falta — uma janela normal, sem escurecer o fundo,
na mesma forma da Welcome. Uma linha por helper com seu próprio botão, "Build both", e
"Do it later", que significa mais tarde: a dispensa é lembrada contra o *conjunto* de
helpers que faltava, então um helper diferente sumir depois é outro aviso e aparece de
novo.

O botão mostra progresso, porque um botão que diz "Building…" por um minuto é
indistinguível de um botão travado. O nome do crate vem da própria narração do cargo; o
denominador vem do `Cargo.lock`, que lista exatamente as unidades de um build limpo — 23
entradas para o daemon de gestos, e um build limpo reporta exatamente 23 crates. A linha
então vira seu estado final e a janela **fica aberta para mostrá-lo**, coisa que a
primeira versão não conseguia porque a linha se apagava no instante em que dava certo.

Também alcançável por `qs -c ii ipc call tabletSetup open|build|status`, para um script de
primeiro boot.

## 4. Polimento antes ou depois do merge

Nada aqui bloqueia, mas todos são coisas que um revisor vai notar.

| # | Item | Por quê | Esforço |
|---|---|---|---|
| ~~P1~~ | ~~Botão de build para `touch_gestures`~~ | ✅ feito — ver M3 | — |
| P2 | Sem UI para trocar de panel family em Settings ou Welcome | O `ShellSwitcher` existe e é alcançável por ação/gesto/bubble/busca, mas quem nunca abriu o bubble não sabe que a family é trocável. O item 6 do backlog está ✅ pela superfície, não pela descoberta | P |
| P3 | Live draw sem desfazer múltiplo nem redo | Um `undo` só volta um traço por toque; para uma anotação rápida basta, para um desenho não | P |
| P4 | Live draw não sobrevive a hot-reload | É deliberado (a tinta é efêmera por design), mas durante o desenvolvimento cada save de QML apaga a folha. Persistir em `Persistent` seria contra a decisão; **documentar basta** | — |
| P5 | Notas com desenho não aparecem no widget de notas do desktop | `NotesWidget.qml` desenha só texto; uma nota de sketch fica vazia lá | P |
| P6 | `notes.json` não é versionado | O campo `sketch` novo é ignorado por um shell antigo, que o **descarta na próxima escrita** — o PNG fica órfão. Sem consequência real, mas é a única regressão possível de downgrade nesta branch | P |
| P7 | Live draw só tem uma cor de "tinta clara" e uma de "tinta escura" na paleta | Sobre um papel de parede claro, o preto some; sobre um escuro, o branco. Um seletor de cor livre resolveria | M |
| P8 | Bandeja do live draw fixa no rodapé | Cobre o canto inferior central da tela, que é exatamente onde muita gente escreve | M |
| P9 | Pen mode não sabe quando a caneta some | O cursor de caneta continua depois de desconectar o tablet. `OskAutoShow` já conta os dispositivos; falta reagir à contagem cair a zero | P |
| P10 | Botões da caneta sem confirmação visual | Settings diz "aperte uma vez para confirmar", mas nada pisca quando chega. Um toast pequeno fecharia o laço | P |
| P11 | Só dois botões de caneta são vinculáveis | As teclas de expressão do tablet (a HS64 tem quatro) chegam por outro caminho e não são lidas | M |

---

## 5. Como introduzir na `dev`

A branch tem 124 commits e toca 403 arquivos. **Não faça squash** — o histórico é a
documentação de por que cada decisão foi tomada, e as mensagens já carregam o raciocínio.

O passo 1 já foi dado: a `dev` está mesclada para dentro, sem conflito textual, e o único
conflito semântico foi corrigido. O que segue é a sequência para o dia do merge.

```bash
ii                                   # cd ~/.config/quickshell/ii
git fetch origin

# 1. Se a dev tiver andado, traga-a para dentro de novo — nunca o contrário.
#    Merge, não rebase: 124 commits reescritos perdem as datas e obrigam a
#    resolver o mesmo conflito uma vez por commit.
git merge origin/dev

# 2. A primeira coisa a conferir, antes de qualquer teste:
grep -n "currentConfigVersion:" modules/common/Config.qml
#    A branch está em 18. Se a dev tiver subido para 17 ou 18, renumere os blocos
#    desta branch e ajuste as guardas `if (from < …)`.

# 3. Procure consumidores de caminhos que esta branch moveu. É a quebra que o git
#    não vê, e já mordeu duas vezes — os testes falham ao abrir o arquivo, não
#    numa asserção.
git diff --diff-filter=D --name-only origin/dev...HEAD | grep -E '\.(qml|js)$'
#    Para cada um, procure o nome do arquivo no resto da árvore.

# 4. Guardas automáticas.
bash scripts/dev/check-panel-family-layering.sh
QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner \
  -import /usr/lib64/qt6/qml -input tests -o -,txt -silent
for f in scripts/tests/test_*.py; do python3 "$f" >/dev/null 2>&1 || echo "FAIL $f"; done
#    Esperado: layering OK, 228 QML passando, e exatamente seis arquivos Python
#    falhando — bar search, browser sites, raycast, edit-mode scope, typing test,
#    user profile avatar. Todos falham na dev também.

# 5. Teste as TRÊS families. 326 dos 403 arquivos são compartilhados, e agora há
#    UI para isto: Settings › Interface & Fonts › Shell family.
#    Em cada uma: bar, sidebars, overview, settings, lock. Depois:
qs log -c ii | grep -icE "is not a type|unavailable|ReferenceError"
#    Esperado: 0.

# 6. Só então:
git checkout dev && git merge --no-ff agent/tablet-family-base
```

> [!CAUTION]
> **Não reinicie o shell com a tela bloqueada.** O shell é dono da superfície de session
> lock; matá-lo ali deixa o Hyprland com a sessão trancada e sem cliente para destrancar,
> e a saída é `hyprctl --instance 0 eval 'hl.clear_crashed_lockscreen()'` de outro TTY.
> Aprendido da forma difícil durante esta sessão.

### Checklist de revisão sugerido para o PR

Um revisor com pouco tempo deve olhar, nesta ordem:

1. **`modules/common/Config.qml`** — é o arquivo que todas as families leem. Defaults novos,
   as migrações v17/v18, e o bloco `tablet.liveDraw`.
2. **`GlobalStates.qml`** — três handlers novos instalados pela family (`liveDrawHandler`,
   `hubModePreview`, `liveDrawSaveRequest`). Todos seguem o padrão de `navigateBackHandler`:
   a family instala, `modules/common` chama se existir, e nada quebra numa family que não
   instala.
3. **`shell.qml` e os três `panelFamilies/*.qml`** — o ponto de acoplamento entre families.
4. **`services/NotesService.qml`** — único serviço compartilhado com mudança de schema.
   E `services/RustHelperBuild.qml` / `PenMode.qml`, serviços novos: o primeiro roda
   `cargo` a pedido, o segundo escreve o tema de cursor da sessão inteira. Ambos só são
   instanciados pela tablet family.
5. O resto de `modules/tablet/` pode ser lido por amostragem: o guarda de camadas garante
   que nada ali importa `qs.modules.ii.*`.

---

## 6. Registro de risco — o que pode quebrar para quem não usa tablet

| Risco | Severidade | Mitigação |
|---|---|---|
| Migração v17 vira `autoHideOnOccupiedWorkspace` para `false` | 🟢 Baixa | Chave só lida pela tablet family; a opção continua em Settings |
| Migração v18 insere `liveDraw` nas ações do bubble | 🟢 Baixa | `tablet.bubble` só existe na tablet family; a inserção é idempotente |
| `notes.json` ganha o campo `sketch` em toda aba | 🟡 Média | Aditivo; shell antigo ignora e descarta na próxima escrita (ver P6) |
| `HelperCodeBox` ganhou botão de ação | 🟢 Baixa | Propriedades novas com default vazio: sem `actionText`, o componente se comporta exatamente como antes |
| `osk.autoShow.allowMouse` novo | 🟢 Baixa | Default `false`; sem ele nada muda para ninguém |
| `TouchGestureActionRegistry` ganhou `liveDraw` e `hubMode` | 🟢 Baixa | Ambos `families: ["tablet"]`; `availableForFamily` já os esconde nas outras |
| Ação `prominent` no bubble | 🟢 Baixa | Superfície exclusiva da tablet |
| Pen mode troca o tema de cursor da sessão | 🟡 Média | `hyprctl setcursor` é global e dura a sessão. Restaurado ao sair do modo **e na destruição do singleton**, então trocar de family devolve o cursor. Um `kill -9` no shell com pen mode ligado deixa o cursor de caneta até o próximo `setcursor` |
| Seletor de family em Interface & Fonts | 🟢 Baixa | Escreve só `panelFamily`, pelo `PanelFamily.select`, que é o único setter e recusa um id desconhecido |
| `modules/common/animations/` e `functions/SpaceArbitration.js` movidos | 🟠 **Já mordeu** | Três testes ficaram apontando para o caminho antigo e **falhavam ao compilar**, não numa asserção — por isso passaram despercebidos. Corrigidos em `10f4412e1`. Vale procurar outros consumidores dos caminhos antigos no rebase |

---

## 7. Ideias de feature, para depois

Em ordem de valor por linha de código, todas na linguagem do que já existe.

1. **Live draw a partir do botão da caneta.** Uma caneta com botão lateral podia entrar em
   modo de desenho sem passar pelo bubble — que é literalmente o que a S Pen faz. O
   `PointHandler` já vê os botões em `point.pressedButtons`.
2. **Anotar uma captura de tela.** Live draw sobre um screenshot congelado em vez de sobre a
   tela ao vivo: mesmo canvas, mesma bandeja, uma origem diferente. É o caso de uso mais
   comum de caneta que este shell ainda não cobre.
3. **Formas reconhecidas.** Desenhar um retângulo tosco e ele virar um retângulo. Barato de
   aproximar com a geometria que já está em `TabletStrokeGeometry.js`.
4. **Uma folha de live draw por app, não por workspace.** A anotação seguiria a janela em vez
   da tela. Mais próximo do que um tablet faz, e o `TabletWindowActions` já sabe casar
   toplevels com clientes do Hyprland.
5. **Pastas na home screen** — item 22 do backlog, a única coisa marcada 🟨 lá.
6. **Toque longo na home → wallpaper & estilo** — item 21, adiado.
7. **Exportar uma folha para a área de transferência** em vez de para Notes, para colar
   direto num chat.

---

## 8. O que este documento não cobre

- **Desempenho.** Nada foi medido. A tablet family carrega mais superfícies que a ii, e o
  live draw acrescenta dois `Canvas` por tela enquanto há tinta. Um perfil com `qs` sob
  carga seria o próximo passo honesto.
- **Multi-monitor.** A Fase 7 do plano ("restrição de customização + simplificação
  multi-monitor") continua ⬜ a fazer, e esta sessão não mexeu nela.
- **Tradução.** As strings novas usam `Translation.tr`, mas nenhum catálogo foi atualizado.
