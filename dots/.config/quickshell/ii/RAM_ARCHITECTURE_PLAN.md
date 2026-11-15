# Plano de arquitetura de RAM (2026-11-13)

Meta: um shell com as features atuais em ~400–600 MB PSS (hoje ~1080 MB fresh no live, 2 monitores).
Medição: sandbox kwin `--output-count 2` (scripts `probe.sh` / `probe2.sh`, farms `cfgW`/`cfgD` em `~/.cache/ii-gm-probe`), ≥2 reps por variante, PSS + anon + JS heap.

Já feito (dev): widgets por monitor (−70 PSS), sidebars connect num monitor só (−80 PSS).

| Ordem | Regra | Esforço | Ganho estimado | Estado |
|---|---|---|---|---|
| 1 | 4 — componentes leves + orçamento por painel | pequeno (1–3 sessões + 1 harness) | 20–60 MB | adiada (teto ~20 MB por componente) |
| 2 | 2 — nada duplicado por tela | pequeno/médio (2–4) | 40–60 MB | quase esgotada (sobra ~10–15 MB) |
| 3 | 3 — serviços quentes em C++ | médio/grande (1 medição + 1–3 por serviço) | 50–100 MB + daemons | dados de serviços < 10 MB (medido); falta o gap só-live |
| 4 | 1 — superfícies consolidadas (parcial) | muito grande (15–25) se total | 40–70 MB | só janelas pequenas |

## 1. Regra 4 — componentes leves e orçamento
- Centrais primeiro (um arquivo melhora centenas de usos): `StyledToolTip` (1270 usos) cria conteúdo só no hover; partes de edição dos toggles (`EditableQuickToggleItem`) e `MaterialShape` (365) só onde morfa.
- Medir antes/depois cada componente central com a dashboard + bar como carga.
- **Medido 2026-11-13 (teto = componente trocado por stub vazio, shell inteiro, sandbox 1 tela):**
  - `StyledToolTip` (1300 usos): ~20 MB PSS (676 → 653). Conteúdo já é lazy; o resto é o Popup do ToolTip + binding `sidebarOpen` com 17 dependências por instância.
  - `MaterialShape` (365 usos): ~6–40 MB, ruidoso, média ~20 (654 → 612/648).
  - Conclusão: componentes centrais rendem no máximo ~20 MB cada, e capturar o teto exige trocar a arquitetura deles (tooltip compartilhado; círculo estático como Rectangle). Ganho realista da regra 4: ~15–30 MB.
- Harness de orçamento: script que roda o per-panel leave-one-out e imprime custo por painel; orçamento inicial = medido hoje, alerta se crescer >10%.

## 2. Regra 2 — nada duplicado por tela
- Auditar os 19 `Variants { model: Quickshell.screens }` restantes: quem precisa existir em toda tela (wallpaper, cantos) vs quem só precisa no monitor ativo (popups, OSD, search, overview).
- Padrão: construir no monitor ativo/primário e mover; fallback `Quickshell.screens[0]` (sandbox sem Hyprland).

- **Medido 2026-11-13 (sandbox 2 telas, cfgD):** limitar TODOS os 21 Variants à 1ª tela = −30 PSS (711 → 682), e isso ainda superestima: na sandbox as telas são `Virtual-1/2`, então dock e bar (filtrados por nome no live) caem em "todas as telas". Por tela restante: Background ~21 (wallpaper decodificado + janelas), TopLayer ~4, resto ~5. Realista no live: ~10–15 MB (compartilhar o wallpaper decodificado entre telas).
- Custo por janela no Hyprland/NVIDIA real (processo qs descartável com N janelas 1×1): 1ª janela +17 MB (init do driver), cada extra ~6 MB PSS (~3.5 anon + ~2.5 mapeamento nvidia). Sem custo escondido do driver; regra 1 continua ~6 MB/janela + buffers.
- Pista principal que sobrou: live fresh (10 min) anon 811 / JS 90 vs sandbox 2 telas anon ~545 / JS 36 → ~+266 MB anon e +54 JS vêm de dados/serviços reais (Hyprland, notificações, busca, clipboard, calendário...). É a fase de medição da regra 3.

## 3. Regra 3 — serviços em C++
- **Medição 2026-11-13 (sandbox 2 telas, sequencial, `probe3.sh`):** sem dados 554 anon / JS 38; + system bus real (rede, bateria, bluetooth) 555 / 38.7; + dados reais do Hyprland (proxy só leitura `hyprproxy.py`, bloqueia dispatch/keyword/eval) 561 / 38.6. Tempo sozinho: 45 s → 10 min estável (+10 anon, JS parado).
  - Conclusão: dados de serviços (rede, bluetooth, UPower, clientes/workspaces do Hyprland) custam < 10 MB. Não justificam migrar serviços para C++ por RAM.
  - Cuidado: rodar sandboxes em paralelo distorce ±60 MB; `pkill -f <caminho>` mata o próprio shell do script.
- Shell real (57 min, 5 hot reloads): anon 773, JS 99, qmlcache 170 MB file com cada .qmlc mapeado ~4× (gerações antigas retidas pelo reload; sandbox: 1×, 27–54 MB).
- O gap restante (~200 anon, ~55 JS) só existe no shell real: reloads, uso (abrir painéis → ratchet), protocolos Hyprland (capturas de janelas/overview/dock, global shortcuts), session bus real (MPRIS, tray, notificações). Próximo passo: 1 restart controlado e medição em 1/5/15 min, antes e depois de usar.
- Sessão de medição: JS heap e CPU por singleton (probe `__sglProbe` + gc) para achar os 5–10 dominantes.
- Migrar só esses para modelos C++ num plugin (`plugins/`), import com Loader guard, `QML_IMPORT_PATH` via env.lua.
- Custo permanente: rebuild a cada update de Qt.

## 4. Regra 1 — superfícies (parcial)
- Juntar janelas pequenas: 4 cantos de tela → TopLayer; idle inhibitor 1×1.
- Consolidação total só se as regras 1–3 não bastarem; riscos: máscaras de input, foco de teclado por superfície, animações/blur por namespace do Hyprland, scanout direto em jogos.
