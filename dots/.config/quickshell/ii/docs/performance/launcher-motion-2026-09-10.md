# Launcher: abertura, digitação e fundo da Overview

## Escopo e evidências

Investigação por código e execução de bindings QML em Qt 6.11.2 offscreen. Não foram
feitas chamadas IPC, capturas do desktop, abertura automatizada de painéis nem
reinício do Quickshell. Não há medição de FPS ou promessa percentual de ganho.

Configuração observada: shell Default, fundo Gnome, previews ao vivo habilitados,
blur do wallpaper com janelas abertas, cascade da overview habilitada e decode
limitado por `scaleLargeWallpapers`. Busca e ranking foram preservados.

O custo identificado é a concorrência entre o trabalho de busca, as animações QML
e os render targets usados para efeitos. A auditoria anterior continua relevante:
o compositor também paga pela composição/blur das superfícies animadas. Estas
correções não desativam a transparência nem reconfiguram o Hyprland.

## Problemas e alterações

| Caminho | Antes | Agora |
| --- | --- | --- |
| Search em abertura | A primeira tecla sobrescrevia a supressão de transições; cada delegate novo iniciava fade/stagger independentemente dela. | O host fornece `surfaceAnimating`, incluindo a animação do fundo do monitor. Resultados chegam imediatamente enquanto a superfície anima ou a digitação está em rajada; sequências pendentes terminam no estado visível. |
| Blur do Search | Layer permanente, inclusive totalmente aberto; a primeira busca redimensionava o target e a cadeia de blur durante a entrada. | Blur somente na transição da superfície vazia. Com query/painel, slide e fade continuam sem o blur. No repouso o wrapper não tem layer. |
| Overview oculta | `opacity < 0.999` habilitava a layer também em zero; previews continuavam com `live: true` e as cascatas seguiam rodando. | Layers somente entre os extremos visíveis; a grade fica invisível, mantendo os objetos residentes. Previews suspendem `live`; timers/cascatas são encerrados. |
| Retorno à grade | Recaptura era agendada mesmo em previews ao vivo e ocultos. | Frozen previews atualizam uma vez ao reaparecer; live previews retomam o stream. Chamadas redundantes ao timer foram removidas. |
| Plano do wallpaper | A máscara do pai e uma layer de conteúdo intermediária criavam dois targets sobre o mesmo plano durante Gnome. | A máscara do pai basta; a layer interna permanece apenas para o caminho da lockscreen. |
| Fonte do backing blur | O wallpaper já era decodificado em 1/8, mas seu wrapper requeria proxy em tamanho de tela. | O wrapper publica uma textura com largura/altura de 1/4. O MultiEffect reutiliza a textura sem proxy adicional, mantendo o crop e o raio lógico do efeito. |
| Material Shape | O wallpaper alimentava a textura da máscara durante outros presets. | A fonte fica `null` e `live` fica falso fora de Material Shape; a mesma proteção vale no canvas de widgets. |
| Fechamento Gnome | O backing blur era destruído assim que `active` virava falso, antes do fim do zoom. | O efeito sobrevive até o progresso chegar ao fim do fechamento. |

O target da fonte de backing passa de W×H para ceil(W/4)×ceil(H/4): em 3840×2160,
960×540. Isso representa 1/16 dos texels **dessa fonte**; não significa redução de
1/16 no custo total do blur, da GPU ou da composição. O orçamento é estável durante
o zoom, sem depender do progresso animado.

Também foi removido `cascadeProgress` de `OverviewWidget`: tinha uma animação
de 480 ms por abertura, mas nenhum consumidor visual. As cascatas efetivas de
workspaces/janelas permanecem habilitadas pela preferência existente.

## Verificação

`python3 scripts/tests/run_launcher_motion_smoke.py` executa trechos de produção,
substituindo somente serviços/janelas por fixtures inertes. São 17 cenários, mais
setup/cleanup: **19 passaram**. Antes das correções, os dez cenários iniciais de
regressão falhavam; a edição deliberada após abertura já passava.

Cobertura: primeira tecla durante entrada; edição isolada e rajada; targets do
Search e da grade oculta; máscara por preset; backing no fechamento; tamanho de
textura estável; layers do wallpaper/lock; delegates sem stagger pendente; cascata
oculta antes e depois de iniciar; captura frozen ao retornar e ausência de timer
redundante em live preview.

