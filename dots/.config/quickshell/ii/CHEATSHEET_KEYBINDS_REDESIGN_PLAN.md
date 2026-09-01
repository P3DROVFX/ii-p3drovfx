# Plano de redesign — Cheatsheet Keybinds

> Status: planejamento de produto, UX e arquitetura — nenhuma implementação incluída neste documento
>
> Data da auditoria: 2026-08-26
>
> Escopo principal: descoberta de atalhos, páginas de programas, atalhos personalizados, criação rápida individual/em lote, importação, detecção e estados de recuperação

## 1. Resultado pretendido

O Cheatsheet deve funcionar como uma biblioteca local de atalhos que o usuário consegue abrir, consultar e alimentar sem interromper o que estava fazendo. A experiência final precisa atender a três tarefas com a mesma qualidade:

1. **Encontrar um atalho em poucos segundos**, mesmo sem saber em qual página ou categoria ele está.
2. **Criar um ou muitos atalhos em sequência**, com o mínimo de repetição e sem perder rascunhos ao fechar o overlay.
3. **Obter uma base útil automaticamente**, com catálogos extensos de programas conhecidos e importadores que distinguem defaults, extensões e personalizações do usuário.

O produto não deve ser apenas uma coleção de cards. Ele deve combinar busca global, contexto do aplicativo ativo, navegação por páginas, categorias priorizadas e uma camada de dados capaz de atualizar catálogos sem apagar personalizações.

## 2. Regras inegociáveis do projeto

- Preservar o Cheatsheet como navegação interna do overlay; criação de página e edição não devem virar janelas independentes.
- `KeybindsService.qml` continua sendo o único escritor da biblioteca de atalhos.
- Não fazer varredura de programas no boot, polling periódico ou execução silenciosa da configuração de terceiros.
- Detecção automática deve ser assíncrona, limitada, cacheada e iniciada somente ao abrir Keybinds/Adicionar fonte ou por ação explícita.
- Usar os tokens de `Appearance` para cores, tipografia, arredondamento e movimento.
- Não usar bordas, animações de pulse ou scale decorativo.
- Reutilizar os widgets do projeto antes de criar controles básicos.
- Um atalho continua sendo uma única cápsula visual. Não criar um `Rectangle` separado para cada tecla.
- Listas persistentes em `JsonObject` devem usar `list<string>` ou `list<var>`, nunca `property var` aninhada.
- Toda nova persistência deve seguir escrita atômica, guarda de inicialização e retry-then-create.
- Toda interface deve funcionar com teclado, alvos de interação de pelo menos 44×44 px e foco visível.
- Fechar o overlay, mudar de aba ou ocorrer hot reload nunca pode descartar silenciosamente um rascunho.

## 3. Diagnóstico do estado atual

### 3.1 Pontos sólidos que devem ser preservados

- Separação entre atalhos Hyprland, páginas pessoais e catálogos importáveis.
- Biblioteca personalizada escrita de forma atômica, com validação e detecção de conflito externo.
- `KeybindShortcutSequence.qml` já centraliza parte da apresentação dos atalhos.
- Criação de página em tela interna, em vez de popup frágil.
- Importador externo em Python separado da camada visual.
- Possibilidade de associar páginas a aplicativos instalados e usar seu ícone.
- Dados opcionais de categoria, contexto, notas e ícone sem bloquear a criação básica.

### 3.2 Problemas P0 — quebram ou interrompem o workflow

| Problema                                                | Evidência atual                                                                                            | Impacto                                                    | Direção da correção                                                                   |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| Rascunho desaparece ao fechar o Cheatsheet              | O `Loader` em `Cheatsheet.qml` é desativado após o fechamento e os formulários mantêm estado somente local | Perda de trabalho e medo de fechar para conferir um atalho | Persistir rascunho, rota e posição; restaurar exatamente o editor ao reabrir          |
| Criar vários atalhos exige reabrir o editor a cada item | O fluxo de criação salva e fecha a sidebar                                                                 | Alto custo para montar uma página                          | Adicionar `Adicionar e próximo`, retenção inteligente de campos e modo em lote        |
| CTA de criar página some para baixo                     | Coluna esquerda fixa, grade grande de ícones e ausência de rolagem/footer sticky                           | Fluxo fica incompleto em telas baixas ou com mais conteúdo | Layout responsivo com região rolável e ação primária sempre visível                   |
| Símbolo inexistente vira texto `SIDEBAR`                | Uso de `MaterialSymbol` sem validação/fallback                                                             | Aparência quebrada e pouco confiável                       | Registro validado de símbolos e fallback; substituir por símbolo existente            |
| Importação fecha a tela antes de confirmar sucesso      | A página inicia o processo e começa a fechar imediatamente                                                 | Erro ou import parcial perde contexto e feedback           | Manter tela aberta até validação/escrita concluírem; preview, progresso e recuperação |
| Fechar/Cancelar estão duplicados                        | X no topo e Cancelar no rodapé; Delete também compete no topo                                              | Hierarquia confusa e mais densidade                        | Uma única ação de conclusão/fechamento; destrutivas em overflow ou zona secundária    |

### 3.3 Problemas P1 — prejudicam descoberta, escala e clareza

- A busca é local à página, literal e sem ranking. Não existe busca única sobre Hyprland, páginas pessoais e catálogos.
- Não existe entendimento de aplicativo ativo; o usuário precisa descobrir manualmente onde procurar.
- Categorias seguem ordem incidental e não importância.
- VS Code, Neovim e IntelliJ têm apenas 20 itens cada; os templates são starters, não referências abrangentes.
- O importador do VS Code ignora defaults, perfis e keybinds contribuídos por extensões.
- O parser estático do Neovim cobre apenas parte das APIs e não enxerga mappings criados em runtime ou buffer-local.
- Renderização com `Repeater` e cálculo de masonry repetitivo tende a degradar com centenas ou milhares de atalhos.
- A rail mistura navegação, ações e estado sem hierarquia forte; no modo recolhido, criar/importar ficam pouco acessíveis.
- Muitas ações usam áreas menores que o alvo mínimo recomendado.
- Icon buttons, toasts e erros não têm uma cobertura consistente de nomes acessíveis, foco e anúncio.
- A apresentação do chord não possui tokenizer robusto para sequência, alternativa, tecla literal `+`, `<leader>` e layouts diferentes.
- Não há detecção de duplicidade ou conflito entre default, extensão, importado e override do usuário.

### 3.4 Problemas P2 — refinamento e robustez

- Excesso de cards aninhados, toggles, campos e chips aumenta densidade no editor.
- Ícone decorativo da ação, contexto e chevron aparecem ao mesmo tempo em rows pequenas.
- Estados vazio, loading, erro, catálogo não escaneado e zero resultados são pouco diferenciados.
- A grade completa de ícones aparece cedo demais para uma decisão secundária.
- Ação de excluir em dois cliques não oferece o modelo mais claro; undo após exclusão é mais seguro e rápido.
- Animações estão espalhadas e algumas usam duração/easing locais, dificultando reduced motion.
- Não existe indicador de procedência, versão, confiança ou atualização de um atalho importado.
- Não há ferramentas de favoritos, recentes, ocultar default ou comparar atualizações.

### 3.5 Mapa de intervenção no código atual

