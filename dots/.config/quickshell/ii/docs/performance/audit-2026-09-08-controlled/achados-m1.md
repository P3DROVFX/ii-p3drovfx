# Relatório de Achados — Fase M1 (Decomposição Causal de CPU no Media Mode)

Em conformidade com a seção 5 de [`PROXIMOS-TESTES.md`](PROXIMOS-TESTES.md#m1), esta etapa executou uma matriz controlada de 5 variantes para decompor causalmente os **57,5% a 60,2% de CPU** observados no Modo de Mídia com reprodução ativa (`Playing`) e modo estático (`visualizerMode: 0`).

Todos os ensaios foram realizados na bancada isolada com o player MPRIS controlado (`controlled_mpris.py`) garantindo estado de reprodução rigorosamente idêntico, contínuo e sem variações externas. A instrumentação da fase T0 coletou métricas de CPU discriminadas por thread (`/proc/<pid>/task/<tid>/stat`).

---

## 1. Matriz de Resultados Empíricos

| Variante do Teste | Descrição da Intervenção | CPU Quickshell Aberto | CPU Thread `qs` (UI/QML) | PSS Aberto | VRAM Aberta | CPU Quickshell Fechado | PSS Pós-GC |
|---|---|---:|---:|---:|---:|---:|---:|
| **`m1_base`** | Cenário estático base (`visualizerMode: 0`, Cava e listener ativos) | **60,2%** | **49,7%** | 420,8 MiB | 227,7 MiB | 1,0% | 332,9 MiB |
| **`m1_listener_off`** | `Connections` de Cava desabilitado no `MediaMode.qml` (Cava emite a 30 FPS) | **53,1%** | **44,4%** | 386,9 MiB | 231,7 MiB | 0,3% | 281,8 MiB |
| **`m1_producer_off`** | Subprocesso `cava` desabilitado em `CavaService.qml` (listener ativo aguardando) | **54,4%** | **44,6%** | 394,6 MiB | 202,4 MiB | 0,2% | 282,3 MiB |
| **`m1_gated`** | **Propriedade `live` dos visualizadores atrelada ao `visualizerMode` ativo** | **19,6%** | **16,7%** | **375,4 MiB** | 226,3 MiB | 0,3% | 272,2 MiB |
| **`m1_gated_listener_off`**| Visualizadores com `live` condicionado + listener de Cava desligado | **19,4%** | **16,5%** | 379,9 MiB | 226,3 MiB | 0,3% | 271,4 MiB |

---

## 2. A Descoberta da Causa Raiz Oculta

### 2.1 Por que o Cava e o Listener explicavam apenas ~6% a 7% de CPU?
- A supressão do `Connections` no `MediaMode.qml` (`m1_listener_off`) reduziu a CPU de 60,2% para 53,1% (**−7,1 pontos percentuais**).
- A supressão do subprocesso `cava` (`m1_producer_off`) reduziu a CPU de 60,2% para 54,4% (**−5,8 pontos percentuais**).
- Isso comprovou que o parsing a 30 FPS e a cópia de pontos em JavaScript são custosos, mas **não eram os responsáveis principais pelos outros ~50% de CPU**.

### 2.2 O "Loop Fantasma" do `WaveVisualizer` e `RadialWaveVisualizer`
Ao inspecionar o código de [`WaveVisualizer.qml`](../../../modules/common/widgets/WaveVisualizer.qml) e [`RadialWaveVisualizer.qml`](../../../modules/common/widgets/RadialWaveVisualizer.qml):
1. Ambos utilizam um componente `FrameAnimation` interno que executa código a cada quadro de VSync da tela (**60 a 144 FPS**).
2. A condição de execução de `FrameAnimation` em `WaveVisualizer.qml` é:
   ```qml
   FrameAnimation {
       running: root.live
       onTriggered: {
           ...
           root.requestPaint();
       }
   }
   ```
3. No [`MediaMode.qml`](../../../modules/ii/background/MediaMode.qml#L594), a instanciação era:
   ```qml
   Item {
       visible: root.visualizerMode === 1
       WaveVisualizer {
           live: root.player?.isPlaying ?? false
       }
   }
   ```
4. Em QML/QtQuick, definir `visible: false` em um `Item` pai **NÃO suspende** um `FrameAnimation` em execução dentro dele.
5. Como `live` verificava unicamente `root.player?.isPlaying`, o `FrameAnimation` continuava disparando de 60 a 144 vezes por segundo, executando interpolações LERP em JavaScript e invocando `requestPaint()` em um software Canvas 2D CPU (`renderTarget: Canvas.Image`) **mesmo com o visualizador completamente invisível na tela**!
6. O mesmo ocorria com o `RadialWaveVisualizer`.

### 2.3 A Prova Causal com `m1_gated`
Quando a propriedade `live` dos visualizadores foi corrigida para:
```qml
live: (root.visualizerMode === 1) && (root.player?.isPlaying ?? false)
```
e
```qml
live: (root.visualizerMode === 3) && (root.player?.isPlaying ?? false)
```
O consumo de CPU do processo Quickshell **despencou de 60,2% para 19,6%** (**uma redução espetacular de 40,6 pontos percentuais de um núcleo inteiro de CPU**)!

A thread principal do QML (`qs`) caiu de **49,7% de CPU para 16,7% de CPU**, e o PSS aberto caiu de 420,8 MiB para 375,4 MiB (**−45,4 MiB PSS economizados**).

---

## 3. Conclusão e Diretriz para o Código de Produção

1. **Bug Crítico Sanado:** O `MediaMode.qml` não pode instanciar `WaveVisualizer` e `RadialWaveVisualizer` continuamente com `live` baseado apenas no `isPlaying`.
2. **Recomendação Definitiva:**
   - Encapsular os modos de visualização em um `Loader` condicionado a `root.visualizerMode === <modo>` (evitando criar os componentes Canvas quando o modo não for o escolhido).
   - Condicionar a propriedade `live` de cada visualizador ao seu respectivo `visualizerMode`.
   - Adicionar flag de demanda (`consumerCount > 0`) em `CavaService.qml`, de modo que o binário externo `cava` também não consuma seus 2,8% de CPU quando nenhum visualizador estiver aberto.
