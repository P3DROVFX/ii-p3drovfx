# Auditoria de merge — Tablet Panel Family → `dev`

> **Data:** 2026-09-03 · **Branch:** `agent/tablet-family-base` · **Alvo:** `origin/dev`
> **Documentos irmãos:** [`tablet-family-plan.md`](./tablet-family-plan.md) (o que foi
> construído) e [`tablet-family-audit.md`](./tablet-family-audit.md) (o que falta para isso
> ser um tablet).
>
> Este documento responde a uma terceira pergunta, que os outros dois não respondem:
> **o que falta para isto entrar na `dev` sem quebrar quem não usa tablet?**

---

## 1. Veredito

**Pronto para merge depois de três coisas pequenas** (§3). O risco não está no
`modules/tablet/` — que é isolado, coberto por um guarda automático e não é carregado por
nenhuma outra family — e sim nos **63 arquivos compartilhados** que a branch tocou fora
dele.

| Número | Valor |
|---|---|
| Commits à frente da `dev` | 117 |
| Commits atrás da `dev` | 11 |
| Arquivos alterados | 390 (23 306 inserções, 802 remoções) |
| Dos quais em `modules/tablet/` | 73 |
| **Fora de `modules/tablet/`** | **317** |
| Conflitos textuais com a `dev` hoje | **0** (`git merge-tree`) |
| Violações de camada | **0** (baseline vazia, guarda passando) |
| Suíte QML | **223 passam, 0 falham** |
| Contratos Python | 3 arquivos falham — **os três também falham na `dev`** |

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

### M1 — Rebase na `dev` e revalidar os 15 arquivos em comum 🔴

`git merge-tree` diz zero conflitos textuais **hoje**, mas a `dev` tem 11 commits que tocam
arquivos que esta branch também toca:

```
GlobalStates.qml            modules/common/Config.qml       shell.qml
SettingsWindow.qml          modules/common/Appearance.qml   modules/common/Persistent.qml
modules/common/Directories.qml   modules/common/SettingsPageRegistry.qml
modules/ii/background/BackgroundRoot.qml      modules/ii/background/BackgroundWidgetsWindow.qml
modules/ii/bar/BarComponent.qml               modules/ii/editMode/EditModeChromeContent.qml
modules/ii/editMode/EditModeChromeSurface.qml modules/ii/editMode/EditModeDrawer.qml
modules/welcome/WelcomeWindow.qml
```

Ausência de conflito textual **não é** ausência de conflito semântico. O caso concreto:

> **`currentConfigVersion`**: a `dev` está em **16**, a branch em **18**. Se alguém subir a
> `dev` para 17 antes do merge, as duas numerações colidem sem git dizer nada, e os blocos
> `if (from < 17)` de cada lado passam a significar coisas diferentes. **Confira este número
> como primeira coisa depois do rebase**, e renumere os blocos da branch se preciso.

### M2 — Validar em hardware com toque 🔴

A `tablet-family-audit.md` §4.4 já pedia isso e continua valendo, agora com mais itens.
**Nada em §4 daquele documento pode ser marcado como pronto sem isto**, e três coisas
entregues nesta sessão nunca tocaram um dedo ou uma caneta:

```
[ ] hyprctl devices  →  lista uma seção "Touch Devices"
[ ] Settings › Overlays › On-screen keyboard → "Build it now" compila e o teclado
    passa a subir sozinho ao tocar num campo, sem reiniciar o shell
[ ] O daemon reporta devices com t>0 ou p>0 (e o aviso de "sem touchscreen" some)
[ ] Live draw: um traço de caneta varia de espessura com a pressão
[ ] Live draw: a ponta de borracha da caneta apaga sem passar pela bandeja
[ ] Live draw: com o desenho "mantido", tocar na tela chega ao aplicativo embaixo
[ ] Alças de janela: arrastar e soltar não dá salto nenhum
```

O que **foi** validado em runtime aqui, sem toque: dock persistente (screenshot), preview do
hub mode (screenshot), grade centrada (medida em pixels: centro do bloco 856 → 954, tela
960), alças seguindo a janela após um `move` (posição relatada acompanha o dispatch), tinta
por workspace (11 608 px de tinta na ws 2, 165 na ws 4, e de volta ao trocar), recorte e
gravação do PNG, e a nota criada com o caminho certo.

### M3 — Decidir o que fazer com os dois helpers Rust 🟠

