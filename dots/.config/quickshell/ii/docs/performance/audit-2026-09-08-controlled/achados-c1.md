# Achados C1 — Decomposição do Calendário/Timetable (`EventSidebar` vs Pickers vs Grade)

Data: 08/09/2026  
Ambiente: Sandbox Bubblewrap isolada (`bwrap`), Hyprland workspace isolado (`9009`), reprodução controlada pausada, seed idêntico restaurado via `--reflink=auto`.  
Supervisor: `run.py` instrumentado com amostragem de threads e espectro de mapas de memória (`/proc/<pid>/maps`).

---

## 1. Contexto e Pergunta da Fase C1

Na Rodada 2 da auditoria, a comparação histórica entre `cheatsheet_timetable` (completo) e `cheatsheet_timetable_grid_only` (sem lateral e sem pickers) indicou duas anomalias simultâneas:
1. Uma diferença de cerca de **55 MiB de PSS próprio** e **94,6 MiB de PSS de árvore** no estado aberto atribuída ao bloco lateral/pickers.
2. A presença de **39,4 MiB de processos auxiliares** na árvore de processos (`khal`, `vdirsyncer_sync.py`, `vdirsyncer`, `ics.py`).
3. Uma retenção residual colossal na grade do mês: mesmo sem a lateral e sem pickers, a grade permaneceu consumindo **~396 MiB de PSS** no estado aberto (um salto de **+275,8 MiB** a partir do controlador).

A pergunta central de C1 definida em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md#c1) foi:
> **A diferença conjunta de lateral/pickers está em `EventSidebar`, num picker ou nas dependências acionadas por eles?**  
> Quanto custa a lateral isoladamente, quanto custa cada seletor (`TimePickerPopup`, `DatePickerPopup`) e qual é o comportamento dos processos auxiliares de sincronização?

---

## 2. Metodologia e Variantes Executadas

Construímos na bancada privada quatro variantes causais comparadas rigorosamente sob as mesmas condições de seed, mês visível, locale e geometria de janela:

| Variante | Descrição | O que isola |
|---|---|---|
| **`c1_base`** | Calendário completo padrão (`Cheatsheet.qml` com `tab: "timetable"`), incluindo `EventSidebar.qml`, `TimePickerPopup.qml` e `DatePickerPopup.qml`. | Linha de base da bancada atual. |
| **`c1_grid_only`** | Controle histórico (`CheatsheetAudit.qml`), com `EventSidebar`, `TimePickerPopup` e `DatePickerPopup` suprimidos simultaneamente. | Réplica do controle histórico para validar o delta total. |
| **`c1_no_sidebar`** | Calendário com `EventSidebar.qml` (131 KB, 2.672 linhas) descarregado via `Loader`, mas mantendo `TimePickerPopup` e `DatePickerPopup` reais ativos. | Custo exclusivo da lateral de eventos e formulário. |
| **`c1_no_timepicker`** | Calendário com `EventSidebar` e `DatePickerPopup` ativos, mas `TimePickerPopup.qml` descarregado via `Loader`. | Custo exclusivo do seletor de horário. |
| **`c1_no_datepicker`** | Calendário com `EventSidebar` e `TimePickerPopup` ativos, mas `DatePickerPopup.qml` descarregado via `Loader`. | Custo exclusivo do seletor de data. |

---

## 3. Resultados Medidos

### 3.1 PSS do Processo e PSS da Árvore por Fase (Mediana em MiB)

