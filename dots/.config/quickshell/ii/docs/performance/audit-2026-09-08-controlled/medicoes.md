# Medições controladas por módulo

Valores absolutos do processo Quickshell isolado. RAM em MiB de PSS. A árvore soma os auxiliares observados. Não somar os módulos: eles compartilham serviços e bibliotecas no shell completo.

| Cenário | Núcleo | Antes de abrir | Aberto | Fechado | Descarregado | CPU aberto (%) | CPU fechado (%) | Árvore CPU aberto (%) | VRAM aberta | VRAM fechada | GPU SM média aprox. (%) | GPU SM pico (%) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Dashboard — cache ligado | 156.2 | 245.2 | 292.3 | 282.7 | 270.9 | 8.8 | 1.3 | 10.7 | 43.7 | 2.0 | 0.0 | 0.0 |
| Dashboard — cache desligado | 156.1 | 150.8 | 294.2 | 268.3 | 261.1 | 8.6 | 1.3 | 12.0 | 43.7 | 2.0 | 0.7 | 5.0 |
| Sidebar IA — cache ligado | 156.6 | 254.9 | 332.3 | 313.3 | 313.3 | 0.6 | 0.2 | 0.9 | 32.8 | 1.8 | 0.0 | 0.0 |
| Sidebar IA — cache desligado | 156.3 | 153.5 | 336.5 | 319.5 | 309.0 | 0.5 | 0.2 | 0.8 | 33.4 | 1.8 | 0.0 | 0.0 |
| Calendário pré-carregado → Atalhos | 155.5 | 397.2 | 426.0 | 392.8 | 384.7 | 0.2 | 0.2 | 1.0 | 53.8 | 1.8 | 0.0 | 0.0 |
| Atalhos — cache desligado | 156.0 | 137.9 | 264.8 | 246.9 | 239.3 | 0.1 | 0.1 | 0.1 | 61.8 | 1.8 | 0.0 | 0.0 |
| Calendário mensal | 137.8 | 134.8 | 466.4 | 430.1 | 402.1 | 0.2 | 0.3 | 0.8 | 65.8 | 1.8 | 0.0 | 0.0 |
| Comandos | 156.3 | 137.5 | 267.2 | 244.8 | 244.8 | 1.2 | 0.1 | 1.2 | 51.8 | 1.8 | 0.0 | 0.0 |
| Overview | 156.1 | 140.9 | 316.6 | 310.5 | 310.5 | 18.4 | 1.2 | 22.0 | 81.7 | 2.0 | 9.9 | 39.0 |
| Settings — Cores | 155.1 | 155.1 | 248.6 | 241.6 | 241.7 | 6.0 | 0.1 | 6.0 | 57.6 | 1.8 | 0.0 | 0.0 |
| Settings — Barra | 155.7 | 155.7 | 234.5 | 230.3 | 207.2 | 6.0 | 0.1 | 6.0 | 54.8 | 1.8 | 0.0 | 0.0 |
| Uso de aplicativos | 155.5 | 134.9 | 249.3 | 223.9 | 214.6 | 1.8 | 0.2 | 7.3 | 52.6 | 1.8 | 1.4 | 26.0 |
| Notas | 155.5 | 141.2 | 347.5 | 332.1 | 332.1 | 0.2 | 0.2 | 0.4 | 33.1 | 1.8 | 0.0 | 0.0 |
| Seletor de wallpapers | 155.6 | 137.9 | 226.7 | 212.2 | 212.2 | 0.6 | 0.1 | 0.6 | 47.6 | 1.8 | 0.0 | 0.0 |
| Background + widgets desktop | 156.7 | 156.7 | 302.7 | 234.8 | 234.8 | 0.2 | 0.2 | 0.2 | 145.1 | 1.8 | 0.0 | 0.0 |
| Barra vertical | 156.4 | 153.7 | 450.8 | 403.0 | 400.9 | 17.0 | 0.7 | 31.3 | 44.9 | 2.0 | 2.4 | 20.0 |
| Dock | 156.4 | 156.2 | 245.4 | 241.7 | 232.4 | 14.7 | 0.1 | 14.8 | 18.2 | 1.8 | 5.6 | 35.0 |
| Modo de mídia (inclui Background) | 137.4 | 315.7 | 437.7 | 379.3 | 335.9 | 25.5 | 0.2 | 25.5 | 231.3 | 146.6 | 6.6 | 39.0 |
| Atalhos — cache ligado, mesma aba | 155.1 | 214.5 | 262.6 | 258.5 | 261.4 | 0.1 | 0.1 | 0.1 | 53.8 | 1.8 | 0.0 | 0.0 |
| Atalhos — cache desligado, mesma aba | 155.7 | 137.6 | 265.0 | 256.1 | 251.5 | 0.1 | 0.1 | 0.1 | 61.8 | 1.8 | 0.0 | 0.0 |
| Phone — única política habilitada | 155.9 | 149.4 | 313.2 | 307.2 | 304.1 | 0.2 | 0.2 | 0.6 | 30.6 | 1.8 | 0.0 | 0.0 |
| Calendário mensal — repetição + GC | 155.9 | 136.7 | 472.9 | 409.8 | 408.6 | 0.3 | 0.3 | 0.8 | 65.8 | 1.8 | 0.0 | 0.0 |
| Barra vertical — Privacy desativado | 156.6 | 153.6 | 442.1 | 408.4 | 393.0 | 0.8 | 0.3 | 11.1 | 44.9 | 2.0 | 0.0 | 0.0 |
| Família II — fork | 155.3 | 154.9 | 903.7 | 714.4 | 710.0 | 4.4 | 1.4 | 17.4 | 225.7 | 2.1 | 0.0 | 0.0 |
| Família II — end-4 | 90.7 | 90.1 | 316.0 | 255.5 | 244.0 | 0.6 | 0.5 | 0.6 | 84.5 | 2.0 | 0.0 | 0.0 |
| Barra vertical — referência A/B | 138.3 | 153.6 | 454.4 | 410.0 | 406.5 | 16.3 | 0.7 | 30.6 | 44.9 | 2.0 | 4.8 | 35.0 |
| Barra vertical — apenas layout ativo | 156.4 | 153.9 | 453.0 | 416.5 | 412.2 | 15.9 | 0.9 | 25.3 | 44.9 | 2.0 | 3.0 | 36.0 |
| Modo de mídia — referência A/B | 156.3 | 312.0 | 429.4 | 401.8 | 312.1 | 25.9 | 0.2 | 26.0 | 231.3 | 146.6 | 6.9 | 40.0 |
| Modo de mídia — fundo estático / visualizador desligado | 156.0 | 313.3 | 453.6 | 378.8 | 308.2 | 56.1 | 1.0 | 68.2 | 225.3 | 146.6 | 8.9 | 39.0 |
| Família II — fork sem pré-carregar sidebars/cheatsheet | 156.6 | 156.4 | 666.3 | 517.7 | 512.4 | 6.0 | 1.4 | 21.9 | 225.7 | 2.1 | 2.6 | 36.0 |