`scripts/osk/osk_autoshow` e `scripts/touchGestures/touch_gestures` são **fonte, não
binário** — corretamente ignorados pelo git. Numa instalação nova, gestos de toque e
auto-show do teclado simplesmente não funcionam até alguém compilar.

A OSK agora tem um botão "Build it now" que resolve isso sem terminal (era obrigatório: o
recurso que desbloqueia o teclado não podia exigir um teclado). **Falta a mesma coisa para
`touch_gestures`**, que hoje só oferece o comando para copiar — e é o helper mais importante
dos dois numa tablet.

Opções, em ordem de preferência:

1. Botão de build no `TouchGesturesConfig`, reusando o `HelperCodeBox.actionClicked` que esta
   branch acabou de acrescentar. **Pequeno, e é a mesma solução já aprovada para a OSK.**
2. Compilar os dois no `setup_ii-vynx.sh`, se o setup puder assumir uma toolchain Rust.
3. Aceitar como está e documentar no README.

---

## 4. Polimento antes ou depois do merge

Nada aqui bloqueia, mas todos são coisas que um revisor vai notar.

| # | Item | Por quê | Esforço |
|---|---|---|---|
| P1 | Botão de build para `touch_gestures` | Ver M3.1 — a metade que ficou | P |
| P2 | Sem UI para trocar de panel family em Settings ou Welcome | O `ShellSwitcher` existe e é alcançável por ação/gesto/bubble/busca, mas quem nunca abriu o bubble não sabe que a family é trocável. O item 6 do backlog está ✅ pela superfície, não pela descoberta | P |
| P3 | Live draw sem desfazer múltiplo nem redo | Um `undo` só volta um traço por toque; para uma anotação rápida basta, para um desenho não | P |
| P4 | Live draw não sobrevive a hot-reload | É deliberado (a tinta é efêmera por design), mas durante o desenvolvimento cada save de QML apaga a folha. Persistir em `Persistent` seria contra a decisão; **documentar basta** | — |
| P5 | Notas com desenho não aparecem no widget de notas do desktop | `NotesWidget.qml` desenha só texto; uma nota de sketch fica vazia lá | P |
| P6 | `notes.json` não é versionado | O campo `sketch` novo é ignorado por um shell antigo, que o **descarta na próxima escrita** — o PNG fica órfão. Sem consequência real, mas é a única regressão possível de downgrade nesta branch | P |
| P7 | Live draw só tem uma cor de "tinta clara" e uma de "tinta escura" na paleta | Sobre um papel de parede claro, o preto some; sobre um escuro, o branco. Um seletor de cor livre resolveria | M |
| P8 | Bandeja do live draw fixa no rodapé | Cobre o canto inferior central da tela, que é exatamente onde muita gente escreve | M |

---

## 5. Como introduzir na `dev`

A branch tem 117 commits e toca 390 arquivos. **Não faça squash** — o histórico é a
documentação de por que cada decisão foi tomada, e as mensagens já carregam o raciocínio.

```bash
ii                                   # cd ~/.config/quickshell/ii
git fetch origin

# 1. Traga a dev para dentro da branch primeiro, nunca o contrário.
#    Merge, não rebase: 117 commits reescritos perdem as datas e obrigam a
#    resolver o mesmo conflito uma vez por commit.
git merge origin/dev

# 2. A primeira coisa a conferir, antes de qualquer teste:
grep -n "currentConfigVersion:" modules/common/Config.qml
#    Se a dev tiver subido para 17, renumere os blocos desta branch para 18/19
#    e ajuste as guardas `if (from < …)`.

# 3. Guardas automáticas.
bash scripts/dev/check-panel-family-layering.sh
QT_QPA_PLATFORM=offscreen /usr/lib64/qt6/bin/qmltestrunner \
  -import /usr/lib64/qt6/qml -input tests -o -,txt -silent
for f in scripts/tests/test_*.py; do python3 "$f" >/dev/null 2>&1 || echo "FAIL $f"; done
#    Esperado: layering OK, 223 QML passando, e exatamente três arquivos Python
#    falhando (bar search, browser sites, raycast) — os mesmos que falham na dev.

# 4. Teste as TRÊS families, não só a tablet. 317 dos 390 arquivos são compartilhados.
for family in ii waffle tablet; do
  qs -c ii ipc call panelFamily set "$family"   # ou troque pela UI
  # abra bar, sidebars, overview, settings, lock; confira o log
  qs log -c ii -t 50
done
ii-restart

# 5. Só então:
git checkout dev && git merge --no-ff agent/tablet-family-base
```

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
