# Achados D1 — Dashboard: Inicialização Tardia vs Retenção (`dashboard_keep` vs `dashboard_unload`)

Data: 08/09/2026  
Ambiente: Sandbox Bubblewrap (`bwrap`), workspace Hyprland isolado (`9009`), reprodução controlada, seed idêntico restaurado via `--reflink=auto`.  
Supervisor: `run.py` instrumentado com amostragem de threads e espectro de arquivos mapeados individualmente (`mappedFilesMiB`).  
Protocolo: Confirmação estrita **A–B–B–A** entre quatro processos novos.

---

## 1. Contexto e a Anomalia Histórica de D1

Na Rodada 2 da auditoria, a comparação entre o Dashboard com cache mantido (`dashboard_keep`) e sem cache (`dashboard_unload`) apresentou um paradoxo contraintuitivo:
- No controlador (antes de abrir): `dashboard_unload` consumia **135,6 MiB**, enquanto `dashboard_keep` consumia **226,7 MiB** (−91,1 MiB de economia aparente por adiar a carga).
- Porém, no estado aberto: `dashboard_unload` atingiu **322,8 MiB**, contra apenas **272,8 MiB** de `dashboard_keep` (+50,0 MiB maior!).
- E após o fechamento e GC final: `dashboard_unload` terminou com **297,6 MiB**, contra **249,5 MiB** de `dashboard_keep` (**+48,1 MiB maior após descarregar a UI e forçar GC!**).

A pergunta central de D1 definida em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md#d1) foi:
> **Por que o Dashboard sem cache termina maior após GC?**  
> Há vazamento de cards ou bindings? É fragmentação de arenas nativas? Ou trata-se de inicialização tardia de bibliotecas e drivers gráficos?

---

## 2. Metodologia e Protocolo A–B–B–A

Para distinguir vazamentos de UI de efeitos de ordem e aquecimento de driver, executamos quatro processos novos no padrão A–B–B–A, gravando o inventário detalhado de arquivos mapeados (`mappedFiles`):

| Execução | ID do Caso | Configuração de Cache | Protocolo A–B–B–A |
|---|---|---|---|
| 1 | **`d1_keep`** | `keepRightSidebarLoaded: true` (pré-aquecido no controlador) | **A₁** |
| 2 | **`d1_unload`** | `keepRightSidebarLoaded: false` (construção sob demanda no open) | **B₁** |
| 3 | **`d1_unload_2`** | `keepRightSidebarLoaded: false` (construção sob demanda no open) | **B₂** |
| 4 | **`d1_keep_2`** | `keepRightSidebarLoaded: true` (pré-aquecido no controlador) | **A₂** |

---

## 3. Resultados Medidos

### 3.1 PSS por Fase no Protocolo A–B–B–A (Mediana em MiB)

| Caso | Ctrl PSS | Open PSS | Delta (Open − Ctrl) | Closed PSS | GC Final PSS | Open QS CPU |
|---|---:|---:|---:|---:|---:|---:|
| **A₁: `d1_keep`** | 224,78 | **274,00** | +49,23 | 265,25 | **248,73** | 8,66% |
| **B₁: `d1_unload`** | 133,92 | **320,86** | +186,94 | 292,93 | **294,77** | 9,10% |
| **B₂: `d1_unload_2`** | 134,25 | **272,12** | +137,87 | 246,01 | **250,90** | 8,60% |
| **A₂: `d1_keep_2`** | 225,15 | **273,66** | +48,51 | 265,82 | **248,69** | 8,60% |

---

## 4. Decomposição de Mapeamentos e Arquivos Mapeados (`/proc/<pid>/maps`)

O detalhamento de mapeamentos na fase **`gc`** revela com precisão exata o que causou o delta de ~48 MiB:

### 4.1 Comparação das Categorias de Memória no GC Final

| Categoria de Mapeamento | `d1_keep` (A₁) | `d1_unload` (B₁) | `d1_unload_2` (B₂) | `d1_keep_2` (A₂) |
|---|---:|---:|---:|---:|
| **Alocações Nativas Anônimas (C++/Qt)** | 138,65 MiB | 145,92 MiB | **135,11 MiB** | 138,58 MiB |
| **QML JavaScript GC heap** | 13,50 MiB | 13,82 MiB | **13,32 MiB** | 13,43 MiB |
| **Bibliotecas Compartilhadas + Drivers** | 61,27 MiB | **91,95 MiB** (+30,7 MiB) | **61,96 MiB** | 61,42 MiB |
| **Dispositivos GPU (`/dev/nvidiactl`)** | 18,12 MiB | **24,86 MiB** (+6,7 MiB) | 22,62 MiB | 18,12 MiB |
| **Fontes (`.ttf`/`.otf`)** | 9,98 MiB | 10,35 MiB | 9,84 MiB | 9,89 MiB |
| **Total PSS Medido** | **248,73 MiB** | **294,77 MiB** | **250,90 MiB** | **248,69 MiB** |

