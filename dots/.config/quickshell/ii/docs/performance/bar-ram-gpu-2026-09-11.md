# Auditoria de RAM/GPU da barra — 11 de setembro de 2026

Continuação de [F1 da reanálise controlada](audit-2026-09-08-controlled/REANALISE-INVESTIGACOES.md#2-f1--barra-passa-a-ser-prioridade-de-consumo-contínuo)
e da [auditoria de GPU](gpu-audit-2026-09-09.md). O F1 tinha apontado a barra
como o maior custo residente, mas sem decompor. Esta rodada mede a barra do fork
**contra a barra do end-4 rodando ao vivo na mesma máquina** e isola o custo da
barra no código atual.

**Todas as medições desta rodada são ao vivo, uma sessão por vez, monitor único
1920×1080, idle, com mídia tocando.** Harness: `snap.py` (RSS/PSS de
`smaps_rollup`, categorias de `smaps`, VRAM por PID via NVML, CPU por diff de
ticks). Nada foi commitado; a única edição de código (desligar o loader da barra
para o teste F1) foi revertida.

## 1. Resultado principal: fork 2,2× o end-4, ao vivo

Pela primeira vez o shell do end-4 foi **executado** aqui (o checkout tinha o
submódulo `shapes` vazio — daí as auditorias anteriores só compararem código).
Populado o submódulo, as duas árvores foram medidas no mesmo instante, ambas em
idle:

| Métrica | end-4 (full) | fork (full) | Δ (fork − end-4) |
|---|---:|---:|---:|
| PSS | **350,1 MiB** | **764,8 MiB** | **+414,7** |
| RSS | 515,8 | 968,3 | +452,5 |
| VRAM (NVML por PID) | 144,6 | 245,8 | **+101,2** |
| `anon_native` | 251,3 | 566,1 | **+314,8** |
| `js_gc_heap` (QtQml) | 10,8 | 91,3 | **+80,5 (8,4×)** |
| bibliotecas `.so` | 52,4 | 50,5 | ~0 |
| fontes | 4,6 | 13,1 | +8,5 |
| threads | 16 | 18 | +2 |

O fork usa **+414 MiB de PSS** e **+101 MiB de VRAM** que o upstream do qual saiu.
A diferença está em dois blocos:

1. **`anon_native` +315 MiB** — QObjects em C++, buffers, strings, pixmaps de
   imagem e arenas do alocador. É o bloco dominante; `smaps` não o reparte por
   objeto (precisaria de heaptrack, que a auditoria de 09-08 marcou como risco em
   processo vivo).
2. **`js_gc_heap` ×8,4** — o heap gerenciado do motor QML/JS. Este número
   **é** atribuível: mede o grafo de objetos JS vivos (wrappers de QObject,
   propriedades, closures de binding, dados dos singletons). O end-4 mantém 10,8
   MiB; o fork, 91,3. Oito vezes mais objetos vivos é a marca estrutural da
   diferença.

**Limites deste teste:** o shell do end-4 emitiu avisos de schema de config
(chaves que a versão dele não conhece → alguns painéis *lazy* como sidebars e
notificações não chegaram a construir). Barra e background construíram e mapearam
camadas nos dois. É uma comparação de idle justa para as superfícies residentes,
não um A/B de cada painel. Rodar as duas ao mesmo tempo gera pressão de memória,
mas PSS é proporcional e por processo.

## 2. Quanto custa a barra, hoje, no fork

Teste F1 refeito com o código atual: início limpo **com** e **sem** a barra
(loader desligado em `panelFamilies/IllogicalImpulseFamily.qml`, revertido depois).
Cada leitura após 34 s de assentamento.

| Métrica | com barra | sem barra | custo da barra |
|---|---:|---:|---:|
| PSS | 672,5 | 534,6 | **+137,9 MiB** |
| RSS | 841,2 | 680,5 | +160,7 |
| `anon_native` | 464,2 | 366,0 | +98,2 |
| `js_gc_heap` | 87,2 | 59,5 | **+27,7** |
| fontes | 13,0 | 9,6 | +3,4 |

A barra inteira (janela + tudo que ela é a primeira a instanciar) custa
**~138 MiB de PSS** — sozinha, ~40% do shell inteiro do end-4.

### 2.1 Quanto disso é a janela e quanto é serviço que não morre

A/B ao vivo na mesma sessão, alternando `ipc call bar close`/`open` (destrói e
reconstrói só a `PanelWindow` da barra; os singletons já instanciados permanecem):

| Estado | PSS | VRAM | threads |
|---|---:|---:|---:|
| barra aberta | 711 / 699 | ~328 | 25–26 |
| barra fechada | 654 / 649 | ~307 | 17 |
| **Δ janela** | **~50–57 MiB** | **~20 MiB** | **+8–9** |

Cruzando com o F1 (138 MiB): a **árvore visual destruível da barra é só ~50 MiB**;
os outros **~88 MiB são singletons de serviço** que a barra é a primeira/única a
tocar e que **não são liberados** quando a janela morre (singleton QML vive pela
sessão inteira). Fechar a barra não recupera esses 88 MiB — só um início sem a
barra recupera. Os +8 threads ao abrir são o pool assíncrono dos `Loader`/imagens.

## 3. Causa concreta: o botão de dashboard "expressivo" é um agregador de serviços

`modules/ii/bar/widgets/dashboard/ExpressiveDashboardPanelButton.qml` desenha um
cacho de ícones de status (VPN, Tailscale, Bluetooth, DNS, mic, cafeína,
easyeffects, reconhecimento de música, pomodoro, cronômetro, game mode…). Cada
ícone tem um `DashboardIconRevealer` cujo `reveal` **avalia um singleton de
serviço** para decidir se aparece:

```qml
reveal: Config.options.bar.dashboardButton.showVpn && VpnService.active
reveal: Config.options.bar.dashboardButton.showTailscale && TailscaleService.active
reveal: Config.options.bar.dashboardButton.showDns && DnsOverTls.active
reveal: Config.options.bar.dashboardButton.showMusicRecognition && SongRec.running
...
```

O `&&` de JS faz short-circuit, então o serviço só é tocado se o toggle estiver
ligado. Só que **16 dos 18 toggles estão ligados** nesta config. Resultado: só por
existir na barra, esse único widget **instancia ~12 singletons no boot** —
`VpnService`, `TailscaleService`, `DnsOverTls`, `SongRec`, `EasyEffects`,
`TimerService`, `BluetoothStatus`, `Idle`, `Audio`, `Notifications` e o
`DashboardIconDriver` (que por sua vez agrega PowerProfile, GameMode, alarmes e
countdowns) — para renderizar pontinhos de status que ficam escondidos 99% do
tempo.

Vários desses fazem **polling em background**: `VpnService` roda `nmcli`/CLI do
provedor, `TailscaleService` faz `tailscale status`, `DnsOverTls` e `SongRec`
também sondam. São **exclusivos da barra** no idle (nada mais os referencia no
startup) — é a explicação mais direta para parte dos ~88 MiB de singletons e da
CPU contínua que o F1 viu sumir ao remover a barra. A barra do end-4 não tem nada
equivalente: os widgets dela são clock, resources, systray, battery, workspaces.

## 4. Fundo estrutural (código, não RAM — contexto)

| | fork | end-4 |
|---|---:|---:|
| QML em `modules/ii/bar` | 43.858 linhas / 172 arquivos | 3.110 / ~30 |
| Singletons em `services/` | 168 | 45 |
| Arquivos em `services/` | 276 | 53 |

14× mais código de barra e 3,7× mais singletons. Não é RAM por si, mas é a
superfície que produz o grafo de objetos vivos 8,4× maior (§1).

## 5. Barra vertical

Não está ativa nesta config (`BarPlacement.vertical` falso → a horizontal é que
mapeia; sem camada `quickshell:verticalBar`), então não deu para medir RAM ao
vivo. O achado estrutural da [auditoria de GPU §3](gpu-audit-2026-09-09.md) segue
de pé: quando ligada, `VerticalBar.qml` é uma `PanelWindow` **fullscreen**
(1920×1080) para hospedar uma faixa de ~72 px, e cai na regra global de blur
`quickshell.*` — o compositor calcula blur sobre a tela inteira por causa dela.
Custo de GPU, não de heap do qs.

## 6. Desperdícios menores confirmados

- **Fonte GoogleSansFlex mapeada de 3 caminhos ao mesmo tempo** (~5,3 MiB):
  `/usr/share/fonts/ii-sddm-theme-fonts/…`, `~/.local/share/fonts/Google_Sans_Flex/…`
  e `/usr/share/fonts/google-sans-flex-vf-fonts/…`. Mesmo arquivo, três instalações.
- Fontes totais do fork 13,1 MiB vs 4,6 do end-4.

## 7. Candidatos de correção, por alavancagem

Ordenado por (RAM/CPU provável) e independência entre si. **Nada aplicado nesta
rodada** — é diagnóstico.

| # | Alvo | Ganho esperado | Risco / o que valida |
|---|---|---|---|
| 1 | **Pollers exclusivos da barra sob demanda** — `VpnService`, `TailscaleService`, `DnsOverTls`, `SongRec`, `EasyEffects` só começam a sondar quando há consumidor vivo que precisa de estado (ref-count "hasConsumers"), não quando um binding de `reveal` escondido os toca. | Parte dos ~88 MiB de singletons da barra + CPU de polling contínuo | O ícone de status precisa observar o serviço para reagir; a correção é o serviço não *sondar* até haver demanda real, mantendo a observação barata. Testar que o ícone ainda aparece/some ao ligar/desligar VPN etc. |
| 2 | **Grafo de singletons no boot** (sistêmico, não só barra) — `js_gc_heap` 8,4× vem de instanciar cedo demais. Levantar quais dos 168 singletons sobem no startup e adiar os de uso sob demanda. | Parcela do `js_gc_heap` (+80 MiB vs end-4) | Precisa de mapa de quem referencia quem no boot; risco de cascata de `Type unavailable` em hot-reload (ver AGENTS.md sobre singleton novo). |
| 3 | **Dedup de fonte** — apontar os consumidores para um caminho só / remover instalações duplicadas de GoogleSansFlex. | ~5 MiB PSS | Baixo; conferir que nenhum QML referencia o caminho removido por string. |
| 4 | **Barra vertical (se usada)** — gate de blur por superfície + não mapear fullscreen (auditoria de GPU §3/§5). | GPU do compositor | Só relevante com a vertical ligada; validar bordas/cantos. |

## 8. Números de referência (para reproduzir)

- Comparação §1: end-4 PID e fork PID medidos no mesmo instante, `snap.py PID label 4`.
- F1 §2: início limpo `killall -9 qs; nohup qs -c ii`, 34 s de espera, medição de 6 s.
- Toggle §2.1: `qs -c ii ipc call bar close|open`, 12–18 s entre leituras.
- VRAM oscila com a GPU compartilhada (outros apps); o valor de toggle (~20 MiB)
  é mais confiável que o F1 para a barra, porque isola melhor o instante.

---

## Adendo — decomposição por widget (11/09, tarde)

Medido removendo cada widget do `config.json` a partir do backup pristino, um
início limpo por variante (34 s de assentamento). Layout base: 12 widgets.

| Variante | PSS | Δ vs base (custo do widget) | Δ JS heap |
|---|---:|---:|---:|
| base (12 widgets) | 685,3 | — | — |
| sem `dashboard_panel_button` | 646,0 | **−39,3** | −19,7 |
| sem `system_monitor` (resources) | 650,0 | **−35,3** | −11,5 |
| sem `clock` | 662,8 | −22,5 | −6,5 |
| sem `system_tray` | 664,3 | −21,0 | −5,2 |
| sem `weather` | 672,5 | −12,8 | −3,1 |
| sem `bluetooth_devices` | 692,8 | ~0 (ruído ±10) | — |
| **barra vazia (0 widgets)** | **552,8** | **−132,5** (todos) | −35,0 |

Os 12 widgets somam **~132 MiB**; são aproximadamente aditivos. A janela/chrome
da barra sem widgets custa ~18 MiB sobre o F1 sem-barra (534,6 → 552,8).

### Os dois pesos-pesados

1. **`dashboard_panel_button` — ~39 MiB (20 dos quais JS heap).** Não existe
   equivalente no end-4. O botão expressivo instancia **18 ícones de status**
   (`DashboardIconRevealer` → `ExpressiveIconWrapper` → `MaterialShape` +
   um ícone animado baseado em `QtQuick.Shapes`, p.ex. `EqualizerIcon` com 5
   `Shape`/`ShapePath`). **Todos os 18 são construídos ansiosamente**, mesmo com
   `reveal: false` — que é o estado 99% do tempo (VPN/Tailscale/DNS/etc.
   desligados). São ~18 árvores de geometria vetorial vivas para desenhar
   pontinhos escondidos.

2. **`system_monitor` (resources) — ~35 MiB.** O end-4 tem resources, porém
   simples. Aqui o `ResourceUsage` mantém históricos de 60 amostras
   (CPU/RAM/swap), uma tabela de **top-80 processos** sondada, amostragem de GPU
   e Docker, mais um popup expressivo. É dado vivo + polling.

Widgets compartilhados com o end-4 também são 2–3× mais caros: `clock` 22 e
`system_tray` 21 MiB no fork contra versões mínimas no upstream.

### Correção candidata de maior retorno (RAM da barra)

**Loader-gate no conteúdo do `DashboardIconRevealer`:** só instanciar o ícone
(MaterialShape + Shape) quando `reveal` for verdadeiro (status ativo) ou durante
a animação de entrada/saída. Hoje os 18 nascem juntos; com o gate, ficam ~0–3
vivos no caso comum. Recupera a maior parte dos ~39 MiB **sem mudar o
comportamento visível** — o ícone ainda aparece quando o status ativa (custo: um
build assíncrono no primeiro reveal, aceitável porque status muda raramente).
É a versão "RAM" do item 1 (que gateou só o *polling* dos serviços, não a
instanciação dos ícones).

---

## Adendo 2 — loader-gate aplicado + medição limpa (11/09, fim da tarde)

Implementado (commit `perf(bar): lazy-load hidden dashboard status icons`):
`DashboardIconRevealer` ganhou `deferredContent: Component{}` num `Loader`
síncrono ativo só enquanto o slot está revelado/animando; o botão expressivo
migrou seus 17 ícones para `deferredContent`. Os outros estilos de botão seguem
no caminho eager (`content`) inalterados.

**Medição limpa (mídia pausada, VRAM estável em 213,9 nas 4 amostras):**

| | PSS | JS heap |
|---|---:|---:|
| gate OFF (eager) — média 2 runs | 555,5 | 74,7 |
| gate ON (lazy) — média 2 runs | 543,2 | 66,1 |
| **Δ** | **−12,3 MiB** | **−8,7 MiB** |

**Correção do número anterior:** o "−39 MiB" do Adendo 1 estava inflado por
ruído de sessão (mídia tocando → VRAM 327 e heap maior). Com a mídia controlada,
o custo real removível pelo gate é **~12 MiB de PSS / ~9 MiB de JS heap** no
idle — o custo dos ~15 ícones de status normalmente ocultos. O restante dos ~39
(chrome do botão, `DashboardIconDriver`, os 2 ícones sempre-visíveis
volume/network, a árvore dos 18 revealers) permanece porque é necessário. O
ganho escala com quantos status estão inativos, e some custo de GPU (menos
buffers de Canvas). Verificado: barra renderiza idêntica; ícones sempre-visíveis
aparecem; sem erros de runtime.

**Próximo alvo de RAM da barra** (não feito): `system_monitor` (~35 MiB) —
`ResourceUsage` com histórico de 60 amostras + tabela top-**80** processos +
amostragem de GPU + Docker. Enxugar o top-N e tornar o histórico sob demanda.