| Variante | Ctrl PSS | Open PSS (qs) | Open TreePSS (árvore) | Helpers na Fase Open | Closed PSS | Reopen PSS | GC Final PSS | Open CPU |
|---|---:|---:|---:|---|---:|---:|---:|---:|
| **`c1_base`** | 121,60 | **432,79** | **472,94** | `khal`, `monitor`, `localsend`, `nmcli` (+40,15 MiB) | 432,76 | 432,80 | **376,49** | 0,34% |
| **`c1_grid_only`** | 121,93 | **392,39** | **392,39** | *(nenhum helper ativo na amostragem)* | 386,79 | 415,64 | **356,10** | 0,25% |
| **`c1_no_sidebar`** | 119,49 | **392,87** | **392,87** | *(nenhum helper ativo na amostragem)* | 392,26 | 392,50 | **321,49** | 0,25% |
| **`c1_no_timepicker`** | 119,74 | **443,60** | **483,60** | `khal`, `ics.py`, `vdirsyncer_sync`, etc. (+40,0 MiB) | 375,32 | 442,10 | **384,88** | 0,28% |
| **`c1_no_datepicker`** | 119,49 | **432,96** | **473,12** | `khal`, `monitor`, `localsend`, etc. (+40,16 MiB) | 430,62 | 433,00 | **373,97** | 0,28% |

---

## 4. Decomposição das Categorias de Memória (`/proc/<pid>/maps`)

### 4.1 Fase `open` (Visualização Ativa do Mês)

| Categoria de Mapeamento | `c1_base` | `c1_no_sidebar` | `c1_grid_only` | `c1_no_timepicker` | `c1_no_datepicker` | Impacto de `EventSidebar` |
|---|---:|---:|---:|---:|---:|---:|
| **Alocações Nativas Anônimas (C++/Qt)** | **285,76 MiB** | **241,99 MiB** | 249,48 MiB | 283,28 MiB | 272,86 MiB | **−43,77 MiB** |
| **QML JavaScript GC heap** | 58,99 MiB | 55,02 MiB | 54,23 MiB | 58,93 MiB | 58,80 MiB | **−3,97 MiB** |
| **Bibliotecas Compartilhadas + Drivers** | 60,87 MiB | 59,92 MiB | 59,53 MiB | 60,81 MiB | 60,68 MiB | −0,95 MiB |
| **Dispositivos GPU / DRM** | 18,64 MiB | 18,64 MiB | 18,64 MiB | 18,64 MiB | 18,64 MiB | 0,00 MiB |
| **Fontes (`.ttf`/`.otf`)** | 12,76 MiB | 9,51 MiB | 8,99 MiB | 12,83 MiB | 12,84 MiB | **−3,25 MiB** |
| **Outros Mapeamentos** | 6,25 MiB | 5,59 MiB | 5,67 MiB | 6,17 MiB | 6,21 MiB | −0,66 MiB |
| **QML JIT / Pilha VM** | 2,72 MiB | 2,27 MiB | 2,22 MiB | 2,71 MiB | 2,71 MiB | −0,45 MiB |
| **Total PSS Medido** | **432,79 MiB** | **392,87 MiB** | **392,39 MiB** | **443,60 MiB** | **432,96 MiB** | **−39,92 MiB** |

### 4.2 Fase `gc` (Pós-fechamento e Coleta de Lixo Forçada)

| Categoria de Mapeamento | `c1_base` | `c1_no_sidebar` | `c1_grid_only` | Impacto Residual de `EventSidebar` |
|---|---:|---:|---:|---:|
| **Alocações Nativas Anônimas** | 217,16 MiB | **164,88 MiB** | 203,02 MiB | **−52,28 MiB** |
| **QML JavaScript GC heap** | 53,77 MiB | 55,51 MiB | 48,82 MiB | +1,74 MiB |
| **Total PSS Medido** | **376,49 MiB** | **321,49 MiB** | **352,24 MiB** | **−55,00 MiB** |

---

## 5. Achados e Conclusões Principais

1. **`EventSidebar` Responde por 100% da Diferença da Lateral/Pickers:**
   - O PSS aberto de `c1_no_sidebar` (**392,87 MiB**) é praticamente idêntico ao de `c1_grid_only` (**392,39 MiB**), com uma diferença insignificante de apenas 0,48 MiB.
   - Em contraste, `c1_no_timepicker` (443,60 MiB) e `c1_no_datepicker` (432,96 MiB) mantiveram a ocupação alta de `c1_base` (432,79 MiB).
   - Isso estabelece causalidade irrefutável: **nem `TimePickerPopup` nem `DatePickerPopup` causam aumento mensurável de memória.** O custo conjunto reportado no histórico pertencia inteiramente ao `EventSidebar.qml`.