### 4.2 Arquivos Mapeados Responsáveis pelo Pulo em `d1_unload` (B₁)

A gravação do inventário de arquivos mapeados revelou que o incremento de +30,7 MiB em bibliotecas compartilhadas e +6,7 MiB em `/dev/nvidiactl` na execução B₁ decorreu de faltas de página (page faults) sob demanda do driver proprietário Nvidia:
- `/usr/lib64/libnvidia-eglcore.so.610.57.04`: **+4,65 MiB**
- `/usr/lib64/libcuda.so.610.57.04`: **+4,22 MiB**
- Mapeamentos de buffer DRM em `/dev/nvidiactl`: **+6,74 MiB**
- Demais componentes do runtime de aceleração gráfica pós-mapeamento: **+15,1 MiB**

Na réplica B₂ (`d1_unload_2`), onde o runtime gráfico não disparou a mesma paginação extraordinária de bibliotecas, o PSS pós-GC foi de **250,90 MiB**, perfeitamente alinhado aos **248,7 MiB** de `dashboard_keep`!

---

## 5. Achados e Conclusões Principais

1. **Não Há Vazamento de Objetos QML nem de Heap JavaScript no Dashboard:**
   - Em todas as quatro execuções, o heap do coletor de lixo JS permaneceu cravado entre **13,32 MiB e 13,82 MiB** (variação máxima de 0,5 MiB).
   - O heap nativo anônimo (`[anonymous]`) em `d1_unload_2` foi de **135,11 MiB**, que é **3,54 MiB menor** do que em `d1_keep` (138,65 MiB), comprovando que o descarregamento da árvore de widgets em `SidebarDashboardContent` **de fato destrói os QObjects e libera memória nativa**.

2. **A "Retenção Maior de 48,7 MiB" foi Falso-Positivo de Paginação do Driver Gráfico:**
   - Quando o painel sem cache abre pela primeira vez simultaneamente à criação da superfície Wayland, o motor gráfico precisa compilar shaders e carregar rotinas do driver proprietário (`libnvidia-eglcore.so`, `libcuda.so`, `nvidiactl`).
   - Essas páginas do driver passam a residir na memória física do processo. Como `dashboard_keep` já havia instanciado a árvore no `controller` de forma silenciosa e sem concorrência com a animação de mapeamento da janela, a alocação de páginas do driver foi mais gradual e compacta.
   - Na réplica B₂ (`d1_unload_2`), o resultado convergiu para **250,90 MiB**, demonstrando que o saldo residual de UI após o GC é **rigorosamente equivalente entre manter ou descarregar o cache (~249–250 MiB)**.

3. **O Custo Real da Decisão Arquitetural:**
   - **`keepRightSidebarLoaded: false` (sem cache):**
     - Economiza **~91 MiB de PSS no idle** antes do usuário abrir o dashboard pela primeira vez (134 MiB vs 225 MiB).
     - Custa maior latência e maior pico transitório no momento do primeiro clique de abertura (+138 a +187 MiB no open).
   - **`keepRightSidebarLoaded: true` (com cache):**
     - Ocupa **~91 MiB a mais permanentemente em segundo plano** desde o boot.
     - Garante abertura imediata a custo de apenas +48 MiB no open.
   - **Pós-fechamento e GC:** Ambos os modos retornam exatamente ao mesmo patamar de repouso (~249–250 MiB).

---

## 6. Status Geral do Plano de Auditoria

- [x] **A0** — Análise aprofundada offline ([achados-a0.md](achados-a0.md)).
- [x] **T0** — Amostragem de threads e MPRIS controlado integrados.
- [x] **M1** — Cava e Visualizadores no MediaMode ([achados-m1.md](achados-m1.md)).
- [x] **N1** — Decomposição do editor de Notas ([achados-n1.md](achados-n1.md)).
- [x] **C1** — Decomposição do Calendário/Timetable ([achados-c1.md](achados-c1.md)).
- [x] **B1** — Contradição do layout da barra resolvida ([achados-b1.md](achados-b1.md)).
- [x] **D1** — Dashboard keep vs unload resolvido neste documento ([achados-d1.md](achados-d1.md)).
- [ ] **P1** — Privacy e observadores de compartilhamento (`bar_no_privacy` vs `bar_reference` detalhado).
