# Ferramentas da auditoria

Leia [GUIA-DE-AUDITORIA.md](../GUIA-DE-AUDITORIA.md) antes de executar. O fluxo é:

1. `prepare.py --output <diretório novo e privado>` cria uma bancada sem interromper o shell.
2. Na bancada, `python3 run.py <id> [<id> ...]` executa somente cenários escolhidos e restaura produção ao sair normalmente ou por SIGINT/SIGTERM.
3. `python3 build_report.py` gera tabelas e dados em `report/`.
4. Validar abertura, fases, reprodução e restauração; escrever análise, propostas e pendências.

`cases.json` espelha o catálogo do supervisor. `runner_template.py` é instalado como `run.py`; não executá-lo nesta pasta do Git. `historical/` contém as versões efetivamente executadas nas rodadas registradas e não deve ser usado como ponto de entrada sem reconstruir sua bancada correspondente.

O coletor usa apenas a biblioteca padrão Python, `/proc` e NVML por ctypes. Quickshell e Bubblewrap são subprocessos externos já instalados. Não há instalação automática, IPC do Quickshell ou captura de tela. Há interrupção da sessão e acesso aos serviços locais; o isolamento não é uma máquina virtual completamente desconectada.

O pacote reutilizável não recebeu um novo ensaio completo após sua organização. Sintaxe, catálogo, hashes dos dados e geração de relatório são verificáveis sem iniciar Quickshell; teste piloto e tratamento adicional de falhas estão no [backlog](../PENDENCIAS.md).

## Runner posterior da rodada 2

Os 15 ensaios posteriores usaram uma versão derivada, preservada em [round2/historical/run.py](../round2/historical/run.py). Ela não substitui o pacote genérico: usa seleção de aba por índice e as fases finais são só de navegação. Consulte os [limites e dados](../round2/README.md) e a seção 10 do [guia](../GUIA-DE-AUDITORIA.md) antes de adaptar uma nova execução.

## Casos planejados e casos implementados

[PROXIMOS-TESTES.md](../PROXIMOS-TESTES.md) descreve o próximo trabalho. A0 é análise offline; T0 requer alterações de instrumentação; os demais IDs são perguntas/variantes a implementar. Eles **não foram adicionados a `cases.json` ou `runner_template.py`** nesta atualização. Leia os critérios do plano antes de adaptar a cópia privada; faça piloto antes de lotes de atribuição.