| Arquivo atual                                              | Responsabilidade afetada | Mudança planejada                                                                         |
| ---------------------------------------------------------- | ------------------------ | ----------------------------------------------------------------------------------------- |
| `modules/ii/cheatsheet/Cheatsheet.qml`                     | Lifecycle do tab/Loader  | Separar lifecycle visual do estado de rota/rascunho; capturar contexto da janela anterior |
| `modules/ii/cheatsheet/CheatsheetKeybinds.qml`             | Shell, rail e roteamento | Busca global, seções da rail, footer sticky, rotas persistíveis e layout adaptativo       |
| `modules/ii/cheatsheet/CheatsheetHyprlandKeybinds.qml`     | Página de sistema        | Renderer compartilhado, categorias priorizadas, estados de erro e virtualização           |
| `modules/ii/cheatsheet/CheatsheetCustomKeybindsPage.qml`   | Páginas pessoais         | Remover busca literal/O(n²), adicionar visão Essenciais/Todos e rows virtualizadas        |
| `modules/ii/cheatsheet/CheatsheetKeybindEditorSidebar.qml` | Criar/editar             | Gravador, formulário progressivo, add-next, undo e hierarquia de ações sem duplicação     |
| `modules/ii/cheatsheet/CheatsheetKeybindsPageForm.qml`     | Criar página/importar    | Fluxo source-first, rolagem, CTA sticky, preview/diff e icon fallback                     |
| `modules/ii/cheatsheet/KeybindShortcutSequence.qml`        | Chord visual             | Tokenizer/registry único, modifier glyphs, acessibilidade e sequências multiestágio       |
| `services/KeybindsService.qml`                             | Fonte de verdade         | Schema v2, base/overlay, merge, transações, undo e APIs de sync                           |
| `modules/common/Persistent.qml`                            | Estado persistente de UI | Guardar apenas preferência/seleção estável; delegar rascunhos ao store próprio            |
| `scripts/keybinds/import_keybinds.py`                      | Importação externa       | Dispatcher de adapters, diagnósticos estruturados, timeout/cancelamento e DTO normalizado |
| `defaults/keybinds/templates.json`                         | Starters atuais          | Migrar para índice + packs versionados extensos; manter migração/compatibilidade          |
| `scripts/tests/test_keybinds_feature_contract.py`          | Contratos                | Cobrir glyphs, virtualização, drafts, sticky CTA, ações e regras visuais                  |
| `scripts/tests/test_keybinds_import.py`                    | Parsers                  | Fixtures por programa, precedência, erros, limites e procedência                          |

## 4. Princípios de produto e UX

1. **Busca primeiro, navegação quando útil.** O campo global deve resolver a maioria das consultas; páginas e categorias ajudam exploração e aprendizado.
2. **Contexto antes de configuração.** Ao abrir, oferecer o aplicativo que estava em foco antes do overlay.
3. **Uma ação primária por estado.** A tela deixa evidente se a próxima ação é adicionar, salvar, importar ou concluir.
4. **Progressive disclosure.** Tecla e ação ficam sempre visíveis; categoria, contexto, notas e aparência entram como opções secundárias.
5. **Defaults e personalizações são camadas distintas.** Atualizar um catálogo nunca sobrescreve notas, favoritos, remapeamentos ou itens manuais.
6. **O dado não desaparece.** Autosave de rascunho, preview de importação, undo e conflitos explícitos substituem descartes silenciosos.
7. **Teclado é o caminho principal, mouse é equivalente.** Abrir, buscar, navegar, criar e salvar devem ser possíveis sem tirar as mãos do teclado.
8. **Automação local e explicável.** Mostrar o que foi detectado, de onde veio e quando foi atualizado.
9. **Escala real.** O design deve funcionar igualmente com 0, 20, 300 ou 10.000 atalhos.

## 5. Metas mensuráveis

### 5.1 Velocidade de consulta

- Campo de busca focado automaticamente quando o Cheatsheet for aberto diretamente em Keybinds.
- Primeiro resultado útil em até três interações: abrir, digitar, selecionar.
- Sugestão do aplicativo anteriormente ativo disponível sem navegar pela rail.
- Busca quente P95 abaixo de 50 ms para 5.000 itens indexados.
- Abertura quente do módulo abaixo de 150 ms; abertura fria abaixo de 300 ms para uma biblioteca típica.

### 5.2 Velocidade de criação

- Criar um atalho simples com no máximo: gravar chord, escrever ação, confirmar.
- Criar dez atalhos sem fechar/reabrir editor.
- Atalhos subsequentes podem herdar categoria e contexto por opção explícita.
- Fechar e reabrir deve restaurar 100% dos campos e a rota anterior.

### 5.3 Cobertura inicial

- VS Code: pelo menos 250 regras Linux úteis ou o conjunto oficial completo normalizado; nunca menos de 100.
- Neovim: pelo menos 150 atalhos core curados por modo/categoria; nunca menos de 100.
- IntelliJ IDEA: ampliar para pelo menos 150 atalhos do keymap selecionado.
- Cada catálogo tem uma visão `Essenciais` com 20–30 itens prioritários e uma visão `Todos` completa.
- Catálogos devem ter IDs estáveis, fonte, versão, aliases do aplicativo e ordem explícita de categorias.

### 5.4 Qualidade da interface

- Alvos interativos de no mínimo 44×44 px; 48×48 px nas ações principais.
- Contraste de texto normal de pelo menos 4.5:1 e foco sempre visível.
- Nenhum símbolo inválido pode aparecer como texto bruto.
- Nenhuma ação primária pode ficar inacessível por altura ou largura reduzida.
- Listas com mais de 50 itens devem ser virtualizadas.

## 6. Arquitetura de navegação proposta

### 6.1 Estados de alto nível

O módulo passa a ter cinco rotas internas persistíveis:

1. `library` — busca global, página selecionada e navegação normal.
2. `pageCreate` — adicionar uma fonte/página.
3. `keybindCreate` — criar um ou vários itens.
4. `keybindEdit` — editar item existente.
5. `bulkImport` — colar ou importar muitos itens com preview.

A rota não pode depender apenas da existência de um `Loader`. Ela deve ser representada em estado persistente e reidratada quando o componente for recriado.

### 6.2 Cabeçalho principal

- Título `Keybinds` e contexto atual em primeiro nível.
- Busca global larga e sempre disponível.
- Chip de escopo: `Aplicativo atual`, `Tudo`, `Meus atalhos`, `Defaults`.
- Ação primária `Adicionar` abre um pequeno menu: `Atalho`, `Vários atalhos`, `Página ou programa`, `Importar arquivo`.
- Ações raras ficam em overflow: atualizar fontes, exportar biblioteca, preferências de exibição.

### 6.3 Rail de páginas

Dividir a rail em seções claras:

- **Agora:** aplicativo que estava ativo antes do overlay, quando reconhecido.
- **Sistema:** Hyprland e outros provedores do desktop.
- **Aplicativos:** catálogos instalados/detectados.
- **Pessoais:** páginas manuais e importadas sem associação.

Regras visuais e de interação:

- Background da rail em container discreto; seleção em `primaryContainer` ou `secondaryContainer`, sem border.
- Ícone do programa com 40 px, nome, contagem e pequena origem somente quando necessário.
- Footer sticky fora da lista rolável. Adicionar permanece visível em rail expandida e recolhida.
- Em modo recolhido, tooltip e nome acessível completos; ação `Adicionar` continua presente.
- Mais de 50 páginas usam lista virtualizada.
- Favoritos e recentes podem aparecer no topo, limitados e sem duplicar semanticamente a página.
- Drag-and-drop deve ter alternativa por teclado/menu: mover para cima, mover para baixo, fixar no topo.

### 6.4 Área de conteúdo

Dois modos complementares:

- **Pesquisar:** lista virtualizada de resultados de todas as fontes, agrupada quando útil.
- **Explorar página:** cabeçalho, categorias, visão `Essenciais` e `Todos`, com jump navigation.

Não manter masonry irrestrito para datasets grandes. Cards de categoria podem continuar em um overview pequeno, mas o conteúdo expandido e resultados devem usar `StyledListView` ou equivalente virtualizado.

## 7. Workflow de consulta rápida

### 7.1 Abertura contextual

1. Antes do overlay tomar foco, capturar `desktopId`, classe e título da janela ativa.
2. Resolver esses dados contra aliases dos catálogos: `code`, `Code - OSS`, `VSCodium`, `Cursor`, `nvim`, `kitty`, etc.
3. Se houver correspondência, mostrar chip `Visual Studio Code — aplicativo anterior` e priorizar seus resultados.
4. Se não houver, preservar a última página usada e oferecer `Criar página para <aplicativo>` quando o aplicativo for identificável.
5. Nunca mudar a página silenciosamente enquanto o usuário já estiver digitando ou editando.

### 7.2 Busca global

Pesquisar em:

- chord canônico e sua forma visual;
- descrição/ação;
- categoria, modo/contexto;
- tags, sinônimos e comandos associados;
- programa, página e origem;
- notas do usuário.

Aceitar dois modos de entrada:

- Texto natural: `mover linha`, `split vertical`, `abrir terminal`.
- Chord gravado ou digitado: `Super+Shift+Enter`, `Ctrl+K Ctrl+S`, `<leader>ff`.

Ranking recomendado:

1. chord exato;
2. ação exata;
3. prefixo de ação ou chord;
4. alias/tag exato;
5. correspondência fuzzy;
6. texto em notas/contexto.

Boosts aplicados depois da relevância textual:

1. aplicativo anterior;
2. página selecionada;
3. override ou item personalizado do usuário;
4. favorito;
5. item essencial;
6. prioridade do catálogo;
7. default comum.

Busca nunca deve esconder itens `Todos` só porque a tela está em `Essenciais`.

### 7.3 Resultado

Cada resultado mostra somente:

- cápsula do chord;
- ação em uma linha, com wrap controlado em telas estreitas;
- programa/página como contexto secundário;
- modo somente quando altera o significado;
- badge de conflito, personalizado ou origem somente quando relevante.

Interações:

- setas navegam;
- `Enter` abre detalhes ou edição quando permitido;
- `Ctrl+C` copia o chord do item focado;
- `/` ou atalho configurado volta o foco à busca;
- `Esc` primeiro limpa a busca, depois fecha o módulo apenas se não houver editor/rascunho ativo.

### 7.4 Exploração por página

- `Essenciais` é a primeira categoria lógica para catálogos grandes.
- Barra de categorias com contagem, navegável por teclado e sticky quando necessário.
- Categorias seguem prioridade explícita, não ordem acidental de importação.
- Cards de categoria recolhidos exibem uma amostra limitada e `Ver todos (N)`.
- Header da página tem somente `Adicionar atalho` como ação principal; editar página, exportar e excluir ficam no overflow.
- Excluir página cria undo temporário; confirmação adicional é usada somente quando houver perda não recuperável.

## 8. Workflow de criação de um ou vários atalhos

### 8.1 Entrada rápida

- `Ctrl+N` ou `Adicionar → Atalho` abre a rail à direita.
- Se a página atual for somente leitura, selecionar automaticamente a camada pessoal associada ou pedir o destino uma única vez.
- O primeiro foco é o gravador de chord.
- A rail exibe o nome da página de destino no header, permitindo troca sem fechar.

### 8.2 Gravador de chord

Comportamento necessário:

- Capturar modificadores e tecla em vez de depender só de texto livre.
- Suportar chords multiestágio e mostrar claramente a separação entre estágios.
- `Esc` cancela a gravação atual, não fecha toda a rail.
- `Backspace` limpa o estágio; `Enter` aceita; um botão permite edição textual manual.
- Normalizar `Meta/Super`, `Ctrl/Control`, `Alt`, `Shift`, casing e nomes de teclas.
- Não confundir `+` como tecla com `+` como separador.
- Suportar `<leader>`, scan codes, mouse buttons e sequências específicas do programa via representação raw quando a forma estruturada não for possível.
- Detectar conflito na mesma página/contexto antes de salvar e oferecer: substituir, manter ambos, mudar contexto ou cancelar.

### 8.3 Formulário simplificado

Primeiro nível sempre visível:

- `Atalho` — obrigatório.
- `Ação` — obrigatório.

Segundo nível em `Organizar e detalhar`:

- Categoria sugerida.
- Modo/contexto.
- Tags/sinônimos.
- Nota.
- Ícone opcional, somente se realmente ajudar a leitura.

Remover cartões individuais grandes para cada campo. Usar uma única superfície organizada, espaçamento maior e labels persistentes. A preview permanece compacta e atualiza ao vivo.

### 8.4 Ações do editor

Modo criação:

- Primária: `Adicionar e próximo`.
- Secundária: `Adicionar e concluir`.
- Header: `Concluir` fecha preservando o que já foi salvo; se há conteúdo incompleto, ele vira rascunho.

Modo edição:

- Primária: `Salvar`.
- Header: um único `Fechar`.
- `Excluir atalho` fica no overflow ou em seção destrutiva ao fim do conteúdo, seguido de toast com `Desfazer`.
- Não mostrar X e Cancelar com a mesma semântica.

Atalhos sugeridos:

- `Ctrl+Enter`: adicionar/salvar e continuar.
- `Ctrl+Shift+Enter`: adicionar/salvar e concluir.
- `Ctrl+N`: iniciar próximo item quando os dados atuais já estiverem salvos.
- `Esc`: sair do subestado atual; nunca descartar dados autosalvos.

### 8.5 Modo sequência

Depois de `Adicionar e próximo`:

- inserir o item imediatamente na página;
- rolar e aplicar um highlight tonal one-shot no novo item;
- limpar chord e ação;
- manter categoria/contexto somente quando os chips `Manter categoria`/`Manter contexto` estiverem ativos;
- mostrar contador `7 adicionados nesta sessão`;
- permitir desfazer o último item sem sair do fluxo;
- lembrar o destino durante toda a sessão.

### 8.6 Criação em lote

Oferecer uma rota específica, não uma textarea escondida no editor:

- Colar TSV/CSV ou linhas no formato `atalho — ação`.
- Importar JSON compatível.
- Preview tabular virtualizado.
- Mapear colunas para chord, ação, categoria, contexto e notas.
- Mostrar válidos, inválidos, duplicados e conflitos antes de gravar.
- Permitir correção inline dos itens inválidos.
- Ação final informa quantidade real: `Adicionar 84 atalhos`.
- Uma transação falha por inteiro quando a escrita não puder ser concluída; nunca deixar estado parcial silencioso.

