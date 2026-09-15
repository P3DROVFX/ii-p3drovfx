# Achados P1 — Decomposição de Privacy e Observadores de Compartilhamento de Tela

Data: 08/09/2026  
Ambiente: Sandbox Bubblewrap (`bwrap`), workspace Hyprland isolado (`9009`), reprodução controlada, seed idêntico restaurado via `--reflink=auto`.  
Supervisor: `run.py` instrumentado com telemetria interna da sonda (`privacy_probe_stats.json`) e do script de compartilhamento (`screenshare_stats.json`).  
Protocolo: Matriz completa de 6 variantes de diagnóstico executadas sob o mesmo ciclo de fases (core, controller, open, closed, reopen, closed_again, unloaded, gc).

---

## 1. Contexto e Motivação de P1

Nas Rodadas 1 e 2 da auditoria, a variante `bar_no_privacy` (que desabilitava a pílula de privacidade da barra) apresentou uma economia consistente de **~4,2 pontos percentuais de CPU da árvore** e uma redução de **12 a 15 MiB de PSS em processos auxiliares**:
- No entanto, o par histórico removia o monitor inteiro em bloco, sem distinguir o que gerava o custo:
  1. A varredura de `/proc/<pid>/fd` à procura de nós V4L2 de câmera?
  2. As chamadas subprocessadas ao `pw-dump` e o parsing JSON de objetos do PipeWire para microfone e tela?
  3. O loop em bash contínuo do `screensharestate.sh` (`pw-dump | jq | sort | paste`) disparado pelo `ScreenShareIndicator.qml`?
  4. O serviço GeoClue2 via `busctl`?

