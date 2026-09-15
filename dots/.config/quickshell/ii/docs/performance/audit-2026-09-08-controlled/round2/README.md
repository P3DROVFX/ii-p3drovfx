# Evidências da rodada 2 — 8 de setembro de 2026

**15 cenários concluídos, 2.477 amostras, 128 linhas de resumo.** Esta pasta foi organizada posteriormente, por leitura dos resultados existentes em `/home/pedro/.local/state/ii-controlled-audit-round2/results`. Nenhum caso foi reexecutado durante a reconciliação. A rodada 1 continua nos arquivos do diretório pai: somadas, são 46 entradas e 6.034 amostras, com validade diferente por caso.

| Arquivo | Conteúdo |
|---|---|
| [manifest.json](manifest.json) | Hash SHA-256, início, quantidade de amostras e fases por caso; revisão registrada na preparação. |
| [summary.json](summary.json) | Resumos originais dos 15 casos, com ID de origem; RAM/CPU recalculadas e conferidas. |
| [validacao.json](validacao.json) | Marcador de término, reprodução por fase e contagem de padrões selecionados nos logs; não é certificado de causalidade. |
| `data/<case>/measurements.json` | Cópia exata das amostras e metadados já sanitizados pelo coletor: métricas de processo/GPU, marcadores e geometria de superfícies. |
| [navigation-identity.json](navigation-identity.json) | Subconjunto sem segredos da configuração de Policies e hash do modelo que explicam o índice incorreto. |
| [variants.json](variants.json) / `variants/` | Hashes dos componentes originais/variantes preservados e oito diffs encontrados no snapshot. |
| [historical/run.py](historical/run.py) | Estado final do runner derivado; preservado para inspeção, não como comando recomendado. |
| [historical/stages-final.json](historical/stages-final.json) | Fases da navegação final. Para cada ensaio, a autoridade é `measurements.json.stages`. |
| [verify.py](verify.py) | Verificação offline de hashes, amostras, resumos e métricas; não executa Quickshell. |

A preparação registra fork `21ecdff37b8d7e48e0a359a5c12bf24ab217e949`, end-4 `97c5bc651f68092351b24aaa935af708b1e04514` e shapes `e31ec4cb4ebf6a46b267f5c42eabf6874916fa16`. **Nenhum dos 15 casos executou o end-4.** SHA não identifica mudanças não commitadas; os diffs/hashes de variantes representam o estado final encontrado, não provam qual versão do runner existia em cada lote anterior. A bancada privada continua necessária para reconstrução integral e não foi publicada.

Os pares de Calendário/Notas removem funcionalidade com stubs. Navegação tem erro de identidade da fase Phone; MPRIS diverge em Notas e numa fase da família. Barra/Dashboard têm resultados contraditórios. O texto de [testes-ab.md](../testes-ab.md) e a tabela de [prioridades](../PRIORIDADES.md) qualificam esses dados; não inferir causalidade de `doneMarker` ou Loader pronto.

A busca em logs contabilizou somente padrões registrados em `validacao.json`; ausência desses padrões não certifica ausência de todo erro. Os três logs de barra não continham os padrões buscados. Cada navegação registrou um `Binding loop` em `Dock.qml` e um `Unable to assign` em `AndroidNetworkToggle.qml`; Dashboard teve um/dois avisos de atribuição. Não foi publicada mensagem privada completa nem medida a contribuição desses avisos ao consumo.

Não foram copiados config, estados de notas/conversas, credenciais, logs privados ou títulos de janelas. Não publicar a pasta privada inteira. O wrapper genérico do [guia](../GUIA-DE-AUDITORIA.md) e este runner histórico têm versões distintas; um não valida automaticamente o outro.