## 9. Preservação de rascunho e retomada

### 9.1 Estado a persistir

- rota atual;
- página e item alvo;
- campos do formulário;
- estado do acorde em gravação;
- acorde raw e estruturado;
- seções expandidas;
- opções de retenção da criação em sequência;
- query e escopo de busca;
- posição de scroll da rail e conteúdo;
- timestamp, revisão/hash base e status dirty.

### 9.2 Armazenamento

Criar um store dedicado, por exemplo `KeybindDrafts.qml`, com arquivo em:

```text
~/.local/state/quickshell/user/keybind_drafts.json
```

Requisitos:

- escrita atômica;
- guarda de inicialização;
- retry-then-create;
- debounce curto de autosave;
- estrutura compatível com as regras de tipagem do Quickshell;
- limite e expiração de rascunhos antigos;
- nenhum dado sensível além do que o usuário digitou na própria biblioteca.

### 9.3 Reabertura

- Se existe rascunho, reabrir exatamente a rota anterior e mostrar `Rascunho recuperado` com ação `Descartar`.
- Fechar o overlay não exige modal porque o rascunho já está seguro.
- Em edição, comparar revisão/hash do item original. Se ele mudou externamente, oferecer comparar, manter cópia ou descartar; nunca sobrescrever silenciosamente.
- Trocar de aba preserva o estado sem manter obrigatoriamente toda a árvore visual viva.
- Após salvar ou descartar, limpar somente o rascunho correspondente.

## 10. Redesign de criação de página/programa

### 10.1 Tela orientada à origem

Substituir a ênfase inicial em `nome + grade de ícones` por quatro escolhas:

1. **Aplicativo instalado** — caminho recomendado.
2. **Catálogo conhecido** — mesmo quando o aplicativo não está instalado.
3. **Importar arquivo** — JSON ou fonte suportada.
4. **Página em branco** — caminho manual.

O topo mostra o aplicativo anterior quando suportado: `Adicionar atalhos do Visual Studio Code`.

### 10.2 Aplicativo instalado ou catálogo

Ao selecionar um programa:

- preencher nome e ícone automaticamente;
- mostrar o que está disponível: `250 defaults`, `18 personalizados`, `42 de extensões`;
- permitir escolher camadas a importar;
- explicar a origem e a data da fonte;
- fornecer preview e conflitos antes da escrita;
- deixar `Personalizar aparência` recolhido, com nome/ícone override.

Remover o toggle `Usar ícone do app na sidebar` do fluxo principal. O comportamento padrão é usar o ícone do app; um override manual vive em `Personalizar aparência`.

### 10.3 Página em branco

- Nome é o único campo obrigatório.
- Ícone padrão válido é inferido; escolher outro é opcional.
- A grade de ícones inicia recolhida ou com favoritos/recentes e busca.
- Todos os símbolos passam por registro de ícones válidos e fallback.
- Programa relacionado é opcional e pesquisável; não renderizar toda a lista de apps sem virtualização.

### 10.4 Layout responsivo

- Tela larga: seleção/origem à esquerda e preview/detalhes à direita.
- Tela estreita ou baixa: coluna única, uma única rolagem principal.
- Quando houver duas colunas, cada região longa precisa de rolagem previsível.
- Footer sticky contém somente a ação primária e nunca é empurrado pela grade, app preview ou mensagens.
- Conteúdo deve funcionar em 1280×720, 1366×768, ultrawide e com texto ampliado.

### 10.5 Importação segura

Fluxo obrigatório:

1. selecionar fonte;
2. ler/analisar;
3. mostrar preview/diff;
4. escolher merge;
5. gravar;
6. confirmar sucesso;
7. navegar para a página criada/atualizada.

Não fechar a tela entre os passos 2 e 6. Falha, cancelamento ou timeout preservam seleção e mensagens de recuperação.

## 11. Nova row de atalho

### 11.1 Hierarquia

- Altura mínima de 48 px.
- Chord como elemento de leitura mais reconhecível, mas não necessariamente o maior texto.
- Ação com peso tipográfico principal.
- Programa/categoria/contexto em texto secundário apenas quando necessário.
- Espaço respirável consistente; sem bordas.
- Ação de editar aparece no foco/hover e também é alcançável pelo teclado; não depender apenas de hover.
- Remover chevron permanente e ícone decorativo da ação por padrão.

### 11.2 Cápsula do chord

Manter uma única cápsula para a sequência completa. Dentro dela:

- Super/Meta, Ctrl, Alt e Shift usam glyph validado quando disponível;
- tecla principal usa texto curto e fonte apropriada;
- `+` representa combinação somente visualmente;
- seta ou separador claro representa estágios de um chord;
- alternativa usa separador diferente de sequência;
- fallback textual preserva a informação quando não houver glyph;
- tooltip e `Accessible.name` sempre expõem a forma completa, por exemplo `Control mais K, depois Control mais S`.

O uso de símbolo para modificadores não deve depender de `useMacSymbol`; essa preferência pode selecionar estilo, mas não decidir se a informação é legível.

### 11.3 Tokenizer compartilhado

Criar uma única implementação usada por:

- atalhos Hyprland;
- páginas personalizadas;
- preview do editor;
- busca por chord;
- detecção de conflitos;
- importadores.

O tokenizer deve produzir uma estrutura como:

```text
sequence[]
  stage[]
    modifiers[]
    key
    raw
alternatives[]
```

Não duplicar mapeamentos de modificadores em múltiplos QMLs.

## 12. Categorias, prioridade e personalização

### 12.1 Ordem de categorias

1. categoria fixada/ordenada pelo usuário;
2. `Essenciais`;
3. rank definido no catálogo;
4. maior prioridade dos itens da categoria;
5. ordem alfabética localizada.

Exemplo para Neovim:

1. Essenciais
2. Movimento
3. Edição
4. Seleção/Visual
5. Busca
6. Arquivos/Buffers
7. Janelas/Tabs
8. Comandos
9. Macros/Registers
10. Avançado

Exemplo para VS Code:

1. Essenciais
2. Navegação
3. Edição
4. Busca
5. Arquivos
6. Editor/Grupos
7. Terminal
8. Debug
9. Source Control
10. Preferências/Acessibilidade

### 12.2 Ordem de atalhos

1. favorito;
2. override ou personalizado do usuário;
3. essencial;
4. prioridade numérica;
5. nome da ação.

### 12.3 Ações pessoais sobre defaults

- Favoritar.
- Adicionar nota/tag.
- Remapear, criando override.
- Ocultar default sem excluí-lo do catálogo.
- Restaurar default.
- Ver procedência e versão.
- Comparar quando um catálogo atualizado alterar o mesmo `actionId`.

## 13. Modelo de dados e catálogos v2

### 13.1 Separar base e overlay

Não duplicar todo o catálogo dentro da página do usuário. Modelar:

- **Base pack:** defaults versionados, somente leitura.
- **Overlay do usuário:** adições, overrides, favoritos, notas e tombstones/itens ocultos.
- **Camada detectada:** personalizações encontradas em arquivos, extensões ou runtime.

