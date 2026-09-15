# Auditoria consolidada do ii — CPU, RAM e GPU

**Revisão de 8 de setembro de 2026.** Reúne a sessão real, 31 cenários da rodada 1 e 15 da rodada 2: **6.034 amostras preservadas**. Os novos resumos de RAM e CPU foram recalculados a partir das amostras. Esta revisão reorganizou documentação e evidências, sem executar novos benchmarks nem alterar o código do produto.

**Prioridades atuais:** o editor de Notas apresentou a maior diferença ao remover uma subárvore (151,1 MiB a menos no incremento aberto); Calendário continua o painel ocasional de maior RAM (+328,4 MiB na rodada 2), com grande parcela restante mesmo sem lateral/pickers. Na CPU, Media Mode chega a 67,8% de um núcleo no processo e ainda 57,5% com visualizador/animação desligados. A família sem cache permanece em 33,0% na árvore durante o idle final com reprodução.

A navegação curta sem cache terminou com **131,8 MiB PSS a menos no idle / 135,3 MiB após GC**, mas não prova economia permanente. O driver seleciona o índice do Tradutor na fase chamada Phone e MPRIS divergiu em uma fase. Dashboard sem cache terminou **48,7 MiB maior após GC**; o layout único da barra teve **11,8 pontos a mais de CPU** nesta rodada, invertendo o resultado anterior. Esses são alvos de investigação, não ganhos funcionais concluídos.

O [ranking atualizado](PRIORIDADES.md) separa RAM, CPU, GPU e anomalias; os [A/B revisados](testes-ab.md) distinguem diferenças observadas, remoções de funcionalidade e hipóteses. A comparação existente com end-4 é da rodada 1: diferença de **587,7 MiB PSS entre famílias**. A rodada 2 não repetiu o original sob a mesma navegação.

## Leitura e evidências

- [Prioridades atuais para aproximar o consumo do end-4](PRIORIDADES.md) e [investigação de código dos maiores consumidores](INVESTIGACAO-DE-CODIGO.md).
- [Medições completas por módulo e fase](medicoes.md), incluindo RSS, PSS, CPU, VRAM e atividade gráfica por PID.
- [Achados de memória, cache e serviços](achados-base.md) e [últimos testes A/B](testes-ab.md).
- [Comparação com o end-4](comparacao-end4.md) e [metodologia e limites](metodologia.md).
- [Propostas de melhorias, escritas após a análise](melhorias.md).
- [Próximos testes por hipótese, variante e critério de decisão](PROXIMOS-TESTES.md).
- [Guia detalhado de execução e elaboração do relatório](GUIA-DE-AUDITORIA.md), [pendências](PENDENCIAS.md) e [scripts](tools/README.md).
- Rodada 1: [resumo JSON](summary.json), [manifesto com hashes](manifest.json), [validação de abertura](validacao.json), [ambiente](environment.json) e `data/<id>/measurements.json`.
- Rodada 2: [guia das evidências](round2/README.md), [resumo](round2/summary.json), [manifesto](round2/manifest.json), [validação](round2/validacao.json) e `round2/data/<id>/measurements.json`.

**As seções 1–6 abaixo preservam o relatório histórico da sessão inicial e da rodada 1.** Seus números, conclusões temporais e PID final não descrevem uma medição atual. Resultados posteriores estão na abertura deste documento e na seção de rodada 2 de `testes-ab.md`.

## 1. O que a auditoria anterior mediu

A [investigação inicial](../audit-2026-09-08/auditoria.md) observou a sessão real, com histórico de desenvolvimento e recarregamentos. Ela mediu processos e regiões de memória; não isolou os painéis. A confirmação de 60 segundos encontrou:

| Medida anterior | Resultado |
|---|---:|
| Quickshell RSS | 1.050,953 MiB |
| Quickshell PSS | 854,041 MiB |
| Memória privada | 823,285 MiB |
| PSS conjunta da árvore | 1.036,573 MiB |
| CPU própria do Quickshell | 4,117% de um núcleo |
| Dois monitores de compartilhamento, com seus subprocessos | 9,500% de um núcleo |
| Monitor Privacy, com seus subprocessos | 9,083% de um núcleo |

As duas rotinas de compartilhamento e Privacy somaram **18,583% de um núcleo** naquela confirmação. São custos observados dos auxiliares; não representam uma economia integral já demonstrada por uma implementação alternativa.

A classificação de páginas encontrou aproximadamente **596,5 MiB anônimos nativos/outros**, **86,0 MiB de heap JavaScript QML**, **110,5 MiB de bibliotecas** e **14,8 MiB de fontes**. Ela não identifica objetos vivos por arquivo. Mostra, porém, que o tamanho das fontes no disco não explica sozinho a diferença de centenas de megabytes.

