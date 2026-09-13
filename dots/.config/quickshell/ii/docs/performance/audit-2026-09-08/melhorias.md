# Melhorias propostas após a auditoria

Estas propostas se baseiam na [análise e medições](auditoria.md). **Nenhuma foi aplicada ao funcionamento do shell.** A ordem separa economia demonstrável nos auxiliares de hipóteses que ainda exigem perfil de alocações.

## 1. Prioridade imediata: eliminar descoberta duplicada de mídia/privacidade

**Evidência:** dois `screensharestate.sh` gastaram 9,500% de um núcleo, e `privacy_probe.py` com seus filhos gastou 9,083%, na confirmação.

**Mudança:** tirar o `Process` do `ScreenShareIndicator` e tornar o widget consumidor de um serviço compartilhado. Usar uma conexão de monitoramento de eventos do PipeWire para as informações compartilhadas de microfone/câmera/tela; manter uma detecção complementar de acesso direto a `/dev/video*` com intervalo adaptativo. Não confundir “widget invisível” com “não precisa detectar atividade”: a detecção é o que permite que ele apareça.

**Ganho a verificar:** a cópia redundante sozinha representa aproximadamente 4,6–4,9% de um núcleo nas janelas medidas. A solução consolidada pode atacar o restante do polling, mas ainda terá custo próprio. Não é uma promessa de recuperar os 18,583% inteiros, nem de economizar centenas de MB.

**Aceite:** somente um produtor por sessão, inclusive com várias instâncias da barra; sem processos por widget; atualizações corretas de início/fim de compartilhamento, hotplug de câmera e reconexão do PipeWire; nenhum uso simultâneo do mesmo arquivo temporário por produtores diferentes; repetir CPU por 60 s com e sem captura ativa.

## 2. Prioridade de RAM: tornar o cache das sidebars limitado e previsível

**Evidência:** ambos os `keep*SidebarLoaded` estão ativos. A esquerda acumula as abas visitadas; a configuração atual habilita AI, Translator e Phone.

**Mudança:** preservar controladores, rascunhos e estado de navegação, mas limitar a UI aquecida à última aba ou a um pequeno conjunto com expiração. Para a direita, separar header/controles baratos das listas pesadas e definir expiração do conteúdo pesado após fechar. Preservar o opt-in de cache e o comportamento solicitado pelo usuário; não desligar preferências silenciosamente.

**Ganho:** não quantificado. É uma das primeiras experiências de RAM a executar, porque o mecanismo de retenção foi identificado e o teste muda poucas variáveis. Não assumir que descarregar o Loader devolverá imediatamente todo o RSS.

**Aceite:** A/B de início limpo, abertura/fechamento e visita de cada aba; estado/rastreamento de tarefas e rascunhos preservados; medir construção e latência além da RAM, para não trocar uma economia pequena por travamentos perceptíveis.

## 3. Reduzir picos de VPN e residência de requisições de email

**VPN:** `VpnService` varre os provedores instalados a cada 10 s, inclusive com backend NetworkManager. Um `protonvpn` apareceu com 102,983 MiB de PSS. Separar descoberta ocasional de provedores da consulta de estado; consultar o selecionado/ativo, usando eventos do NetworkManager sempre que possível. Manter descoberta dos outros provedores ao abrir a seleção ou pedir refresh explícito.

**Email:** quatro helpers somaram aproximadamente 49,387 MiB de PSS e permaneceram presentes durante a confirmação inteira. Adicionar timeouts de rede e prazo global do job aos scripts que usam `urlopen` sem timeout, cancelamento efetivo, deduplicação por conta e concorrência limitada. Compartilhar token/dados quando fizer sentido; uma bridge permanente só compensa se o perfil provar que evita custo maior do que sua própria residência.

**Ganho:** reduzir picos e impedir residência sem limite durante falhas de rede; os 103 MiB de VPN não são economia permanente. Os 49 MiB de email são custo observado de jobs, não prova de vazamento.

**Aceite:** confirmar status correto de cada backend, comportamento offline, timeout previsível, reexecução sem fila crescente e término de todos os filhos ao cancelar.

## 4. Investigar os aproximadamente 596 MiB de alocações nativas

Esse bloco é o maior alvo de RAM, mas ainda está sem atribuição causal. Otimizá-lo exige evidência adicional.

1. Em uma sessão controlada da única instância, iniciar QML profiler e um perfil nativo desde o nascimento do processo; não injetar heaptrack no shell em uso como primeiro recurso.
2. Medir separadamente compilação de componentes, criação de QObjects, pixmaps, heap JavaScript e estado do jemalloc (`allocated`, `active`, `resident`, `retained`). Espaço virtual retido não equivale a RAM física.
3. Comparar início limpo com uma sequência fixa de 10–20 ciclos de abertura/fechamento. Verificar se a curva estabiliza e quais objetos/referências sobrevivem.
4. Só depois testar ajustes de decay/background purge do jemalloc, se houver grande diferença entre bytes vivos e residentes. Comparar CPU e latência para não obter RAM menor às custas de mais trabalho constante.