A visualização resolve as camadas. Uma atualização da base não apaga o overlay.

### 13.2 Metadados do catálogo

```text
id
name
appIds[]
aliases[]
platform
keymapVariant
version
sourceUrl
license
generatedAt
categoryOrder[]
minimumItemCount
```

### 13.3 Metadados do atalho

```text
id
actionId
sequence
rawKeys
displayKeys
description
categoryId
category
modeOrContext
command
tags[]
synonyms[]
priority
essential
origin             # core, extension, user, manual, imported
confidence         # authoritative, static, runtime, inferred
source
sourceVersion
favorite
disabled
```

### 13.4 Metadados da página/overlay

```text
basePackId
sourceRefs[]
additions[]
overrides[]
hiddenDefaults[]
categoryOrder[]
pinnedCategories[]
lastScanAt
lastSourceFingerprint
```

### 13.5 Migração

- Bibliotecas v1 continuam válidas como páginas manuais/snapshots.
- Migração é idempotente e cria backup recuperável antes de alterar schema.
- Nunca inferir silenciosamente que um item manual é igual a um default; usar `actionId + contexto + chord` e confirmar casos ambíguos.
- IDs dos catálogos são estáveis entre versões.
- Downgrade deve manter uma exportação v1 possível quando não houver perda crítica.

## 14. Construção e atualização dos catálogos

### 14.1 Estratégia

- Gerar catálogos em desenvolvimento/build a partir de fontes oficiais ou dados versionados, não raspar a web no runtime.
- Bundlar catálogos offline com o shell.
- Atualizá-los junto às releases do projeto ou por pacote assinado/versionado no futuro.
- Registrar fonte, licença, plataforma, data e transformações.
- Validar quantidade mínima, IDs únicos, categorias conhecidas, glyphs válidos e chords parseáveis em CI.

### 14.2 VS Code

Entregáveis:

- catálogo Linux abrangente, meta mínima de 250 regras;
- aliases para Visual Studio Code, Code OSS, VSCodium e Cursor, sem presumir que todos têm exatamente os mesmos defaults;
- categorias e prioridades próprias;
- comandos sem binding também podem ser pesquisáveis como ações, mas precisam ser visualmente distintos;
- suporte a chords e regras condicionais (`when`).

A documentação oficial explica que as regras são avaliadas de baixo para cima, que regras do usuário são adicionadas ao fim, que remoções usam comandos prefixados por `-` e que chords têm estágios separados por espaço. O importador deve reproduzir essa semântica ao resolver o resultado efetivo.

### 14.3 Neovim

Entregáveis:

- catálogo core com meta mínima de 150 atalhos;
- separação por Normal, Insert, Visual, Select, Operator-pending, Command e Terminal;
- prioridades distintas para movimento básico, edição, busca, buffers, janelas, registers, macros e comandos avançados;
- representação correta de `<leader>`, `<localleader>`, `<C-x>`, teclas especiais e sequências.

Defaults core, mappings estáticos do usuário e mappings de runtime devem ser camadas distintas.

### 14.4 IntelliJ/JetBrains

- Catálogo base por keymap e plataforma, meta mínima de 150 atalhos.
- Resolver o keymap pai e os overrides XML do usuário.
- Identificar IDE e variantes sem duplicar páginas desnecessariamente.
- Categorias: navegação, edição, geração de código, refactor, run/debug, VCS, ferramentas e preferências.

## 15. Detecção e importação por programa

### 15.1 Contrato comum de adapters

Cada adapter deve declarar:

- IDs/aliases de aplicativo;
- caminhos candidatos;
- tipos de fonte suportados;
- se é leitura estática ou runtime opt-in;
- limites de arquivo, tempo e itens;
- versão do parser;
- procedência e confiança de cada resultado;
- erros recuperáveis com mensagem estruturada.

Saída normalizada:

```text
DetectedSource
ScanResult
NormalizedKeybind[]
Diagnostic[]
```

Todo subprocesso precisa de timeout, cancelamento, limite de output, exit code e stderr tratados. A UI recebe progresso e não bloqueia.

### 15.2 VS Code e família

Escanear, quando solicitado:

- `User/keybindings.json`;
- perfis em `User/profiles/*/keybindings.json`;
- instalações nativas, Flatpak e Snap conhecidas;
- `package.json` de extensões instaladas com `contributes.keybindings` e `contributes.commands`;
- campos por plataforma, especialmente `linux`;
- `when`, remoções e precedência das regras.

Separar no preview:

- defaults core;
- extensões;
- usuário/perfil;
- conflitos e comandos removidos.

### 15.3 Neovim

Três níveis, sempre explícitos:

1. **Estático seguro — padrão:** ampliar parser para `vim.keymap.set`, `vim.api.nvim_set_keymap`, `vim.api.nvim_buf_set_keymap`, formas Vimscript, tabelas comuns do lazy.nvim e registros which-key que sejam estaticamente determináveis.
2. **Instância já aberta — recomendado quando disponível:** com consentimento, conectar a um server Neovim já existente e consultar mappings globais e buffer-local. Não iniciar nova configuração.
3. **Scan live headless — avançado:** opção explícita com aviso de que a configuração/plugins serão executados; processo isolado, timeout, cancelamento e nenhum uso automático.

Exibir badges `Core`, `Estático`, `Runtime` e `Buffer local`. Mappings dinâmicos não devem ser apresentados como permanentes sem esse contexto.

### 15.4 JetBrains

- Ler keymap selecionado e XMLs do usuário.
- Resolver herança sobre o catálogo base conhecido.
- Diferenciar default, override e atalho removido.
- Detectar variantes Toolbox, native e Flatpak sem varrer diretórios arbitrários.

### 15.5 Tier 1 após os três principais

| Programa                   | Base/default              | Personalização                                                 | Estratégia                                                           |
| -------------------------- | ------------------------- | -------------------------------------------------------------- | -------------------------------------------------------------------- |
| Zed                        | keymap Linux oficial      | `~/.config/zed/keymap.json`                                    | Resolver base keymap, contexto e bindings                            |
| Helix                      | tabelas oficiais por modo | `config.toml` quando aplicável                                 | Catálogo versionado + parser TOML                                    |
| kitty                      | defaults documentados     | `kitty.conf`, includes, `map`, `mouse_map`                     | Parser estático com includes limitados e detecção de clear           |
| WezTerm                    | defaults oficiais         | `wezterm show-keys`                                            | Execução somente por ação explícita; saída representa config efetiva |
| tmux                       | tabelas/defaults          | `list-keys -a -N` em servidor existente; `.tmux.conf` fallback | Nunca criar servidor apenas para scan                                |
| Firefox/Chromium/Brave/Zen | catálogo Linux            | shortcuts de extensões quando acessíveis                       | Base offline; customização best-effort claramente rotulada           |
| Obsidian                   | catálogo versionado       | `.obsidian/hotkeys.json`                                       | Seleção explícita de vault e merge com defaults                      |

### 15.6 Tier 2

Avaliar adapters/catálogos para Blender, Krita, GIMP, Inkscape, OBS Studio, Kdenlive, LibreOffice, Dolphin, KDE global shortcuts e GNOME custom shortcuts. A ordem deve considerar uso real pelos usuários do projeto, disponibilidade de fonte oficial e segurança da detecção.

