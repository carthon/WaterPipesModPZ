# WaterPipes

Base de un mod para Project Zomboid Build 42.15.x orientado a redes de agua construibles.

## Objetivo

Permitir colocar tramos de tuberia en celdas del mundo y enlazar recipientes entre si para compartir el liquido de una misma red. La primera iteracion se centra en una version simple:

- Las tuberias forman una red ortogonal por casillas.
- Los recipientes conectados comparten el volumen total del fluido de la red.
- Cualquier objeto del mundo colocable con `FluidContainer` finito sera candidato a conectarse.

## Estado actual

Este repositorio ya incluye:

- Estructura de mod Build 42 con carpeta `common` obligatoria.
- `mod.info` para la rama `42.15`.
- Nucleo Lua para modelar grafos de red, persistir estado y detectar contenedores candidatos.
- Un sistema servidor inicial para reconstruir y equilibrar la red periodicamente.
- Un primer objeto construible de pipe con menu contextual y registro en la red.
- Cursor de colocacion con 4 modos temporales: suelo E/O, suelo N/S, pared E/O y pared N/S.
- Deteccion generica de contenedores placeables con `FluidContainer` real de B42.
- Redistribucion de un unico tipo de fluido por red; las redes con mezclas se omiten por seguridad.
- Endpoints genericos de consumo usando la señal vanilla `waterPiped` / `canBeWaterPiped`.
- Menus contextuales de `Drink`, `Fill` y `Wash` en sinks, duchas, toilets y moveables equivalentes conectados a la red.
- Menu debug contextual para forzar corte global de agua y tick de red cuando Zomboid arranca en debug.

Todavia falta cerrar:

- Sprite definitivo y tiledefs propios.
- Sincronizacion mas fina en multijugador y con plumbing vanilla.
- Tests dentro del juego y ajuste de APIs exactas de B42.15.3.

## Estructura

- `Contents/mods/WaterPipes/common`: codigo compartido entre versiones.
- `Contents/mods/WaterPipes/42.15`: codigo y metadatos para Build 42.15.x.
- `docs/architecture.md`: decisiones tecnicas de la primera version.

## Instalacion local

Este workspace esta pensado para vivir como carpeta de desarrollo del mod. Para probarlo en local, copia la carpeta raiz al arbol de Workshop de Zomboid respetando esta estructura:

```text
Zomboid/Workshop/WaterPipes/
  Contents/mods/WaterPipes/...
```

## Siguiente paso recomendado

Conectar recipientes vanilla concretos de forma mas fiable y ampliar el build flow con desmontaje dedicado, receta y assets propios.

## Prueba rapida

En esta version la construccion usa items vanilla:

- `Base.Pipe`
- `Base.PipeWrench`

Con ambos en el inventario, al hacer clic derecho sobre una casilla valida aparece `Water Pipes -> Lay Pipe`.
Durante la colocacion, la tecla de rotacion de construccion recorre estos modos:

- Suelo E/O.
- Suelo N/S.
- Pared E/O.
- Pared N/S.

Los placeholders actuales usan una familia visual `wire`:

- Suelo: `fencing_01_20` y `fencing_01_21`.
- Pared: `fencing_01_26` y `fencing_01_25`.

## Endpoints de uso

La red tambien puede alimentar puntos de consumo del mundo:

- Si un objeto marca soporte vanilla de plumbing (`waterPiped`, `canBeWaterPiped` o equivalente) y toca una red con `Water` o `TaintedWater`, aparecen opciones de `Drink`, `Fill` y `Wash`.
- El mod usa el objeto real para alcance y animacion, pero el liquido se consume del conjunto de depositos conectados.
- Estos endpoints no cuentan como almacenamiento; el almacenamiento sigue viniendo de `FluidContainer` placeables finitos.
