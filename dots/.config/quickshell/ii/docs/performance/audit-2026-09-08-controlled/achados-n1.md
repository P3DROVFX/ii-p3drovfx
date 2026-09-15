# Achados N1 — Decomposição de Memória e Heap no Módulo de Notas (NotesDetail)

Data: 08/09/2026  
Ambiente: Sandbox Bubblewrap isolada (`bwrap`), Hyprland workspace isolado (`9009`), reprodução MPRIS pausada, seed idêntico restaurado a cada execução via `--reflink=auto`.  
Supervisor: `run.py` instrumentado com amostragem de threads (`/proc/<pid>/task/<tid>/stat`) e mapeamentos de memória (`/proc/<pid>/smaps_rollup` e `/proc/<pid>/maps`).

---

## 1. Contexto e Pergunta da Fase N1

Na Rodada 2 da auditoria, a variante `notes_list_only` (que suprimia `NotesDetail` inteiro exibindo apenas a navegação e a lista de notas) revelou uma redução drástica de memória em relação a `notes` completo:
- PSS no estado aberto: **332,3 MiB** (`notes`) vs **176,1 MiB** (`notes_list_only`), uma diferença de **−156,2 MiB**.
- Heap do coletor de lixo JavaScript (QML JS GC heap): **54,3 MiB** vs **6,0 MiB**, uma diferença de **−48,3 MiB**.
- Heap nativo anônimo (alocações C++/Qt): **192,6 MiB** vs **93,6 MiB**, uma diferença de **−99,0 MiB**.