Não prometer extração completa onde o aplicativo não expõe defaults/customizações de forma estável. Nesses casos, entregar catálogo versionado e importação manual confiável.

### 15.7 Atualizar fonte existente

- Comparar fingerprint/mtime antes de escanear novamente.
- Preview mostra `Adicionados`, `Alterados`, `Removidos`, `Conflitos`.
- Opções: mesclar, atualizar somente camada detectada, criar página separada.
- Alterações manuais, favoritos e notas são preservados.
- Fonte desaparecida fica `Indisponível`, sem apagar automaticamente a última cópia útil.

## 16. Estados vazios, loading, erro e casos extremos

Cada estado de página inteira usa `PagePlaceholder` grande ou componente equivalente: ícone válido, título específico, explicação curta e CTA de recuperação. Estados pequenos na rail podem ser inline.

### 16.1 Biblioteca e página

| Estado                          | Mensagem/ação esperada                                            |
| ------------------------------- | ----------------------------------------------------------------- |
| Store carregando                | Skeleton discreto ou progresso com label acessível                |
| Primeira execução sem páginas   | `Adicione um programa ou crie sua primeira página`                |
| Página pessoal vazia            | `Nenhum atalho nesta página` + `Adicionar atalho`                 |
| Busca sem resultado             | Mostrar query, limpar filtros e sugerir procurar em Tudo          |
| Página selecionada foi removida | Selecionar fallback e informar o ocorrido                         |
| Hyprland sem config/atalhos     | Explicar caminho/fonte e oferecer tentar novamente                |
| Biblioteca somente leitura      | Explicar causa e oferecer exportar/reparar permissões             |
| Conflito externo                | Comparar/recarregar/manter cópia, nunca sobrescrever              |
| Limite atingido                 | Explicar limite e oferecer dividir/exportar, sem falha silenciosa |

### 16.2 Descoberta e catálogo

| Estado                            | Mensagem/ação esperada                                              |
| --------------------------------- | ------------------------------------------------------------------- |
| Ainda não escaneado               | `Procurar programas suportados`                                     |
| Escaneando                        | Fonte atual, progresso indeterminado e Cancelar                     |
| Scan concluído sem fontes         | Diferenciar de “ainda não escaneado” e permitir página manual       |
| Scan falhou/timeout               | Causa, caminhos tentados de forma resumida e Tentar novamente       |
| Programa reconhecido sem catálogo | `Criar página para X` e registrar suporte futuro sem falsa promessa |
| Catálogo inválido/incompatível    | Não carregar parcialmente; informar versão e recuperação            |
| Ícone ausente                     | Fallback consistente, nunca texto do nome do símbolo                |

### 16.3 Importação

| Estado                      | Comportamento                                                     |
| --------------------------- | ----------------------------------------------------------------- |
| Arquivo vazio ou inválido   | Erro inline com formato esperado                                  |
| Schema mais novo            | Preservar arquivo e explicar incompatibilidade                    |
| Todos os itens duplicados   | Mostrar que nada será alterado e opções de merge                  |
| Parte inválida              | Preview separa itens; usuário decide corrigir ou importar válidos |
| Fonte mudou durante preview | Reanalisar antes de escrever                                      |
| Cancelado                   | Manter seleção/rascunho, nenhuma escrita parcial                  |
| Falha de escrita            | Reter preview e permitir tentar novamente/exportar                |
| Sucesso                     | Quantidades e CTA `Abrir página`                                  |

### 16.4 Rascunho

| Estado               | Comportamento                                      |
| -------------------- | -------------------------------------------------- |
| Rascunho recuperado  | Banner discreto + Descartar                        |
| Item original mudou  | Comparação e escolha explícita                     |
| Página alvo removida | Escolher nova página sem perder campos             |
| Rascunho expirado    | Oferecer recuperar ou descartar, conforme política |

### 16.5 Layout e dados extremos

Testar explicitamente:

- nomes, ações, categorias e chords muito longos;
- Unicode, RTL e traduções maiores;
- zero, 1, 49, 50, 500, 5.000 e 10.000 itens;
- centenas de páginas/apps;
- resoluções baixas e escalas de fonte 125–200%;
- tema claro, escuro, transparente e sharp mode;
- ícone de app ausente, arquivo removido e symlink quebrado;
- import com 100% de conflitos;
- múltiplas alternativas e chords de vários estágios.

## 17. Movimento e feedback

- Usar somente `Appearance.animation.*` e respeitar `animationMultiplier`/reduced motion.
- Entrada de rail/página: opacity + translate curta e interrompível.
- Saída deve ser um pouco mais rápida que entrada.
- Novo item: translate curto + opacity e highlight tonal one-shot; sem scale e sem pulse.
- Busca: animar somente delegates visíveis; sem cascade sobre centenas de itens.
- Categoria expandida: altura/opacity com duração do token e estado final determinístico.
- Importação: progresso, conclusão e erro com mudanças de estado claras, não looping decorativo.
- Reabertura não pode depender de `Behavior` em valor que já terminou; reset e início explícitos quando uma sequência for indispensável.

## 18. Acessibilidade e uso por teclado

- `Accessible.name`, `Accessible.role` e tooltip em todo icon-only button.
- Ordem de tab lógica do header ao conteúdo e à rail/edit sidebar.
- Foco visível com token tonal, sem border proibida.
- Ações disponíveis por hover também aparecem no foco e possuem menu/atalho.
- Mensagens de erro usam ícone + texto, nunca somente cor.
- Toasts importantes são anunciados por tecnologia assistiva.
- Chords têm nome falado completo; glyph sozinho nunca carrega a semântica.
- Drag-and-drop tem alternativa por teclado.
- Labels permanecem visíveis; placeholder não substitui label.
- O primeiro erro de validação recebe foco, com mensagem junto ao campo.
- Suportar reduced motion e fontes ampliadas sem cortar CTA ou conteúdo.

## 19. Desempenho

### 19.1 Renderização

- Trocar `Repeater` irrestrito por lista virtualizada em resultados e visão `Todos`.
- Manter overview em cards somente para um conjunto pequeno; categorias recolhidas não instanciam todos os filhos.
- Eliminar cálculo masonry O(n²) por delegate.
- Evitar `iconExists()` e parsing repetido dentro de cada row.
- Reutilizar delegates e limitar animações aos elementos visíveis.

### 19.2 Índice de busca

- Serviço mantém documento normalizado por item: tokens, chord canônico, aliases e score base.
- Reindexar incrementalmente somente página/camada alterada.
- Debounce de 60–100 ms para input de busca.
- Cache da forma normalizada; não aplicar `toLowerCase()` e concatenações grandes em cada binding/delegate.
- Resultados podem ser limitados inicialmente e carregados em lotes sem alterar ranking.

### 19.3 Scans

- Nenhum scan no boot.
- Checagem leve de caminhos/mtime ao abrir a área relevante, cacheada por sessão.
- Parsing pesado fora do thread visual.
- Timeout, cancelamento, limite de bytes e quantidade máxima por fonte.
- Feedback visual em menos de 100 ms após iniciar uma operação.

## 20. Segurança, privacidade e confiabilidade