## Segunda abertura e coleta explícita

| Cenário | Aberto 1 | Fechado 1 | Aberto 2 | Fechado 2 | Descarregado | Após gc() | Redução adicional por GC |
|---|---:|---:|---:|---:|---:|---:|---:|
| Atalhos — cache ligado, mesma aba | 262.6 | 258.5 | 270.8 | 265.8 | 261.4 | 251.3 | 10.1 |
| Atalhos — cache desligado, mesma aba | 265.0 | 256.1 | 271.3 | 264.2 | 251.5 | 250.2 | 1.3 |
| Phone — única política habilitada | 313.2 | 307.2 | 316.8 | 304.4 | 304.1 | 303.2 | 0.9 |
| Calendário mensal — repetição + GC | 472.9 | 409.8 | N/D | N/D | 408.6 | 393.9 | 14.7 |
| Barra vertical — Privacy desativado | 442.1 | 408.4 | N/D | N/D | 393.0 | 392.6 | 0.4 |
| Família II — fork | 903.7 | 714.4 | N/D | N/D | 710.0 | 666.7 | 43.2 |

## RAM RSS e processos auxiliares

| Cenário | RSS aberto | PSS aberto | PSS da árvore aberto | Auxiliares (diferença) |
|---|---:|---:|---:|---:|
| Dashboard — cache ligado | 417.9 | 292.3 | 331.6 | 39.4 |
| Dashboard — cache desligado | 420.4 | 294.2 | 333.7 | 39.5 |
| Sidebar IA — cache ligado | 447.7 | 332.3 | 336.4 | 4.1 |
| Sidebar IA — cache desligado | 452.1 | 336.5 | 340.6 | 4.1 |
| Calendário pré-carregado → Atalhos | 553.6 | 426.0 | 465.8 | 39.8 |
| Atalhos — cache desligado | 382.0 | 264.8 | 264.8 | 0.0 |
| Calendário mensal | 592.1 | 466.4 | 506.2 | 39.8 |
| Comandos | 378.2 | 267.2 | 267.2 | 0.0 |
| Overview | 432.0 | 316.6 | 355.8 | 39.3 |
| Settings — Cores | 360.9 | 248.6 | 248.6 | 0.0 |
| Settings — Barra | 348.3 | 234.5 | 234.5 | 0.0 |
| Uso de aplicativos | 361.6 | 249.3 | 250.6 | 1.3 |
| Notas | 465.1 | 347.5 | 351.5 | 4.0 |
| Seletor de wallpapers | 338.5 | 226.7 | 226.7 | 0.0 |
| Background + widgets desktop | 422.4 | 302.7 | 306.7 | 4.1 |
| Barra vertical | 575.8 | 450.8 | 504.1 | 53.2 |
| Dock | 360.0 | 245.4 | 261.5 | 16.1 |
| Modo de mídia (inclui Background) | 568.9 | 437.7 | 441.7 | 4.0 |
| Atalhos — cache ligado, mesma aba | 380.3 | 262.6 | 262.6 | 0.0 |
| Atalhos — cache desligado, mesma aba | 382.6 | 265.0 | 265.0 | 0.0 |
| Phone — única política habilitada | 430.1 | 313.2 | 334.0 | 20.8 |
| Calendário mensal — repetição + GC | 598.5 | 472.9 | 512.7 | 39.8 |
| Barra vertical — Privacy desativado | 567.1 | 442.1 | 482.7 | 40.6 |
| Família II — fork | 1055.8 | 903.7 | 975.7 | 71.9 |
| Família II — end-4 | 442.7 | 316.0 | 320.1 | 4.0 |
| Barra vertical — referência A/B | 579.1 | 454.4 | 508.5 | 54.0 |
| Barra vertical — apenas layout ativo | 577.8 | 453.0 | 506.6 | 53.6 |
| Família II — fork sem pré-carregar sidebars/cheatsheet | 799.3 | 666.3 | 736.5 | 70.2 |