Revisão independente validou também o comportamento real do Qt: a visibilidade
ancestral chega ao tile, e `MultiEffect.hasProxySource` fica falso ao receber o
item com layer reduzida. A fonte oficial do Quickshell confirma que reativar
`live` solicita um frame novo. Ver
[ScreencopyView](https://quickshell.org/docs/v0.3.1/types/Quickshell.Wayland/ScreencopyView/)
e [MultiEffect](https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html).

Os 61 contratos existentes de Search/background têm a mesma base antes/depois:
49 passaram, 11 falhas e 1 erro preexistentes (incluem versões antigas de config,
assertivas de implementações substituídas e `SuggestionsPanel.qml` ausente).
Nenhuma falha nova foi introduzida nesse conjunto. O `qmllint` ainda reporta
diagnósticos de resolução do projeto; a análise não encontrou erros de sintaxe.

## Limites e próxima medição

Os testes offscreen verificam coordenação, fontes e lifecycle; não medem fluidez
no compositor nem substituem observação visual. Para atribuir um ganho real,
comparar intervalos de apresentação de frames em abertura vazia, abertura com
digitação imediata e busca após a entrada, mantendo wallpaper, número de janelas,
monitores e estado quente/frio iguais. Uma coleta global de uso de GPU não separa
o trabalho do shell do trabalho do Hyprland.

## Material Shape: máscara estática e movimento no shader

O pedido foi ampliado para Material Shape. O caminho anterior criava uma
`MaterialShape` no wallpaper e outra no canvas dos widgets. Como ela herda de
`ShapeCanvas`, cada novo sorteio iniciava `Morph` + `requestPaint()` por cerca de
350 ms. Além disso, dois `ShaderEffectSource` desenhavam essas formas transformadas
em texturas do tamanho de cada monitor durante o zoom/rotação.

`OverviewMaterialMask.qml` agora renderiza uma silhueta estática do tamanho do
diâmetro da forma. O fragment shader `overviewMaterialMask.frag` aplica a inversa
da escala/rotação às coordenadas da máscara e combina a amostra com a textura do
conteúdo na mesma passagem. As duas superfícies usam o mesmo componente e os
mesmos valores do controller do monitor; cada janela mantém sua textura local.

- Escala e rotação continuam iguais; o morph entre o sorteio anterior e o novo é
  instantâneo. O movimento visível continua vindo do controller da overview.
- O tamanho da silhueta não segue o progresso: o zoom só altera uniforms, sem
  repintar Canvas nem atualizar uma máscara fullscreen.
- A máscara retangular auxiliar fica desligada nesse preset.
- Com sombra Material Shape habilitada, o wallpaper conserva o MultiEffect
  anterior para respeitar padding e formato da sombra; sua forma também perde
  o morph concorrente. Esse fallback é lazy e não existe sem sombra. Os widgets
  usam o shader novo em ambos os casos.

`python3 scripts/tests/run_overview_material_mask_smoke.py` usa o componente real,
o MaterialShape real e as bibliotecas de polígonos, em Qt offscreen com RHI/OpenGL
e Mesa por software: **9 verificações passaram** (7 cenários + setup/cleanup).
O shader embarcado carregou, as 18 formas foram exercitadas, e 15 atualizações de
escala/rotação não produziram nenhum sinal `Canvas.painted`. A transformação
inversa foi comparada a `Item.mapToItem()` do caminho antigo em orientação
horizontal, vertical e ultrawide, com quatro escalas e três ângulos.
O teste da layer verifica pixels de uma cena sintética offscreen (fundo azul e
conteúdo verde), confirmando recorte no canto e conteúdo no centro, além da
liberação do efeito ao desativar a layer. Nenhum pixel do desktop é lido.

O teste do launcher continua com 19 passes: total **28**, sem substituir uma
medição de frames no Hyprland. O contrato de widgets foi atualizado para exigir
o efeito compartilhado no lugar da antiga máscara fullscreen.

Recompilação do shader (executada com Qt 6.11.2):

```bash
/usr/lib64/qt6/bin/qsb --glsl '100 es,120,150' --hlsl 50 --msl 12 \
  -o modules/ii/background/shaders/overviewMaterialMask.frag.qsb \
  modules/ii/background/shaders/overviewMaterialMask.frag
```

O `.frag` e o `.frag.qsb` devem ser entregues juntos. Referência do contrato de
uniforms/texturas: [Qt ShaderEffect](https://doc.qt.io/qt-6/qml-qtquick-shadereffect.html).