- Importadores estáticos são somente leitura.
- Não seguir includes/symlinks fora de limites definidos sem consentimento.
- Não executar arquivos de configuração por padrão.
- Modos runtime/headless explicam exatamente o comando e o risco antes da primeira execução.
- Não enviar keybinds, caminhos ou nomes de apps para serviços externos.
- Sanitizar strings exibidas e exportadas; limitar tamanho por campo/arquivo.
- Escritas usam transação lógica, arquivo temporário e rename atômico.
- Backup/migração tem nome versionado e caminho informado ao usuário.
- Undo para exclusões guarda dados suficientes para restauração real.

## 21. Arquitetura de arquivos proposta

Os nomes finais podem mudar, mas as responsabilidades devem permanecer separadas:

```text
modules/ii/cheatsheet/
  CheatsheetKeybinds.qml                 # shell da feature e roteamento
  CheatsheetKeybindsLibrary.qml          # busca/exploração
  CheatsheetKeybindsRail.qml             # páginas e fontes
  CheatsheetKeybindEditorSidebar.qml     # criar/editar/sequence
  CheatsheetKeybindsPageForm.qml         # adicionar fonte/página
  CheatsheetKeybindBulkImport.qml        # preview e correção em lote
  KeybindShortcutSequence.qml            # renderização da cápsula
  KeybindEmptyState.qml                  # estados específicos, se PagePlaceholder não bastar

services/
  KeybindsService.qml                    # store e escrita única
  KeybindDrafts.qml                      # rascunho e rota persistidos
  KeybindSearchIndex.qml                 # índice/ranking, ou helper adequado
  KeybindCatalogService.qml              # packs, aliases, updates e overlays
  KeybindAppContext.qml                  # janela anterior e resolução de app

scripts/keybinds/
  import_keybinds.py                     # CLI/dispatcher
  adapters/                              # parsers somente leitura
  catalogs/                              # geração/normalização no desenvolvimento

defaults/keybinds/
  catalog.json                           # índice de packs
  vscode-linux.json
  neovim-core.json
  intellij-linux.json
```

Regras:

- QML visual não interpreta formatos de terceiros.
- Adapter não escreve biblioteca do usuário.
- Catálogo não contém estado pessoal.
- Search index não é a fonte de verdade.
- Draft store não duplica itens já salvos.
- Toda mudança estrutural relevante deve atualizar o `AGENTS.md` durante a implementação, não nesta fase de planejamento.

## 22. Fases de implementação

### Fase 0 — Guardrails e correções imediatas (P0)

Entregáveis:

- substituir símbolo inválido e adicionar fallback/teste de ícones;
- tornar criação de página rolável e CTA sticky/responsivo;
- parar de fechar import antes do resultado;
- consolidar Fechar/Cancelar/Delete;
- adicionar cobertura de alvo mínimo e labels acessíveis;
- fixtures/testes que reproduzem perda de rascunho e overflow.

Aceite:

- nenhuma ação fica abaixo da viewport em 1280×720;
- nenhuma string de símbolo inválido aparece na UI;
- erro de import mantém a tela e os dados;
- fechar/reabrir não perde o formulário, inicialmente por store mínimo se necessário.

### Fase 1 — Fundação de dados

Entregáveis:

- tokenizer/chord estruturado compartilhado;
- schema v2, migração v1 e base/overlay;
- draft store atômico;
- índice/ranking de busca;
- registro de ícones e aliases de app.

Aceite:

- migração é idempotente e preserva biblioteca byte-semanticamente;
- chord tem a mesma renderização/normalização em Hypr, páginas, editor e busca;
- rascunho sobrevive a close, troca de aba e reconstrução do Loader.

### Fase 2 — Biblioteca, busca e rail

Entregáveis:

- busca global com scopes e app anterior;
- rail reorganizada e sticky footer;
- `Essenciais`/`Todos`, categorias priorizadas e lista virtualizada;
- row limpa e glyphs de modificadores;
- matriz de empty/loading/error states.

Aceite:

- consulta global alcança todas as páginas;
- 5.000 itens mantêm metas de latência e scroll;
- todos os fluxos principais funcionam somente por teclado.

### Fase 3 — Criação rápida

Entregáveis:

- gravador de chord;
- editor simplificado;
- `Adicionar e próximo`, retenção inteligente e contador de sessão;
- bulk paste/import;
- conflito/duplicidade e undo.

Aceite:

- usuário cria 25 itens em sequência sem reabrir rail;
- conflito é detectado antes da escrita;
- fechar no meio restaura exatamente o próximo item incompleto.

### Fase 4 — Criação de fonte/página e sync

Entregáveis:

- fluxo source-first;
- seleção de app auto-preenchida;
- preview/diff/merge;
- atualização de uma fonte existente;
- estados de cancelamento, timeout e fonte removida.

Aceite:

- nenhum import fecha antes do sucesso;
- merge preserva notas, favoritos e overrides;
- scan pode ser cancelado sem escrita parcial.

### Fase 5 — Catálogos principais

Entregáveis:

- VS Code Linux ≥250;
- Neovim core ≥150;
- IntelliJ Linux/keymap ≥150;
- fontes, versões, categorias, prioridades e `Essenciais`;
- testes automáticos de quantidade e integridade.

Aceite:

- nenhum pack cai abaixo do mínimo definido;
- todos os IDs são estáveis/únicos;
- cada item possui categoria, prioridade, origem e chord válido ou raw justificado.

### Fase 6 — Importadores avançados

Entregáveis:

- VS Code perfis/extensões/precedência;
- Neovim parser estático ampliado;
- Neovim server runtime opt-in e headless avançado;
- JetBrains herança de keymap;
- diagnósticos estruturados.

Aceite:

- fixtures cobrem regras removidas, condicionais, buffer-local, arquivos malformados e timeout;
- nenhuma configuração é executada silenciosamente;
- preview identifica origem/confiança.

### Fase 7 — Ecossistema Tier 1 e Tier 2

Implementar por uso e confiabilidade: Zed, Helix, kitty, WezTerm, tmux, browsers, Obsidian; depois apps criativos/produtividade. Cada adapter exige fonte oficial, threat model, fixtures e critérios de atualização.

### Fase 8 — Polimento e rollout

- auditoria completa de acessibilidade;
- performance e memória;
- traduções e texto longo;
- motion/reduced motion;
- telemetria local opcional de métricas técnicas, sem conteúdo pessoal;
- documentação no `AGENTS.md`;
- migração gradual com feature flag e rollback.

## 23. Plano de testes

### 23.1 Unitários

- tokenizer: combinações, chords, alternativas, tecla `+`, `<leader>`, scan code, mouse, Unicode;
- normalização de modificadores e layouts;
- ranking e prioridade;
- detecção de conflito/duplicidade;
- merge base/overlay e tombstones;
- migração v1→v2;
- lifecycle do rascunho;
- registro/fallback de ícones.

### 23.2 Parsers

Fixtures por programa com:

- arquivos vazios, malformados e grandes;
- comentários/JSONC;
- includes e symlinks;
- caminhos Unicode;
- remoções/overrides;
- múltiplos perfis;
- mappings estáticos, runtime e buffer-local;
- timeout, cancelamento e output truncado;
- versão futura não reconhecida.

### 23.3 Contratos QML

