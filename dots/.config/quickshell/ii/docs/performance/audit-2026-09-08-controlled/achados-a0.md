# Relatório de Achados — Fase A0 (Análise Offline Aprofundada)

Em conformidade com a seção 3 do plano em [`PROXIMOS-TESTES.md`](PROXIMOS-TESTES.md#a0), esta etapa processou e cruzou todas as amostras temporais brutas da bancada controlada da Rodada 2, sem interromper a sessão ativa nem reiniciar processos.

Os dados estruturados foram consolidados em [`docs/performance/audit-2026-09-08-controlled/data/series-por-fase.json`](data/series-por-fase.json).

---

## 1. Localização do Custo: Processo Quickshell vs. Processos Auxiliares

### 1.1 Anomalia de CPU no Modo de Mídia (Media Mode)
O cruzamento temporal segundo a segundo revelou a divisão exata de responsabilidade da CPU no Modo de Mídia estático (`media_static` com `visualizerMode: 0` sob reprodução MPRIS ativa):

| Processo | PID Observado | Papel | CPU Média na Fase Aberta | PSS Mediano | Comportamento no Unload / Fechado |
|---|---:|---|---:|---:|---|
| **`qs` (Quickshell)** | 373235 | Processo principal | **57,53%** | 444,6 MiB | Cai para 3,2% fechado e 0,9% unloaded |
| **`cava`** | 374811 | Daemon de áudio Cava | **2,81%** | 5,1 MiB | **Continua rodando** no closed, unloaded e gc |
| **`nmcli`** | 374053 | Polling de rede | <0,05% | 3,8 MiB | Permanece ativo |
| **Outros helpers** | Vários | Scripts de letras/sync | <0,1% | ~16 MiB | Transitórios (reopen) |

> [!IMPORTANT]
> **Conclusão para M1:** O processo binário externo `cava` consome apenas **2,81% de CPU**. Os outros **~55% de CPU** são consumidos **dentro do próprio processo Quickshell (`qs`)**.
> A causa primária é a taxa de 30 FPS com que o `SplitParser` em C++ lê as 32 barras de áudio e emite `visualizerPointsChanged`, fazendo com que o `MediaMode.qml` reconstrua arrays JavaScript a cada ~33 ms mesmo com `visualizerMode: 0`.

---

## 2. Decomposição de Páginas de Memória (`maps`) no Notas

A comparação detalhada das categorias do `/proc/<pid>/smaps` entre o Notas completo (`notes`) e o Notas sem editor (`notes_list_only`) quantifica com precisão cirúrgica a origem dos 151,1 MiB de diferença:

| Categoria do Mapeamento | `notes` (Controlador) | `notes` (Aberto) | `notes` (Pós-GC) | `notes_list_only` (Aberto) | `notes_list_only` (Pós-GC) | Saldo Exclusivo do `NotesDetail` |
|---|---:|---:|---:|---:|---:|---:|
| **QML JavaScript GC heap** | 5,8 MiB | **54,3 MiB** | **54,4 MiB** | **6,0 MiB** | **6,4 MiB** | **+48,3 MiB PSS retidos** |
| **Anonymous native allocations** | 63,1 MiB | **192,6 MiB** | **159,3 MiB** | **93,6 MiB** | **86,4 MiB** | **+99,0 MiB PSS (72,9 MiB retidos)** |
| **Shared libraries & drivers** | 52,6 MiB | 63,0 MiB | 63,0 MiB | 59,1 MiB | 59,1 MiB | +3,9 MiB PSS |
| **Font files** | 0,0 MiB | 8,9 MiB | 8,5 MiB | 5,7 MiB | 5,4 MiB | +3,2 MiB PSS |
| **Device mappings (GPU)** | 0,0 MiB | 6,1 MiB | 7,1 MiB | 6,1 MiB | 6,1 MiB | 0,0 MiB |

> [!NOTE]
> **Conclusão para N1:** A UI interna do `NotesDetail` (editor de texto, canvas e menus de IA) é diretamente responsável por inflar o heap do JavaScript de 5,8 para 54,3 MiB (**+48,5 MiB de objetos JS** que **não são liberados pelo `gc()`**) e por gerar **99,0 MiB de alocações nativas** no heap C++.
> Quando `NotesDetail` não é instanciado, o heap JS cresce apenas **+0,2 MiB** (de 5,8 para 6,0 MiB).

---

## 3. Inventário Consolidado de Processos Auxiliares

Mapeamento de todos os processos filhos detectados na árvore do Quickshell durante os ensaios da Rodada 2:

| Processo / Script | Ocorrências | CPU % Média | PSS Observado | Sobrevivência ao Unload / Fechamento | Classificação |
|---|---:|---:|---:|---|---|
| **`cava`** | 5 casos | 2,1% – 2,4% | 5,1 – 5,2 MiB | **Sim** (Closed, Unloaded, GC) | Daemon órfão quando sem consumidores |
| **`privacy_probe.py`** | 4 casos | 1,4% | 13,6 – 14,8 MiB | **Sim** (Permanece ativo a cada 1,2 s) | Polling custoso de `/proc` |
| **`protonvpn`** | 23 casos | <0,1% | 6,2 – 38,8 MiB | **Sim** (Invocado periodicamente) | Pico transitório de memória |
| **`khal`** / **`vdirsyncer`** | 8 casos | <0,1% | 14,3 – 30,4 MiB | Não (Encerra após sincronização) | Auxiliar legítimo de calendário |
| **`localsend_bridge.py`** | 8 casos | <0,05% | 12,3 – 12,5 MiB | **Sim** (Daemon de recepção PTY) | Daemon sob demanda |
| **`localsend-cli`** | 8 casos | <0,05% | 6,4 – 6,8 MiB | **Sim** (Processo subjacente) | Daemon sob demanda |
| **`monitor.py` (KDE Connect)** | 8 casos | <0,1% | 15,9 – 16,0 MiB | **Sim** (Escuta DBus) | Daemon essencial de sessão |
| **`screensharestate.sh`** | 18 casos | <0,1% | 0,4 – 0,5 MiB | **Sim** (Loops de verificação) | Script shell contínuo |
| **`sleep`** | 625 casos | <0,01% | 0,1 MiB | **Sim** (Milhares de forks de timers bash) | Ineficiência de forks contínuos |
| **`magick`** / **`cc1plus`** | 4 casos | <0,1% | 67,8 – 134,8 MiB | Não (Encerra após compilar/converter) | Pico de shaders e imagens |

---

## 4. Próximos Passos Imediatos Definidos por A0

1. **Avançar para T0:** Instrumentar a bancada com medição de threads (`/proc/<pid>/task`) e controle estrito de reprodução MPRIS.
2. **Executar M1:** Construir as variantes `M-base`, `M-listener-off` e `M-producer-off` para confirmar que desabilitar o listener em QML elimina a maior fatia dos 57,5% de CPU sem precisar desligar o processo Cava.
3. **Executar N1:** Subdividir `NotesDetail` entre ferramentas de IA (`AiTextTask`), exportação e canvas, identificando qual fatia dos +48,3 MiB do heap JS pertence a cada componente.
