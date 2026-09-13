# Referência histórica: cache da cheatsheet, 07/09/2026

Resumo dos dados lidos no início desta auditoria em `docs/performance/cheatsheet-cache.md` e `cheatsheet-cache-2026-09-07.json`. Esses arquivos estavam sem commit e ficaram ausentes durante alterações concorrentes no workspace. Este arquivo preserva somente os números usados como referência; não restaura arquivos removidos e não representa nova medição.

Configuração medida naquela investigação: Corne v4, 46 teclas, seis layers, aba Keybinds, PID 286514, Qt 6.11.1.

| Métrica do processo inteiro | Antes de construir o cache | Depois | Diferença |
|---|---:|---:|---:|
| RSS | 992,582 MiB | 1.019,504 MiB | +26,922 MiB |
| PSS | 774,259 MiB | 791,905 MiB | +17,646 MiB |
| Privada | 729,191 MiB | 746,527 MiB | +17,336 MiB |
| Swap | 0 MiB | 0 MiB | 0 MiB |

Construção inicial: 158 ms. Reconstruções com engine aquecida: 73, 61 e 67 ms. São tempos até o Loader de conteúdo pronto, não latência até o primeiro frame na tela.

O custo é incremental observado no processo compartilhado. Não é heap exclusivo, não se soma ao PSS da sessão atual e não se aplica automaticamente a outras abas, layouts ou conteúdo. O cache atual conserva somente a última aba selecionada; trocar de aba substitui a anterior.
