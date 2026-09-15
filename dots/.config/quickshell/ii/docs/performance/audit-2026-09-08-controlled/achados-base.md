# Achados individuais validados

**Registro histórico da rodada 1.** A organização atual está em [PRIORIDADES.md](PRIORIDADES.md) e os testes novos em [testes-ab.md](testes-ab.md). Na rodada 2, a remoção do editor de Notas e da lateral/pickers do Calendário foi medida; a navegação curta mostrou vantagem residual de RAM, com limites. Barra e Dashboard produziram anomalias. Pendências citadas abaixo referem-se ao momento da primeira rodada.

## Calendário: maior aumento de RAM entre os painéis de uso eventual

Na repetição, o processo foi de **136,7 MiB PSS com controlador fechado para 472,9 MiB aberto**: aumento de **336,3 MiB**. Fechar levou a 409,8 MiB; destruir o controlador, a 408,6 MiB; coletar JavaScript explicitamente, a 393,9 MiB. O maior custo persistente não é a janela gráfica: sua VRAM caiu de 65,8 para 1,8 MiB ao fechar.

O mapeamento de memória aberto tinha aproximadamente 292 MiB em alocações anônimas nativas/outras e 63 MiB no heap JavaScript do QML. Após descarregar e coletar, ainda havia 224 e 51 MiB, respectivamente. Esses grupos são categorias de páginas residentes, não bytes de objetos vivos identificados por arquivo.

O calendário mensal instancia as células, os dados derivados de eventos/tarefas/aniversários, a barra de eventos e popups. O host já usa Loader para alternar mês/semana; carregar ambas as visualizações simultaneamente não é a explicação encontrada. A próxima investigação deve separar a barra de edição/pickers do grid e medir quais serviços/dados continuam referenciados após o último consumidor desaparecer.

## Pré-carregamento: o conteúdo escolhido altera muito o resultado

Com a aba Atalhos controlada desde o começo, habilitar seu cache levou o controlador fechado a 214,5 MiB, contra 137,6 MiB sem cache: aproximadamente 76,9 MiB antecipados antes da primeira abertura. Após a primeira abertura/fechamento, porém, a diferença foi apenas 2,4 MiB; depois de descarregar e coletar, 1,1 MiB.

O cenário anterior, que chegava a 397,2 MiB ainda fechado, tinha pré-carregado **Calendário** e depois navegado a **Atalhos**. Ele mede um histórico de navegação mais caro. Esse comportamento é relevante para o seu boot, porque a configuração original mantém a última aba do Cheatsheet carregada e a referência salva estava no calendário.

Logo, desligar a retenção pode economizar bastante **antes da primeira visita**, mas não garante que o processo devolverá a mesma quantidade de RAM depois de visitar os módulos.

## Barra: layout invisível ainda custa objetos e processos

`VerticalBarContent.qml` mantém duas árvores de layout: uma para Dynamic Island e outra para o modo normal. A propriedade `visible` seleciona o desenho, mas os dez Repeaters continuam criando componentes. A medição isolada registrou **dois `screensharestate.sh`** durante a abertura, mesmo com apenas um monitor.

Cada instância de `ScreenShareIndicator.qml` inicia seu próprio Process. O script consulta `pw-dump`, filtra JSON e dorme 1,5 s. No ensaio da barra, os dois auxiliares consumiram aproximadamente 6,8% de um núcleo juntos; o Privacy adicionou aproximadamente 3,7% nos seus contadores observados. Essas estimativas por nome são conservadoras para processos curtos; a CPU total da árvore foi medida separadamente.

O `privacy_probe.py` continuou existindo depois de fechar/descarregar a barra porque seu proprietário é o singleton Privacy. Isso é uma decisão de ciclo de vida distinta da duplicação do indicador: se a detecção deve permanecer global para proteger o usuário, o melhor ajuste é compartilhar um observador eficiente, preservando as funções de privacidade.

## Serviços sobrevivem às janelas

Após fechar Dashboard, Calendário, Overview ou Barra, alguns cenários continuaram com processos como `monitor.py`, o bridge de LocalSend e `localsend-cli`. A diferença entre PSS do Quickshell e PSS de sua árvore ficou próxima de 40 MiB no calendário/overview e de 53 MiB na barra da primeira rodada.

Não atribuímos automaticamente esses serviços como defeitos: LocalSend pode ter autostart configurado, e monitoramento de aplicativos pode precisar continuar. O problema arquitetural a revisar é uma visualização tocar um singleton com efeitos de inicialização e, assim, manter dependências globais mesmo depois que ela desaparece.

## GPU: ocupação e atividade são custos diferentes

Background + widgets usaram aproximadamente 145 MiB de VRAM, mas o Quickshell consumiu apenas 0,2% de um núcleo nessa fase. O modo de mídia elevou a VRAM total do processo a 231 MiB e a CPU a 25,5%; fechar o modo devolveu a VRAM para o patamar do Background.

A configuração testada tinha animação de fundo e visualizador de ondas ativados. `FloatingArtBackground.qml` anima dois eixos continuamente; sua imagem já é decodificada em resolução reduzida, portanto recomendar apenas diminuir `sourceSize` ignoraria uma otimização existente. O A/B que desligou animação e visualizador terminou com CPU maior e Cava persistente, sob interferência de reprodução externa. Ele não demonstrou economia; os resultados e a hipótese de demanda incorreta do singleton estão em [testes-ab.md](testes-ab.md).

Overview e Dock também exigem atenção à captura contínua de janelas: a configuração tinha `windowZoomLiveCapture=true`. A leitura posterior confirmou que o Dock, apesar de `ScreencopyView.live=true`, já torna `captureSource` nulo sem demanda e controla visibilidade, privacidade e escala; a janela de widgets do Background também já é desmapeada quando não é necessária. Não tratar esses mecanismos como ausentes. A parcela exclusiva de cada preview/superfície exige seu próprio A/B; ver [investigação de código](INVESTIGACAO-DE-CODIGO.md).

## O que os dados não demonstram

- Não demonstram que todo o saldo após fechar é um vazamento. Destruição de QML, coleta de JavaScript e devolução de páginas do alocador são etapas distintas.
- Não permitem somar o consumo de todos os módulos, porque os processos isolados repetem o núcleo e dependências comuns.
- Não tornam 600 MB versus 1 GB uma comparação equivalente por si só. O teste da família visual do end-4, com as mesmas bibliotecas e condições, está documentado separadamente.
- Não estabelecem estabilidade de várias horas: a primeira rodada observa 25 s após fechar, e as repetições acrescentam um segundo ciclo e/ou GC.

## Resultado adicional da rodada 1

O protótipo de barra com somente o layout ativo eliminou um monitor de compartilhamento e reduziu a CPU da árvore em 5,3 pontos percentuais de um núcleo. Economizou apenas 1,5 MiB de PSS, dentro da escala de variação observada.

A família sem pré-carregar sidebars/Cheatsheet ficou 237,4 MiB de PSS abaixo da referência, com a mesma VRAM. A reprodução externa e a janela de coleta não foram rigorosamente idênticas entre lotes. A redução é um sinal forte para revisar o pré-carregamento, mas seu tamanho exato e sua persistência após visitar os painéis ainda precisam de confirmação.