Também apareceram consultas transitórias do ProtonVPN de até **103 MiB PSS**, quatro auxiliares de email somando cerca de **49,4 MiB PSS** durante a confirmação, e outros serviços persistentes. Logs órfãos ocupavam **156,3 MiB de tmpfs**; arquivos de crash em disco ocupavam cerca de **1,6 GiB**. Esses valores não são o heap do Quickshell e não devem ser somados como se fossem a RAM de um painel.

O inventário estático contava 2.163 QML no fork e 586 no original; isso indica crescimento de escopo, não consumo proporcional. A versão inicial foi registrada em `698c4ffaaa6f75d8bf1a5b8758456f8179cebf55`, com alterações locais. O snapshot controlado posterior é `842411d065ada2b95a714dbeacc1387ada258aac`; portanto, a comparação entre rodadas não é um A/B de uma única alteração de código.

## 2. O que foi testado individualmente

Foram preservados **31 cenários concluídos**. Um foi excluído da atribuição por abrir a aba errada; os outros 30 abrangem 16 módulos/páginas principais, repetições, variantes e famílias visuais. Isso não equivale a medir cada widget ou arquivo QML do projeto separadamente.

Cada cenário iniciou um processo novo em uma cópia privada, com GPU e Wayland reais. O fluxo mediu núcleo, controlador fechado, módulo aberto, fechado e controlador destruído. Algumas repetições acrescentaram segunda abertura e coleta explícita de JavaScript. Rede externa ficou isolada; serviços locais, incluindo MPRIS, permaneceram disponíveis.

Na tabela abaixo, RAM é **PSS absoluto do processo isolado**, em MiB. “Antes” já inclui pré-carregamento quando habilitado. A diferença aberto − antes mede o incremento dessa transição, não o heap exclusivo do módulo. CPU 100% significa um núcleo lógico; a máquina possui 16. Não somar linhas.

| Módulo/cenário representativo | Antes | Aberto | Fechado | Descarregado | CPU aberto % | VRAM aberta MiB |
|---|---:|---:|---:|---:|---:|---:|
| Calendário, repetição sem cache | 136,7 | 472,9 | 409,8 | 408,6 | 0,3 | 65,8 |
| Barra vertical, referência A/B | 153,6 | 454,4 | 410,0 | 406,5 | 16,3 | 44,9 |
| Mídia, referência A/B; antes inclui Background | 312,0 | 429,4 | 401,8 | 312,1 | 25,9 | 231,3 |
| Notas | 141,2 | 347,5 | 332,1 | 332,1 | 0,2 | 33,1 |
| Sidebar IA sem cache | 153,5 | 336,5 | 319,5 | 309,0 | 0,5 | 33,4 |
| Overview | 140,9 | 316,6 | 310,5 | 310,5 | 18,4 | 81,7 |
| Phone, aba validada | 149,4 | 313,2 | 307,2 | 304,1 | 0,2 | 30,6 |
| Background + widgets | 156,7 | 302,7 | 234,8 | 234,8 | 0,2 | 145,1 |
| Dashboard sem cache | 150,8 | 294,2 | 268,3 | 261,1 | 8,6 | 43,7 |
| Comandos | 137,5 | 267,2 | 244,8 | 244,8 | 1,2 | 51,8 |
| Atalhos, repetição sem cache | 137,6 | 265,0 | 256,1 | 251,5 | 0,1 | 61,8 |
| Uso de aplicativos | 134,9 | 249,3 | 223,9 | 214,6 | 1,8 | 52,6 |
| Settings — Cores | 155,1 | 248,6 | 241,6 | 241,7 | 6,0 | 57,6 |
| Dock | 156,2 | 245,4 | 241,7 | 232,4 | 14,7 | 18,2 |
| Settings — Barra | 155,7 | 234,5 | 230,3 | 207,2 | 6,0 | 54,8 |
| Seletor de wallpapers | 137,9 | 226,7 | 212,2 | 212,2 | 0,6 | 47,6 |

Para Phone e Atalhos com dois ciclos, “descarregado” ocorre depois da segunda abertura/fechamento. A tabela completa inclui a fase intermediária. Background e Dock são instanciados na fase aberta e destruídos na fechada; não possuem a mesma semântica de controlador de um popup. No modo de mídia, fechar mantém Background. Settings já descarrega seu host e limpa caches específicos após cinco segundos.

## 3. O que permanece depois de fechar

O Calendário caiu de 472,9 para 409,8 MiB ao fechar. Destruir o controlador deixou 408,6 MiB; `gc()` reduziu para 393,9 MiB. A VRAM, entretanto, caiu de 65,8 para 1,8 MiB ao fechar. A retenção principal observada é de RAM, e não de uma janela gráfica ainda aberta.

Notas, IA e Phone também deixaram grande saldo no processo. Esse saldo pode incluir singletons ainda referenciados, componentes compilados, imagens, arenas do alocador e objetos coletáveis. O ensaio não separou todos esses mecanismos. **Não foi demonstrado vazamento de crescimento ilimitado.**