- somente um renderer/tokenizer de chord;
- nenhuma cápsula por tecla;
- nenhum border;
- nenhuma duração/easing hardcoded nova;
- ícones pertencem ao registro ou têm fallback;
- alvos mínimos respeitados;
- footer da criação permanece visível;
- listas grandes são virtualizadas;
- botões icon-only têm nome acessível;
- draft store é acionado em close/troca de aba.

### 23.4 Integração

- criar, fechar overlay e retomar;
- editar item, fonte mudar externamente e resolver conflito;
- criar 25 itens em sequência;
- bulk import de 500 itens com inválidos e duplicados;
- atualizar catálogo preservando overlay;
- apagar/desfazer item e página;
- fonte desaparecer entre scan e import;
- cancelar scan/import;
- página alvo ser removida enquanto há rascunho;
- alternar repetidamente entre abas sem vazamento/perda.

### 23.5 QA visual e de teclado

Sem depender de IPC ou capturas do desktop durante esta etapa:

- revisar manualmente 1280×720, 1366×768, 1920×1080 e ultrawide;
- tema claro/escuro, transparência, sharp mode e fonte ampliada;
- fluxo completo mouse, somente teclado e leitor de tela quando disponível;
- long labels, traduções, chords longos, 0/10.000 itens;
- confirmar contraste, foco, rolagem, clipping e sticky footer.

## 24. Critérios de aceite finais

- [ ] Abrir o Cheatsheet sugere o app anterior sem substituir a escolha ativa indevidamente.
- [ ] Busca global encontra Hyprland, defaults, extensões, importados e itens pessoais.
- [ ] Busca por chord e por linguagem natural têm ranking previsível.
- [ ] VS Code e Neovim possuem mais de 100 itens cada, com `Essenciais` priorizados.
- [ ] Categoria importante aparece antes de categorias raras sem depender da ordem do arquivo.
- [ ] Criar vários atalhos não exige fechar/reabrir o editor.
- [ ] Fechar overlay, trocar aba e hot reload preservam rota e rascunho.
- [ ] O editor não duplica Fechar/Cancelar nem compete com Delete.
- [ ] CTA da página permanece visível em viewport baixa.
- [ ] Nenhum ícone inválido aparece como texto.
- [ ] Defaults, extensões e personalizações são visualmente distinguíveis.
- [ ] Atualizar catálogo preserva overrides, notas, favoritos e itens ocultos.
- [ ] Scans são opt-in/contextuais, canceláveis e não bloqueiam a UI.
- [ ] Neovim nunca executa config automaticamente.
- [ ] Import mostra preview/diff e não fecha antes do sucesso.
- [ ] Rows têm alvo mínimo, foco visível e nomes acessíveis.
- [ ] Listas grandes são virtualizadas e cumprem metas de latência.
- [ ] Todos os estados críticos possuem mensagem e recuperação.
- [ ] Migração v1→v2 é idempotente e reversível por backup/exportação.

## 25. Riscos e decisões que precisam ser validados durante a implementação

| Decisão                      | Risco                                     | Mitigação                                                            |
| ---------------------------- | ----------------------------------------- | -------------------------------------------------------------------- |
| Base pack + overlay          | Aumenta complexidade de resolução         | Resolver em service, testar merge e manter exportação materializada  |
| Busca global sempre indexada | Memória com 10.000+ itens                 | Índice compacto, incremental e virtualização                         |
| App anterior                 | Classes Wayland inconsistentes            | Aliases versionados, fallback pelo desktop entry e controle manual   |
| Neovim runtime               | Configuração dinâmica e risco de execução | Preferir server já aberto; headless somente opt-in com aviso/timeout |
| VS Code extensões            | Muitos manifests e regras condicionais    | Scan incremental/cache, mostrar `when` e procedência                 |
| Catálogos extensos           | Conteúdo desatualizado                    | Versionar fonte/data, CI e atualização por release                   |
| Autosave de draft            | Conflito com edição externa               | Guardar baseRevision/baseHash e comparar ao salvar                   |
| Undo destrutivo              | Dados grandes                             | Snapshot limitado e persistido por curto período                     |

## 26. Ordem recomendada de decisões

Antes de desenhar pixels finais, fechar estas decisões na ordem:

1. schema v2 e resolução base/overlay;
2. representação estruturada de chord;
3. lifecycle de rascunho/rota;
4. contrato de adapters e procedência;
5. ranking global e prioridade;
6. comportamento exato de `Adicionar e próximo`;
7. breakpoints e virtualização;
8. especificação visual/motion final.

Isso evita construir uma interface bonita sobre uma estrutura que ainda perde dados, mistura origens ou não escala.

## 27. Referências oficiais para implementação

- [VS Code — Keyboard Shortcuts](https://code.visualstudio.com/docs/configure/keybindings)
- [VS Code — `contributes.keybindings`](https://code.visualstudio.com/api/references/contribution-points#contributes.keybindings)
- [Neovim API — keymap global e buffer-local](https://neovim.io/doc/user/api/)
- [Zed — Key Bindings](https://zed.dev/docs/key-bindings)
- [Helix — Keymap](https://docs.helix-editor.com/keymap.html)
- [kitty — Configuração e shortcuts](https://sw.kovidgoyal.net/kitty/conf/)
- [WezTerm — `show-keys`](https://wezterm.org/cli/show-keys.html)
- [WezTerm — Default Key Assignments](https://wezterm.org/config/default-keys.html)
- [tmux — Getting Started / key tables](https://github.com/tmux/tmux/wiki/Getting-Started)
- [Firefox — Keyboard shortcuts](https://support.mozilla.org/en-US/kb/keyboard-shortcuts-perform-firefox-tasks-quickly)
- [Web Interface Guidelines](https://github.com/vercel-labs/web-interface-guidelines/blob/main/command.md)

## 28. Checklist mestre de entrega

### Fundamentos

- [ ] Schema v2 documentado e migrador testado.
- [ ] Base/overlay/procedência implementados.
- [ ] Tokenizer e glyph registry compartilhados.
- [ ] Draft store atômico e reidratação de rota.
- [ ] Search index incremental.

### Interface

- [ ] Busca global e app anterior.
- [ ] Rail reorganizada, contrastante e escalável.
- [ ] Row limpa com cápsula única e modifier glyphs.
- [ ] Editor simplificado sem ações duplicadas.
- [ ] Criação em sequência e bulk.
- [ ] Criação de página source-first, responsiva e com sticky CTA.
- [ ] Empty/loading/error states completos.
- [ ] Movimento tokenizado e reduced motion.

### Conteúdo e integrações

- [ ] VS Code ≥250 e import de perfis/extensões.
- [ ] Neovim ≥150, parser estático ampliado e runtime opt-in.
- [ ] IntelliJ ≥150 e herança de keymap.
- [ ] Tier 1 priorizado por uso/fonte oficial.
- [ ] Preview/diff/merge/refresh de fontes.
- [ ] CI valida packs, fontes, quantidade e IDs.

### Qualidade

- [ ] Acessibilidade e navegação completa por teclado.
- [ ] Performance com 10.000 itens.
- [ ] Testes unitários, parsers, contratos e integração.
- [ ] QA de layouts, temas, texto longo e casos extremos.
- [ ] Backup, rollback e conflitos externos.
- [ ] `AGENTS.md` atualizado ao implementar as novas decisões arquiteturais.