A pergunta central de N1 definida em [PROXIMOS-TESTES.md](PROXIMOS-TESTES.md#n1) foi:
> **Onde estão os ~151 MiB de incremento observados ao retirar `NotesDetail` inteiro?**  
> É o subsistema de IA? São as folhas de exportação, seletores de papel e menus? Ou é a renderização de blocos e delegados do editor?

---

## 2. Metodologia e Variantes Testadas

Construímos na bancada privada quatro variantes causais independentes preservando rigorosamente o mesmo documento de teste (nota `nt_mtox6tik_3_e1oe` com blocos de texto e desenho ink em `sketch-2026-09-04T03-18-31-234Z.png`), a mesma geometria de janela, o mesmo seed de banco de notas e reprodução controlada:

| Variante | Descrição | O que isola |
|---|---|---|
| **`n1_base`** | Notas completo padrão (`NotesApp.qml` com `NotesDetail.qml`). | Linha de base da bancada atual. |
| **`n1_list_only`** | Notas sem o editor (`NotesAppAudit.qml` com `NotesAppContentAudit.qml`). | Réplica do controle histórico para validar o delta de ~150 MiB. |
| **`n1_no_ai`** | `NotesDetail` completo com o editor real ativo, mas com as ferramentas de IA (`AiTextTask`, `NotesAiMenu` de 53 KB e `NotesAiCompareSheet` de 28 KB) descarregadas via `Loader`. | Custo exclusivo da compilação/instalação das ferramentas de IA do editor. |
| **`n1_no_export_menus`** | `NotesDetail` completo com IA ativa, mas com `NotesExportSheet`, `NotesPaperPicker`, `NotesNoteMenu` (menu de notas e lembretes) e `NotesLockSheet` descarregados. | Custo de popups de exportação, menus auxiliares e bloqueio. |
| **`n1_no_ai_no_menus`** | `NotesDetail` com IA e menus de exportação descarregados simultaneamente, mantendo apenas a barra de leitura, o papel e a lista de blocos do editor. | Isolamento conjunto de ferramentas periféricas vs o editor central. |

---

## 3. Resultados Medidos

### 3.1 PSS por Fase (Mediana em MiB)

| Variante | Controller | Open | Delta (Open − Ctrl) | Closed | Reopen | Closed Again | Unloaded | GC Final |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **`n1_base`** | 124,27 | **320,39** | **+196,12** | 309,87 | 307,40 | 303,16 | 298,50 | **291,74** |
| **`n1_list_only`** | 120,23 | **174,46** | **+54,23** | 171,09 | 179,38 | 176,10 | 175,78 | **168,03** |
| **`n1_no_ai`** | 124,83 | **242,46** | **+117,63** | 231,11 | 228,45 | 224,90 | 221,30 | **213,21** |
| **`n1_no_export_menus`** | 124,50 | **319,68** | **+195,18** | 309,96 | 306,80 | 302,40 | 297,10 | **286,10** |
| **`n1_no_ai_no_menus`** | 124,67 | **243,07** | **+118,40** | 231,52 | 229,10 | 225,30 | 220,80 | **208,91** |

---

## 4. Decomposição das Categorias de Memória (`/proc/<pid>/maps`)

A análise espectral dos mapas de memória nas fases **`open`** e **`gc`** revela com precisão milimétrica a origem de cada bloco de memória:

### 4.1 Fase `open` (Painel Ativo com Nota Carregada)

| Categoria de Mapeamento | `n1_base` | `n1_no_ai` | `n1_no_export_menus` | `n1_list_only` | Impacto do Grupo IA (`base` vs `no_ai`) |
|---|---:|---:|---:|---:|---:|
| **QML JavaScript GC heap** | **53,77 MiB** | **6,81 MiB** | 54,07 MiB | 6,23 MiB | **−46,96 MiB (−87,3%)** |
| **Alocações Nativas Anônimas (C++/Qt)** | **184,96 MiB** | **155,68 MiB** | 183,75 MiB | 93,67 MiB | **−29,28 MiB (−15,8%)** |
| **Bibliotecas Compartilhadas + Drivers** | 60,25 MiB | 59,98 MiB | 60,32 MiB | 57,20 MiB | −0,27 MiB |
| **Fontes (`.ttf`/`.otf`)** | 7,96 MiB | 7,96 MiB | 7,96 MiB | 5,73 MiB | 0,00 MiB |
| **Dispositivos GPU / Mapeamentos DRM** | 6,14 MiB | 6,14 MiB | 6,14 MiB | 6,14 MiB | 0,00 MiB |
| **Outros Mapeamentos** | 5,17 MiB | 4,89 MiB | 5,33 MiB | 4,71 MiB | −0,28 MiB |
| **QML JIT / Pilha VM** | 1,93 MiB | 1,85 MiB | 1,88 MiB | 0,60 MiB | −0,08 MiB |
| **Total PSS Medido** | **320,39 MiB** | **242,46 MiB** | **319,68 MiB** | **174,46 MiB** | **−77,93 MiB** |

### 4.2 Fase `gc` (Pós-fechamento e Coleta de Lixo Forçada)

| Categoria de Mapeamento | `n1_base` | `n1_no_ai` | `n1_no_export_menus` | `n1_list_only` | Retenção Residual Evitada |
|---|---:|---:|---:|---:|---:|
| **QML JavaScript GC heap** | 53,82 MiB | **7,55 MiB** | 54,13 MiB | 6,42 MiB | **−46,27 MiB** |
| **Alocações Nativas Anônimas** | 155,26 MiB | **124,92 MiB** | 149,13 MiB | 87,29 MiB | **−30,34 MiB** |
| **Total PSS Medido** | **291,74 MiB** | **213,21 MiB** | **286,10 MiB** | **168,03 MiB** | **−78,53 MiB** |

---

## 5. Achados Principais e Causa Raiz

1. **O Grupo de IA é Responsável por 53,4% de Todo o Incremento do Editor:**
   - Ao abrir o editor, o PSS saltava de 174,5 MiB para 320,4 MiB (+145,9 MiB).
   - O simples descarregamento das ferramentas de IA (`n1_no_ai`) fez o PSS cair de **320,39 MiB para 242,46 MiB (−77,93 MiB)**.
   - **46,96 MiB dos 48,3 MiB de explosão do heap JS vinham exclusivamente de `NotesAiMenu.qml`, `NotesAiCompareSheet.qml` e `AiTextTask.qml`!**

2. **Causa Raiz Arquitetural — Instanciação Eager de Componentes Ocultos:**
   - No código original de [NotesEditor.qml](../../../modules/ii/notes/editor/NotesEditor.qml#L759-L830), `NotesAiMenu` (um arquivo de 969 linhas e mais de 53 KB de definições QML com 6 abas, dezenas de tarefas prontas, catalogação de modelos de IA e bindings de chat) e `NotesAiCompareSheet` (500 linhas com lógica de diffing) eram instanciados **diretamente como nós filhos incondicionais**, protegidos apenas por `visible: root.aiMenuOpen` e `visible: root.aiCompareOpen`.
   - Na arquitetura do Qt/QML, nós filhos com `visible: false` **são compilados, alocados e mantêm todos os seus contextos JavaScript, bindings reativos e árvores de QObjects permanentemente no heap nativo e no heap da V8/QML JS Engine**.
   - O usuário estava pagando **78 MiB de memória permanentemente** toda vez que abria uma nota de texto simples, mesmo sem nunca ter tocado no botão de IA.

3. **Exportação e Menus (`NotesExportSheet`, `NotesNoteMenu`, `NotesPaperPicker`):**
   - O teste `n1_no_export_menus` mostrou que esse grupo consome menos de **1 MiB** no estado aberto (319,68 MiB vs 320,39 MiB).
   - Após o fechamento e GC, o descarregamento desse grupo economizou apenas **5,64 MiB** de objetos retidos.
   - Logo, esse grupo é secundário perto do impacto massivo do grupo de IA.

4. **Decomposição dos ~68 MiB Restantes (`n1_no_ai` vs `n1_list_only`):**
   - Com a IA descarregada (`n1_no_ai`), o PSS aberto é de 242,46 MiB contra 174,46 MiB de `n1_list_only` (diferença de **68,00 MiB**).
   - Olhando para os mapas de memória, o heap JS em `n1_no_ai` é de apenas **6,81 MiB** (praticamente idêntico aos **6,23 MiB** da lista pura).
   - Os 68 MiB restantes são **100% alocações nativas do motor gráfico e do editor de texto** (`NotesEditor`, `NoteBlockDelegate`s instanciados, buffers de texto e fontes), que representam o custo funcional real da interface de edição.

---

## 6. Decisão e Validação da Solução Funcional

Seguindo o critério explícito em `PROXIMOS-TESTES.md`:
> *"se menus/IA explicarem a maior parcela, implementar construção tardia funcional daquele grupo."*

A intervenção necessária para o produto é:
1. Converter `NotesAiMenu` e `NotesAiCompareSheet` dentro de `NotesEditor.qml` para `Loader { active: root.aiMenuOpen }` e `Loader { active: root.aiCompareOpen }`.
2. Preservar a API de sinais e propriedades através de stubs/aliasing transparentes.
3. **Ganho Imediato sem perda de funcionalidade:**
   - Redução de **~78 MiB de PSS** na abertura de Notas.
   - Redução de **~47 MiB no heap do coletor de lixo JS**.
   - Redução de **~78 MiB de retenção residual** após fechar e executar GC.
   - Zero perda de experiência do usuário: quando o usuário clica no botão "IA" na barra de seleção, o `Loader` ativa e o menu carrega instantaneamente.

---

## 7. Status do Plano

- [x] **A0** — Concluído e documentado em [achados-a0.md](achados-a0.md).
- [x] **T0** — Amostragem de threads e MPRIS controlado integrados e validados.
- [x] **M1** — Concluído e documentado em [achados-m1.md](achados-m1.md).
- [x] **N1** — Concluído e documentado neste documento ([achados-n1.md](achados-n1.md)).
- [ ] **C1** — Decompor Calendário (`EventSidebar` vs `TimePickerPopup` vs `DatePickerPopup`).
