# VolumeTweak

App de barra de menus para macOS que ajusta o volume de cada app individualmente (0–200%, com mudo).

## Requisitos
- macOS 14.2+ (usa Core Audio Process Taps)
- Swift 5.10+ (Command Line Tools bastam)

## Build
```sh
./build.sh            # gera build/VolumeTweak.app
./build.sh --install  # instala em /Applications e abre
```

Na primeira alteração de volume, o macOS pede permissão de captura de áudio do sistema.

## Como funciona
Apps em 100% não são tocados. Para os demais, um process tap captura o áudio do app
(silenciando a saída original), aplica o ganho e reproduz no dispositivo de saída padrão
por meio de um aggregate device privado. Processos auxiliares (ex.: helpers do Chrome) são
agrupados ao app principal. Trocas de dispositivo de saída recriam os taps automaticamente.

## Limitações
- O áudio de apps ajustados é mixado em estéreo.
- Ganho acima de 100% é limitado em ±1.0 (pode distorcer).