O cache de Atalhos antecipou cerca de **76,9 MiB** antes da primeira abertura, mas a diferença entre cache ligado/desligado após fechar foi **2,4 MiB**; depois de descarregar e coletar, **1,1 MiB**. Logo, destruir a interface não implica devolver imediatamente ao sistema toda a memória alocada na primeira visita.

Alguns módulos ativaram auxiliares persistentes. Calendário e Overview tiveram cerca de 40 MiB adicionais na árvore; a barra, cerca de 53–54 MiB. Isso merece revisão de ciclo de vida, respeitando serviços configurados para continuar globalmente, como LocalSend e privacidade.

## 4. GPU e CPU dos módulos

Background manteve aproximadamente **145 MiB de VRAM** com apenas **0,2% de um núcleo**. Mídia chegou a **231 MiB de VRAM** e cerca de **26% de um núcleo**. Ocupação gráfica e trabalho contínuo são problemas diferentes.

Overview apresentou aproximadamente **9,9% de atividade SM por PID**, com pico amostrado de 39%; Dock, média aproximada de 5,6%, pico de 35%. São amostras NVML, com limitações de granularidade descritas na metodologia, e não a utilização global da GPU. Atribuir esse trabalho especificamente às capturas ao vivo ainda exige um A/B.

O último teste de mídia estática da rodada 1 ficou pior: 56,1% de CPU própria e 68,2% na árvore. Cava apareceu e continuou após fechar/descarregar. O estado MPRIS externo não ficou fixo durante a rodada; não há base para afirmar que desligar animações causa a piora. Há evidência suficiente para investigar o Cava ativado por reprodução sem depender de um visualizador visível.

## 5. Fork, original e pré-carregamento

| Família visual | RSS MiB | PSS MiB | PSS da árvore MiB | VRAM MiB |
|---|---:|---:|---:|---:|
| Fork, preferências originais | 1.055,8 | 903,7 | 975,7 | 225,7 |
| Fork, pré-carregamento dos três painéis desligado | 799,3 | 666,3 | 736,5 | 225,7 |
| end-4 | 442,7 | 316,0 | 320,1 | 84,5 |

A diferença observada do fork para o end-4 foi **587,7 MiB de PSS**. Parte do custo do fork já existe antes da família: núcleo de aproximadamente 155 MiB contra 90 MiB. As famílias têm funções, serviços e pré-carregamentos diferentes; o harness não executou o boot completo de nenhum `shell.qml`. Há avisos de compatibilidade no original. Os 600 MB citados pelo usuário não foram reproduzidos literalmente nessa bancada.

Desativar `keepLeftSidebarLoaded`, `keepRightSidebarLoaded` e `cheatsheet.keepLastTabLoaded` foi a variante de maior redução de RAM observada: **−256,5 MiB RSS / −237,4 MiB PSS**, aproximadamente 26,3% do PSS da família original. A reprodução externa mudou entre execuções, e não houve teste de visitar todos os painéis depois. A evidência sustenta priorizar a política de pré-carregamento; não permite prometer essa economia exata em toda sessão.

## 6. Validade e encerramento

- `policies_phone` inicial não validou Phone e ativou IA: preservado para rastreabilidade, excluído da atribuição. `phone_only` confirmou `policyIcon=smartphone`.
- `cheatsheet_keybinds_keep` inicial pré-carregou Calendário antes de Atalhos: rotulado como navegação mista. As repetições validaram a mesma aba nos dois lados do teste.
- Falhas de calibração de Hyprland, configuração KDE somente leitura e submódulo ausente no end-4 não entraram como benchmarks bem-sucedidos.
- Os logs dos lotes registraram restauração e config original inalterado. Na consolidação, havia uma única instância normal do shell, numa sessão posterior à coleta. Nenhum teste adicional foi iniciado.
- Os scripts históricos executados foram preservados. O empacotamento reutilizável recebeu verificação estática, sem uma nova rodada de consumo; seu primeiro uso deve ser um piloto.

A [verificação final dos artefatos](verificacao.json) conferiu os hashes e resumos dos 31 cenários, totalizando 3.557 amostras, a sintaxe dos dez arquivos Python, a correspondência do catálogo e dos scripts históricos, e a regeneração das tabelas. A consulta final encontrou somente o shell normal, PID 2434, iniciado às 10:24:04. Os quatro logs de lote registraram `originalConfigUnchanged: true`. O código live pode ter avançado depois do snapshot; reproduzir os resultados exige a revisão e os dados registrados, não presumir que o checkout atual seja idêntico.

As medições identificam prioridades concretas, mas a atribuição por objeto/alocação, a estabilidade em horas e a economia após navegação completa continuam [explicitamente pendentes](PENDENCIAS.md).