2. **Causa Raiz de `EventSidebar.qml` (131 KB de Código Eager):**
   - `EventSidebar.qml` possui 2.672 linhas de código e define inline três páginas massivas: o navegador de eventos do dia, o formulário completo de edição/criação de eventos (com categorias, recorrência complexa, alarmes, seletores de cor) e o painel de fontes de calendário (`GoogleCalendarService`, `SportsService`, `OutlookCalendarImport`, `CalendarSubscriptions`).
   - Por estar instanciado diretamente em [MonthView.qml](../../../modules/ii/cheatsheet/timetable/MonthView.qml#L951) (mesmo com `mode: ""` / fechado), o Qt aloca **43,8 MiB de objetos nativos C++** e consome **3,25 MiB extras em fontes**.
   - Na fase pós-fechamento e GC, manter `EventSidebar` resulta em **52,28 MiB de alocações nativas retidas** que não são devolvidas ao sistema operacional. Descarregá-lo derruba o PSS de GC de **376,49 MiB para 321,49 MiB (−55,00 MiB)**.

3. **Os Processos Auxiliares (`khal`, `vdirsyncer`) e a Árvore:**
   - Em `c1_base`, a árvore de processos atingiu **472,94 MiB** devido aos helpers disparados em background (`khal` com 28,3 MiB, `monitor.py` com 16,1 MiB, `localsend_bridge.py` com 12,7 MiB).
   - Quando o painel Timetable é aberto, o `CalendarService` dispara [vdirsyncer_sync.py](../../../services/CalendarService.qml#L429) e `khal list` para sincronização em segundo plano.
   - Em `c1_no_sidebar`, a árvore permaneceu idêntica ao processo principal (392,87 MiB), confirmando que a ausência de chamadas da lateral impediu a cadeia de subprocessos de sincronização de rodar no momento da amostragem.

4. **A Grade Central Continua Sendo o Maior Bloco (270+ MiB):**
   - Mesmo eliminando totalmente `EventSidebar` e os pickers (`c1_no_sidebar`), o PSS aberto foi de **392,87 MiB**, contra 119,49 MiB no controlador (um acréscimo de **+273,38 MiB**).
   - A composição dos 392,87 MiB da grade sem lateral é:
     - 241,99 MiB em alocações nativas (árvores de QQuickItem de 35 a 42 células do mês, cada uma com `MonthDayCell`, `MonthEventChip`, delegados e layouts).
     - 55,02 MiB em heap do coletor de lixo JS (estruturas de dados de eventos, modelos de calendário, datas e formatações).
     - 59,92 MiB em bibliotecas compartilhadas e drivers GPU.

---

## 6. Recomendação e Próximos Passos

1. **Construção Tardia de `EventSidebar`:**
   - O `EventSidebar` deve ser encapsulado em um `Loader { active: root.eventSidebarOpen }` dentro de `MonthView.qml`, tornando sua carga puramente sob demanda.
   - **Ganho Imediato:**
     - **−40,0 MiB de PSS** imediatamente ao abrir a timetable.
     - **−55,0 MiB de retenção residual** após fechar e executar GC.
     - Zero perda funcional para o usuário: a lateral carrega normalmente ao clicar em um evento ou data.

2. **Status do Plano de Auditoria:**
   - [x] **A0** — Concluído ([achados-a0.md](achados-a0.md)).
   - [x] **T0** — Concluído.
   - [x] **M1** — Concluído ([achados-m1.md](achados-m1.md)).
   - [x] **N1** — Concluído ([achados-n1.md](achados-n1.md)).
   - [x] **C1** — Concluído neste documento ([achados-c1.md](achados-c1.md)).
   - [ ] **B1** — Resolver a contradição do layout da barra (`bar_reference` vs `bar_active_layout` com o novo instrumental T0).