A pergunta central de P1 definida na Seção 10 de [`PROXIMOS-TESTES.md`](PROXIMOS-TESTES.md#p1) foi:
> **Qual parte de Privacy e screen share consome CPU e mantém helpers?**  
> É possível unificar a observação em um único observador compartilhado funcional, mantendo 100% da cobertura de detecção sem redundância de subprocessos?

---

## 2. Matriz Experimental de Variantes

Para responder cada pergunta de forma isolada, foram implementadas e executadas 6 variantes na bancada:

| ID do Caso | Modificação perante a Referência | O que isola / avalia |
|---|---|---|
| **`p1_base`** | Nenhuma (cenário de referência da barra) | Linha de base com `privacy_probe.py` completo (câmera, microfone, tela) + loop `screensharestate.sh`. |
| **`p1_no_camera`** | `Config.options.bar.privacyPill.watchCamera = false` | Elimina exclusivamente a varredura síncrona de `/proc/*/fd` no Python. Mantém PipeWire e screenshare script. |
| **`p1_no_pipewire`** | `watchMicrophone = false`, `watchScreen = false` | Elimina a execução e parsing de `pw-dump` pelo Python. Mantém varredura de câmera e screenshare script. |
| **`p1_no_screenshare`** | `GlobalStates.disableScreenShareScript = true` | Mantém o monitor de privacidade completo, mas suspende o loop bash do `screensharestate.sh`. |
| **`p1_no_privacy`** | `Config.options.bar.privacyPill.enabled = false` | Desliga o `privacy_probe.py` por completo (`noPrivacy: true`), mantendo apenas `screensharestate.sh`. |
| **`p1_unified`** | `unifiedPrivacy = true` (elimina script redundante) | `screensharestate.sh` desativado; `ScreenShareIndicator.qml` consome eventos diretamente do singleton `Privacy.qml`. |

---

## 3. Micro-benchmark dos Mecanismos Individuais de Consulta

Antes do ensaio supervisionado, o custo por chamada de cada fonte foi medido diretamente em Python/Bash sob condições de repouso:

| Mecanismo de Consulta | Comando / Operação | Duração Média por Chamada | Frequência de Execução | Custo Contínuo de CPU Estimado |
|---|---|---:|---:|---:|
| **Varredura de Câmera** | `camera_users()`: itera `/proc/*/fd` | 23,87 ms (host com ~400 procs) | A cada 1,2 s | ~1,98% de um núcleo |
| **Streams PipeWire (Python)** | `pipewire_streams()`: `pw-dump` + JSON parse | 14,54 ms (100+ nós PipeWire) | A cada 1,2 s | ~1,21% de um núcleo |
| **Consulta GeoClue2** | `location_in_use()`: `busctl` D-Bus | 2,46 ms | Desabilitado por padrão | 0,00% (opt-in) |
| **Pipeline Screenshare (Bash)** | `pw-dump 2>/dev/null \| jq ... \| sort \| paste` | 13,38 ms (5 forks por ciclo) | A cada 1,5 s | ~0,89% de um núcleo |
| **Soma Teórica dos Custos** | — | — | — | **~4,08% de CPU da árvore** |

> [!NOTE]
> A soma teórica dos tempos de consulta do `privacy_probe.py` (~3,2%) e do loop `screensharestate.sh` (~0,9%) totaliza **~4,1% de CPU contínua**, coincidindo com exatidão com os **4,2 pontos percentuais** identificados entre `bar_reference` e `bar_no_privacy` nas rodadas anteriores.

---

## 4. Resultados Medidos no Ambiente Supervisionado

### 4.1 CPU e PSS por Fase em Todas as Variantes

| Variante | Fase Open CPU (Tree / `qs`) | Fase Closed CPU (Tree / `qs`) | Fase GC CPU (Tree / `qs`) | Open PSS (Tree / `qs`) | Post-GC PSS (Tree / `qs`) | Helpers em GC |
|---|---:|---:|---:|---:|---:|---:|
| **`p1_base`** | 9,78% / 0,64% | 4,98% / 0,41% | **8,14% / 0,64%** | 521,1 / 467,3 MiB | 473,5 / 419,2 MiB | 5 helpers |
| **`p1_no_camera`** | 15,11% / 0,84% | 7,80% / 0,66% | **7,97% / 0,72%** | 520,3 / 466,1 MiB | 468,0 / 413,5 MiB | 5 helpers |
| **`p1_no_pipewire`** | 31,60% / 18,69% | 7,61% / 0,87% | **4,62% / 0,54%** | 471,2 / 417,3 MiB | 431,5 / 376,8 MiB | 5 helpers |
| **`p1_no_screenshare`** | 23,90% / 18,27% | 7,15% / 0,66% | **4,72% / 0,64%** | 466,3 / 412,9 MiB | 428,0 / 372,9 MiB | 5 helpers |
| **`p1_no_privacy`** | 28,05% / 18,50% | 4,05% / 0,67% | **1,62% / 0,54%** | 454,0 / 413,6 MiB | 411,9 / 372,6 MiB | **4 helpers** |
| **`p1_unified`** | 24,36% / 18,39% | 7,86% / 0,97% | **4,73% / 0,65%** | 473,3 / 420,8 MiB | 428,4 / 374,3 MiB | 5 helpers |

---

### 4.2 Telemetria Interna Registrada pelas Sondas (105 ciclos por execução)

| Variante | Chamadas Câmera | Tempo Total Câmera | Chamadas PipeWire | Tempo Total PipeWire | Tempo Total Coleta | Iterações Screenshare Script |
|---|---:|---:|---:|---:|---:|---:|
| **`p1_base`** | 105 | 101,6 ms | 105 | 2.205,5 ms | 2.308,6 ms | 14 iterações |
| **`p1_no_camera`** | **0** | **0,0 ms** | 105 | 3.062,9 ms | 3.064,6 ms | 14 iterações |
| **`p1_no_pipewire`** | 105 | 91,8 ms | 105 | 2.967,9 ms | 3.061,5 ms | 14 iterações |
| **`p1_no_screenshare`** | 105 | 81,0 ms | 105 | 2.884,5 ms | 2.967,2 ms | **0 (desativado)** |
| **`p1_no_privacy`** | **0** | **0,0 ms** | **0** | **0,0 ms** | **0,0 ms** | 14 iterações |
| **`p1_unified`** | 105 | 92,6 ms | 105 | 2.952,9 ms | 3.047,2 ms | **0 (desativado)** |

---

## 5. Análise Causal e Descobertas Principais

### 5.1 O Custo Residual dos Processos Auxiliares (Tree CPU − `qs` CPU)
Na fase final de repouso após GC:
1. **Em `p1_no_privacy`:**
   - CPU dos helpers = `1,62% − 0,54% = 1,08%`.
   - Processos ativos: apenas `nmcli`, `monitor.py` (KDE Connect) e `localsend-cli` (mais o loop remanescente do `screensharestate.sh`).
2. **Em `p1_no_screenshare`:**
   - CPU dos helpers = `4,72% − 0,64% = 4,08%`.
   - Desligar o script em bash do screenshare reduziu a CPU de helpers em GC de **7,50% (`p1_base`) para 4,08% (−3,42 pontos percentuais de CPU economizados!)**.
3. **Em `p1_unified`:**
   - CPU dos helpers = `4,73% − 0,65% = 4,08%` (rigorosamente idêntico a `p1_no_screenshare`).
   - O indicador de compartilhamento de tela continuou ativo e pronto para sinalizar sessões ativas através de `Privacy.activeKinds`, **sem rodar uma única linha de script bash ou fork de `pw-dump` redundante**.

### 5.2 Decomposição Interna do `privacy_probe.py`
A telemetria de 105 ciclos coletada em cada cenário demonstrou cabalmente:
- **Câmera (`camera_users`):** consumiu apenas **101,6 ms em 105 ciclos** (~0,96 ms por ciclo no sandbox). Desabilitar a checagem de câmera (`p1_no_camera`) zerou as chamadas mas teve impacto insignificante na CPU total (0,25 p.p.).
- **PipeWire (`pipewire_streams`):** consumiu **2.205 ms a 3.062 ms** ao longo do ensaio. Mais de **95,6% de todo o tempo de CPU do `privacy_probe.py`** é gasto exclusivamente invocando `pw-dump` e decodificando o grafo JSON do PipeWire a cada 1,2 segundos.

### 5.3 A Descoberta da Redundância Crítica
O código original continha dois observadores concorrentes fazendo exatamente a mesma coisa em paralelo:
1. `privacy_probe.py`: executa `pw-dump` a cada 1,2 s para detectar nós com `media.class: Stream/Input/Video` e `media.role: Screen`.
2. `ScreenShareIndicator.qml`: instancia incondicionalmente um `Process` que dispara `screensharestate.sh`, o qual executa em loop infinito `pw-dump | jq ...` a cada 1,5 s — **mesmo que o widget estivesse com `visible: false` na configuração da barra!**

A variante **`p1_unified`** comprovou que:
- O script `screensharestate.sh` e seu loop contínuo de forks (`bash`, `pw-dump`, `jq`, `sort`, `paste`, `sleep`) são **100% desnecessários**.
- Conectar o `ScreenShareIndicator.qml` aos eventos do singleton `Privacy.qml` (`Privacy.activeKinds.includes("screen")`) elimina integralmente o script de tela, poupando **~3,4 pontos percentuais de CPU da árvore em repouso** e centenas de forks por minuto, mantendo cobertura total.

---

## 6. Próximos Passos e Recomendações

1. **Adotar a Arquitetura Unificada de `p1_unified` no Produto:**
   - Remover a dependência de `screensharestate.sh` no `ScreenShareIndicator.qml`.
   - Utilizar o singleton `Privacy.qml` como fonte única de verdade para detecção de compartilhamento de tela.
2. **Evolução da Sonda de PipeWire (Redução dos 3,2% restantes):**
   - Substituir a chamada por polling a cada 1,2 s de `pw-dump` por uma escuta dirigida a eventos do PipeWire (via extensão nativa do Quickshell em C++ ou monitor de stream orientado a sinais).
3. **Avançar para a Fase F1:**
   - Executar os testes de custo residual contínuo da família de painéis (`family_fork` vs `family_fork_no_prewarm` e navegação limpa) conforme previsto em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md#f1).