Não adicionar `gc()` em timer, `malloc_trim()` periódico ou um profiler permanente. Não prometer que forçar GC libera QObjects/strings/buffers de todos os subsistemas. A Qt tem mecanismos distintos de alocação e GC: [referência](https://doc.qt.io/qt-6/qtqml-javascript-memory.html).

## 5. Adiar a compilação das integrações e UIs pesadas

**Evidência:** 47 declarações PanelLoader contra 20 no original, 168 singletons declarados em services contra 45 e muito mais fonte QML. A família escolhida ainda usa muitos componentes inline. O fork já corrigiu esse problema no nível das famílias externas ao carregar por URL.

**Mudança:** estender o padrão de URL aos conteúdos pesados opcionais, mantendo controladores leves com atalhos e sinais necessários. Separar o serviço que precisa executar no boot da UI que só será usada depois. Auditar dependências indiretas: importar um tipo, compilar seu componente e instanciar seu singleton são etapas diferentes.

**Ganho:** reduzir trabalho de startup/reload e evitar parte dos componentes/caches nunca utilizados; valor em MiB ainda não medido. Não remover inicialização de notificadores, backups e outros serviços que precisam funcionar sem abrir o Settings.

**Aceite:** registrar quais arquivos são compilados e quais objetos são criados antes/depois; conferir primeira abertura e operação por atalho de todos os módulos afetados.

## 6. Aparar caches específicos, mantendo as otimizações existentes

| Alvo | Proposta | Limite da evidência |
|---|---|---|
| AI | Manter a sessão persistida completa, mas permitir janela visual/dados quentes menor e limite por bytes, além do teto de 1.000 mensagens. Carregar histórico anterior sob demanda. | Não foi medido excesso de mensagens na sessão atual. |
| AppStats | Introduzir descarte **só do cache em RAM**, preservando o dia atual e o período visível; limitar dias em memória. Não usar `clearHistory()` para liberar RAM: ele apaga dados persistidos. | Disco tinha apenas 2,773 MiB; prioridade secundária até medir representação JS. |
| Wallpaper Browser | Limitar páginas/respostas e suas imagens; descartar referências de páginas antigas e cancelar solicitações que perderam consumidor. | Aba desabilitada no estado observado; não explica por si só o consumo atual. |
| Cava | Adotar registro de consumidores visíveis; executar somente com reprodução ativa e ao menos um visualizador solicitante. | Não apareceu nas janelas longas; economia depende de uso. |
| Imagens de background | Avaliar resolução decodificada adequada ao monitor com margem real para parallax/zoom; reduzir resolução de fontes usadas só para blur. | O JPEG atual representa cerca de 19 MiB por buffer RGBA nativo; não somar automaticamente textura, RAM e VRAM. |
| Settings | Preservar unload após 5 s e as liberações de SearchRegistry/previews já presentes. Investigar apenas retenção residual demonstrada. | Reimplementar o que já existe não é uma melhoria. |
| Cheatsheet | Preservar última aba como único cache; considerar limite/expiração por tipo de aba se os novos testes mostrarem custo alto. | O Corne medido adicionou 17,646 MiB de PSS e evita reconstruções de 61–158 ms; não é o primeiro corte para buscar 400 MB. |

As escolhas entre instanciar menos, armazenar caches e reduzir tamanho de imagens têm consequências de latência; medir esses efeitos é recomendado pela [documentação de performance da Qt Quick](https://doc.qt.io/qt-6/qtquick-performance.html).

## 7. Manutenção: logs órfãos em tmpfs

Havia **156,313 MiB de logs sem instância ativa**, além dos logs do processo atual. Arquivar somente os IDs confirmados como inativos em um filesystem persistente, com política de retenção. Não apagar tudo em `by-id`.

**Detalhe deste sistema:** `/tmp` também é tmpfs. Mover de `/run/user/1000` para `/tmp` alivia o limite do runtime, mas não é uma solução para reduzir o uso total de memória por tmpfs. Para essa finalidade, o destino deve estar em disco. Os 1,600 GiB de crash logs em `.cache` são outro problema, de armazenamento; limpeza deles não faz o `qs` perder 1,6 GiB de RSS.

Nenhuma limpeza foi executada.

## 8. Protocolo pendente para completar a atribuição por módulo

A medição por processo desta auditoria está concluída. A medição causal por painel depende da etapa que interrompe brevemente a interface; não foi autorizada nem executada nesta entrega.

1. Preservar as preferências e o estado original; trabalhar com uma única instância e uma configuração de teste isolada que não sobrescreva o estado do usuário. Pausar alterações de código durante as rodadas.
2. Estabelecer baseline de início limpo com mesmo monitor, wallpaper, fonte e carga externa. Aguardar estabilização e coletar 60 s por condição, idealmente três rodadas com ordem alternada.
3. Testar um fator por vez: cache da sidebar esquerda; cache da direita; última aba da cheatsheet; Settings; background/widget canvas; dock/bar; AI; telefone; integrações auxiliares. Preservar serviços necessários ao funcionamento, em vez de remover indiscriminadamente singletons.
4. Para cada módulo, registrar: PSS/RSS/privada, CPU própria e dos auxiliares, eventos de criação/compilação, pixmaps, estado do alocador, tempo de primeira abertura e de reabertura. Registrar qual dependência compartilhada foi ativada pela primeira vez.
5. Repetir o mesmo protocolo no checkout end-4. Os 600 MB tornam-se comparáveis somente com essa referência controlada e com funcionalidades equivalentes.
6. Voltar à configuração original e verificar instância única, encerramento dos profilers, estado persistente e ausência de helpers órfãos.

As diferenças por condição são **custos incrementais observados**, não partes independentes que possam ser somadas para chegar ao total: módulos compartilham dependências, fontes, buffers e alocadores. Ganhos finais devem vir do baseline completo otimizado, medido novamente.

**Ordem sugerida:** corrigir duplicação/polling; reduzir consultas VPN e limitar jobs de email; medir cache das sidebars; perfilar heap nativo/compilação; então ajustar caches menores. Chegar a 600 MB é uma hipótese de meta, não uma economia já demonstrada.