---

## Rodada 2: 13 cenários de módulos e 2 de navegação

Fonte: [manifesto](round2/manifest.json), [resumo completo](round2/summary.json) e [validade dos pares](testes-ab.md#rodada-2-reavaliação-dos-15-ensaios-adicionais). Valores de memória em MiB; diferenças calculadas antes de arredondar. Cada cenário tem uma execução. Fases dos módulos: core 20 s, controller 20 s, open 25 s, closed 25 s, reopen 20 s, closed_again 20 s, unloaded 20 s, gc 15 s. Saldo é PSS da fase menos PSS do controlador, não heap exclusivo.

| Cenário | Controller | Open | Closed | Reopen | Closed 2 | Unloaded | GC | Incremento open | Saldo GC |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bar_active_layout | 139,0 | 355,5 | 339,2 | 365,1 | 350,7 | 342,4 | 340,6 | 216,6 | 201,6 |
| bar_no_privacy | 139,1 | 444,4 | 419,7 | 443,6 | 424,1 | 417,5 | 410,4 | 305,4 | 271,3 |
| bar_reference | 139,2 | 394,8 | 368,9 | 403,3 | 379,0 | 374,8 | 369,1 | 255,6 | 229,9 |
| cheatsheet_timetable | 123,0 | 451,4 | 410,7 | 477,4 | 408,3 | 401,7 | 376,7 | 328,4 | 253,7 |
| cheatsheet_timetable_grid_only | 120,4 | 396,1 | 366,7 | 415,7 | 377,2 | 377,3 | 352,2 | 275,8 | 231,9 |
| dashboard_keep | 226,7 | 272,9 | 264,6 | 273,3 | 265,4 | 249,7 | 248,3 | 46,2 | 21,6 |
| dashboard_unload | 135,5 | 322,9 | 296,5 | 324,7 | 301,4 | 300,1 | 297,0 | 187,3 | 161,5 |
| media_reference | 301,7 | 430,5 | 348,8 | 424,5 | 373,3 | 327,1 | 283,0 | 128,8 | -18,7 |
| media_static | 302,0 | 445,0 | 367,9 | 411,2 | 395,0 | 297,2 | 290,9 | 143,0 | -11,1 |
| notes | 126,4 | 332,3 | 297,5 | 317,6 | 313,2 | 305,4 | 299,8 | 205,9 | 173,4 |
| notes_list_only | 121,3 | 176,1 | 172,7 | 179,4 | 176,1 | 175,8 | 168,9 | 54,9 | 47,7 |
| policies_ai_keep | 240,9 | 279,6 | 275,3 | 284,0 | 280,7 | 278,0 | 278,0 | 38,7 | 37,0 |
| policies_ai_unload | 135,6 | 280,7 | 277,5 | 285,1 | 277,9 | 277,9 | 277,7 | 145,1 | 142,0 |

### CPU, GPU e árvore por módulo

| Cenário | RSS open | Árvore PSS open | Auxiliares¹ | CPU qs open | CPU árvore open | CPU árvore closed | CPU árvore unloaded | VRAM open | SM média aprox. |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| bar_active_layout | 496,8 | 408,2 | 52,7 | 15,8 | 26,6 | 6,3 | 6,2 | 44,7 | 2,0 |
| bar_no_privacy | 605,6 | 484,7 | 40,3 | 0,8 | 10,7 | 4,8 | 3,5 | 45,2 | 0,0 |
| bar_reference | 535,9 | 447,0 | 52,3 | 0,8 | 14,8 | 5,6 | 6,9 | 44,7 | 0,0 |
| cheatsheet_timetable | 594,7 | 490,8 | 39,4 | 0,2 | 0,5 | 1,5 | 0,6 | 49,8 | 0,0 |
| cheatsheet_timetable_grid_only | 533,6 | 396,1 | 0,0 | 0,2 | 0,2 | 0,2 | 0,1 | 49,3 | 0,0 |
| dashboard_keep | 416,3 | 311,9 | 39,0 | 8,2 | 11,8 | 3,1 | 3,5 | 37,7 | 10,0 |
| dashboard_unload | 485,9 | 362,2 | 39,4 | 8,6 | 11,9 | 3,1 | 3,2 | 38,6 | 0,0 |
| media_reference | 578,8 | 439,6 | 9,1 | 67,8 | 68,8 | 5,0 | 3,3 | 237,6 | 13,6 |
| media_static | 626,1 | 454,0 | 9,0 | 57,5 | 58,7 | 5,4 | 3,0 | 214,1 | 4,7 |
| notes | 466,9 | 336,3 | 3,9 | 0,2 | 0,4 | 0,6 | 0,5 | 33,1 | 0,0 |
| notes_list_only | 305,8 | 176,1 | 0,0 | 0,1 | 0,1 | 0,2 | 0,1 | 33,1 | 0,0 |
| policies_ai_keep | 410,9 | 283,6 | 4,0 | 0,5 | 0,8 | 0,5 | 0,5 | 22,7 | 0,0 |
| policies_ai_unload | 412,2 | 284,8 | 4,0 | 1,0 | 1,2 | 0,9 | 0,6 | 23,1 | 0,0 |

¹ Diferença entre medianas da árvore e do processo; não uma medição de heap exclusivo. CPU usa 100% = um núcleo. SM é aproximação NVML, não energia nem utilização global. Todas as demais métricas/fases estão no JSON.

### Navegação da família

| Fase histórica | PSS keep | PSS unload | Variação PSS | Árvore keep | Árvore unload |
| --- | --- | --- | --- | --- | --- |
| core | 848,8 | 645,5 | -203,4 | 924,9 | 720,3 |
| open_policies_ai | 862,0 | 660,3 | -201,8 | 938,6 | 736,3 |
| nav_policies_phone | 869,4 | 662,5 | -206,9 | 946,4 | 738,8 |
| policies_closed | 879,0 | 663,0 | -216,0 | 956,6 | 739,7 |
| open_cheatsheet_keybinds | 877,4 | 692,7 | -184,6 | 955,0 | 769,7 |
| nav_cheatsheet_timetable | 929,4 | 882,3 | -47,1 | 1007,1 | 960,2 |
| cheatsheet_closed | 914,8 | 864,6 | -50,1 | 992,7 | 942,6 |
| open_dashboard | 926,3 | 819,0 | -107,3 | 999,3 | 897,1 |
| dashboard_closed | 923,6 | 814,5 | -109,1 | 1001,8 | 892,8 |
| idle_settled | 920,3 | 788,5 | -131,8 | 998,9 | 866,9 |
| gc | 914,5 | 779,1 | -135,3 | 993,0 | 857,8 |

`core` já contém a família inteira carregada; não é um núcleo vazio. A sequência tem **180 s programados**, incluindo **25 s de idle final e 15 s de GC**; descartar os cinco segundos iniciais de cada fase reduz ainda mais a janela útil. O benefício observado foi **131,8 MiB PSS no idle e 135,3 MiB pós-GC**, sem evidência de permanência por horas ou de cobertura de todos os painéis pesados. Notas e Overview, por exemplo, não foram visitados.

O registro de MPRIS foi `Playing` em todas as fases de `unload`; em `keep`, `open_dashboard` registrou **Paused**, e as demais Playing. A comparação não ficou inteiramente controlada. Ambos os logs registraram um aviso de binding loop em `Dock.qml` e um de atribuição em `AndroidNetworkToggle.qml`; não foram quantificados como causa de consumo.

**RAM menor não trouxe idle barato:** a CPU da árvore no idle final foi **34,5% com cache / 33,0% sem cache**; VRAM foi **222,9 MiB em ambos**. Após GC, CPU foi 33,2% / 30,5%. Desligar retenção não resolve o custo contínuo da família. Não há execução do end-4 com essa mesma sequência na rodada 2.
