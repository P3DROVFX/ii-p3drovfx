# Melhorias propostas após a reavaliação

As duas rodadas orientam esta ordem. Esta revisão documental não alterou o produto. As diferenças dos protótipos não são ganhos garantidos de patches funcionais; fonte e limitações em [PRIORIDADES.md](PRIORIDADES.md) e [testes-ab.md](testes-ab.md).

## 1. RAM: decompor Notas e Calendário

**Notas:** a remoção de `NotesDetail` reduziu o incremento aberto em 151,1 MiB, mas eliminou o editor inteiro e o par teve reprodução diferente. Preservar a seleção/edição atual e criar sob demanda ferramentas de IA, exportação e seletores ocultos, em mudanças separadas. O desenho já é carregado tarde. `selectedId` seleciona a primeira nota automaticamente; um Loader condicionado somente à seleção não adia a construção. Separar dados de índice/documento é uma segunda frente de escalabilidade, não a explicação comprovada dos MiB atuais.

**Calendário:** implementar lateral, fontes e seletores sob demanda, conservando rascunho, estado e API dos formulários. A remoção conjunta reduziu 52,6 MiB do incremento no processo e 94,6 MiB absolutos da árvore. Ainda sobra grande custo na grade/dependências. Perfilar esse restante antes de reescrever as células. Limitar janela de eventos e detalhes por consumidores/uso recente em uma intervenção separada; alarmes e sincronização não podem perder dados necessários.

**Aceitação:** mesmos dados/reprodução, abertura e uso real das ferramentas, fechamento, reabertura e ciclos repetidos. Medir primeira visita e retorno ao idle, além de latência. Não aceitar uma implementação por reproduzir somente a RAM de uma variante sem editor.

## 2. RAM da família: política explícita de retenção

Separar pré-carregar, manter temporariamente e conservar estado leve. Usar as preferências existentes e limitar abas visitadas residentes; preservar rascunhos, seleção, geração de IA e operações do telefone fora da árvore visual quando apropriado.

Há 131,8 MiB a menos no idle final da navegação curta sem cache. Antes de tornar a política padrão, corrigir a seleção/validação da aba Phone e repetir a sequência com reprodução estável, duração maior e tempo de abertura medido. Dashboard precisa de tratamento próprio: sem cache ficou 48,7 MiB acima do cache ligado após GC. Não somar custos isolados de pré-carregamento para explicar a família.

## 3. CPU: Media Mode e demanda de Cava

Registrar consumidores reais de visualização, incluindo todos os widgets e modos de mídia. Ativar Cava apenas com reprodução e demanda; interromper processamento de pontos nas interfaces inativas/desabilitadas e liberar cada solicitação no descarte. Um guard só de `visualizerMode > 0` pode ser insuficiente se a UI estiver oculta: incluir sua demanda efetiva.

O código mostra trabalho dispensável, mas não atribui os 57,5% de CPU ao listener. Medir separadamente serviço, listener, animação de fundo e modos de visualização; obter perfil QML/nativo para a parcela restante. Verificar um único processo para múltiplos consumidores e ausência de trabalho sem consumidor. A GPU caiu no protótipo estático, mas sua RAM subiu.

## 4. Barra e observação de privacidade

Criar somente o layout ativo, compartilhar um monitor de screen share e evitar instanciar widgets explicitamente desabilitados. Distinguir preferência desligada de indicador temporariamente vazio, que precisa continuar observando para reaparecer.

O ganho de CPU do layout único não se repetiu; investigar antes de adotar o protótipo. Privacy off mostrou redução de CPU/helper, porém aumentou RAM total. Usar eventos onde cubram os sinais atuais e manter fallback de detecção/recuperação necessário. Desligar Privacy não é uma solução funcional. Validar câmera, microfone, compartilhamento, alternância de layout e múltiplos monitores, com CPU/RAM medidas em pares.

## 5. Trabalho residual, captura e auxiliares

A família sem cache permaneceu em 33,0% de um núcleo no idle com reprodução. Decompor widgets de mídia, barra e serviços; preservar LocalSend em autostart, notificações/KDE Connect e operações ativas. Para VPN/email, medir status relevante, limites de concorrência, deadline e cancelamento. O inventário estático não quantifica o ganho de cada mudança.

Overview/Dock precisam de A/B de captura versus mídia/bindings. O Dock já suspende a fonte sem demanda e Background já evita superfície vazia desnecessária. Mapear texturas/buffers antes de atribuir a VRAM toda a desperdício; separar otimização de bytes de redução de atividade gráfica.

## Critérios comuns

Registrar baseline e revisão exatos, mesmas funções e dados, repetições alternadas e métricas por fase. Melhorar RAM sem deslocar o custo para auxiliares fora da soma ou aumentar CPU/latência sem decisão explícita. Para distinguir vazamento de retenção, medir crescimento por ciclo e estabilização prolongada; GC periódico, restart e limpeza indiscriminada de cache não substituem identificar alocações e consumidores.

O [backlog](PENDENCIAS.md) separa o que foi medido, o que é hipótese e como encerrar cada investigação. Nenhum benchmark novo foi iniciado nesta reorganização.
