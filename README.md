# WaterPipes

Mod experimental para Project Zomboid Build 42.15.x orientado a redes de agua construibles.

## Objetivo

Permitir colocar tuberias en el mundo y enlazar recipientes placeables con fluidos para que compartan una misma red. La version actual busca una base estable antes de meterse en bombas, valvulas, presion o filtrado.

## Estado actual

El mod ya incluye:

- Estructura valida para Build 42.15 con `mod.info`, `tiledef=waterpipes 1000` y `pack=waterpipes`.
- Pipe construible desde el menu de construccion vanilla en la categoria `Piping`.
- Cursor de colocacion con 4 modos: suelo E/O, suelo N/S, pared E/O y pared N/S.
- Tiles propios del mod (`waterpipes_01_*`) para las pipes visibles.
- Deteccion generica de contenedores del mundo con `FluidContainer` finito.
- Redistribucion de un unico fluido por red. Si una red mezcla fluidos distintos, se omite por seguridad.
- Conectividad horizontal y vertical entre pipes, incluyendo `z+1 / z-1`.
- Integracion con plumbing vanilla: al usar `Plumb` sobre un endpoint conectado a una pipe del mod, el flujo se redirige a la red del mod; si no, se mantiene el comportamiento vanilla.
- Fuente adaptadora oculta sobre el endpoint para que el motor acepte la red como `external water source`.
- Filtro del menu contextual para que el adaptador oculto no exponga sus propias opciones de agua.
- Opcion `Unplumb` propia del mod para soltar el endpoint de la red.
- Debug menu para forzar corte global de agua, tick de red y dumps de diagnostico cuando el juego esta en debug.

## Limitaciones actuales

- El adaptador oculto sigue siendo una solucion tecnica para encajar con el plumbing vanilla interno del motor.
- El mod esta orientado a agua y agua contaminada. Otros fluidos se redistribuyen entre contenedores, pero la integracion con endpoints de consumo esta pensada para agua.
- No hay todavia sistemas de presion, perdida, prioridad, bombas o filtrado.
- No esta validado a fondo en multijugador.

## Estructura

- `Contents/mods/WaterPipes/42.15`: codigo y metadatos para Build 42.15.x.
- `docs/architecture.md`: resumen tecnico del sistema actual.
- `docs/texturepack.md`: notas del tileset y del empaquetado.
- `tools/`: recursos auxiliares para trabajo con Modding Tools.

## Instalacion local

La carpeta que debe leer Project Zomboid es:

```text
Contents/mods/WaterPipes
```

Para pruebas locales, monta esa carpeta en:

```text
C:\Users\<tu_usuario>\Zomboid\mods\WaterPipes
```

Lo mas practico es usar una junction de Windows apuntando a:

```text
<workspace>\Contents\mods\WaterPipes
```

## Construccion

La construccion ya no va por clic derecho sobre el suelo. Ahora usa el flujo vanilla del panel de construccion:

- Categoria: `Piping`
- Receta: `Water Pipe`
- Requisitos:
  - `Base.Pipe`
  - `Base.PipeWrench` en modo `keep`

Durante la colocacion, la rotacion recorre:

- Suelo E/O
- Suelo N/S
- Pared E/O
- Pared N/S

Sprites usados ahora:

- Suelo E/O: `waterpipes_01_24`
- Suelo N/S: `waterpipes_01_25`
- Pared E/O: `waterpipes_01_11`
- Pared N/S: `waterpipes_01_26`

## Plumbing y consumo

Los endpoints vanilla compatibles con plumbing se integran asi:

- Si haces `Plumb` sobre un sink, ducha, water source o equivalente y hay una pipe del mod en su misma casilla con una red valida, el mod intercepta esa accion y lo conecta a la red.
- Si no hay red valida del mod en la casilla, `Plumb` sigue el comportamiento vanilla.
- El endpoint usa las acciones vanilla de beber, llenar y lavar.
- El mod no parchea esas acciones para cambiar menus; lo que hace es proporcionar una `external water source` compatible con el motor.

Prioridad actual:

- Si el endpoint se plumba a una casilla con pipe del mod y red activa, la red del mod tiene prioridad.
- La coexistencia con un `rain barrel` real encima se resuelve manteniendo el barrel real visible e interactuable y ocultando el proxy del mod.

## Flujo de prueba rapido

1. Coloca una o varias pipes desde `Piping -> Water Pipe`.
2. Coloca contenedores placeables con agua en la red.
3. Conecta un sink o endpoint equivalente a una casilla con pipe.
4. Usa `Plumb`.
5. Si quieres probar sin agua del mapa, usa el debug menu del mod para forzar el corte global.

## Siguiente trabajo razonable

- Refinar sprites y variantes de conexion automaticas.
- Mejorar casos de esquina con multiples fuentes vanilla alrededor del endpoint.
- Validar la conservacion de agua en mas configuraciones complejas y en multijugador.
