# Comparação controlada com end-4 — rodada 1

| Família visual carregada | RSS MiB | PSS MiB | PSS com auxiliares MiB | VRAM MiB | CPU Quickshell % | CPU árvore % |
|---|---:|---:|---:|---:|---:|---:|
| Fork, configuração original | 1055,8 | 903,7 | 975,7 | 225,7 | 4,4 | 17,4 |
| end-4, configuração compartilhada | 442,7 | 316,0 | 320,1 | 84,5 | 0,6 | 0,6 |
| Diferença observada | +613,1 | +587,7 | +655,6 | +141,3 | +3,8 | +16,8 |

São as famílias `IllogicalImpulseFamily.qml` reais, carregadas na mesma versão de Quickshell/Qt, GPU NVIDIA, monitor 1920×1080 a 120 Hz e isolamento de rede/dados. O harness não executa o bloco de inicialização completo do `shell.qml` de nenhuma das versões. Os singletons acionados pelos painéis continuam usando suas implementações reais.

O núcleo antes de carregar a família já difere: cerca de 155 MiB de PSS no fork e 90 MiB no original. Ao carregar a família, a diferença incremental entre versões é aproximadamente 523 MiB. Isso não transforma 523 MiB em desperdício: o fork possui mais serviços, interfaces, código e conteúdo pré-carregado.

## Versões e integridade

- Fork: `842411d065ada2b95a714dbeacc1387ada258aac`.
- end-4: `97c5bc651f68092351b24aaa935af708b1e04514`.
- Submódulo `rounded-polygon-qmljs`: `e31ec4cb4ebf6a46b267f5c42eabf6874916fa16`, exatamente a revisão fixada pelo clone original.

O diretório do submódulo estava vazio no clone indicado. A primeira tentativa falhou ao carregar MaterialShape e foi descartada. A bancada recebeu um `git archive` da revisão exata, já disponível no repositório local do fork. Não houve modificação do clone end-4 original nem instalação de pacotes.

## Validade e diferenças funcionais

As superfícies Background, barra vertical, Dock e quatro cantos de tela do end-4 foram confirmadas no Hyprland. No fork, além da barra e Dock, existe a superfície separada de widgets do desktop; os painéis pré-carregados e serviços também são diferentes.

O original emitiu um aviso sobre `notifications.forceMonitor.enable`, ausente em seu próprio esquema Config, e três avisos de `AiChat.commandPrefix` referenciando root nulo, além de um binding loop de altura em FloatingActionButton. O fork emitiu um binding loop de sizing no Dock. Eles estão documentados como limites de compatibilidade; esta medição não certifica todas as funções do original nesta versão de Qt/Quickshell.

O mesmo JSON não oferece paridade funcional entre versões: propriedades exclusivas do fork não existem no original. Esta comparação mede o resultado das famílias reais com a configuração compartilhada, e não um teste de dois programas oferecendo rigorosamente as mesmas funções. Os 600 MB citados pelo usuário são uma referência externa; a bancada mediu 443 MiB de RSS no original, sob as condições acima.

## Limite após a rodada 2

Os 15 ensaios novos não incluíram uma execução do end-4. Os 779,1 MiB PSS do fork sem cache após a navegação/GC da rodada 2 pertencem a outro protocolo e snapshot: não formam um par equivalente com os 316,0 MiB acima. Comparar novamente boot integral e sequência comum, com funções/dados/reprodução controlados, antes de declarar a meta alcançada. Não somar reduções de módulos isolados para projetar o total do fork.
