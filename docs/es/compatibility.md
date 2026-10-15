# Compatibilidad

## Qué se necesita

| Elemento | Estado |
|---|---|
| Project Zomboid | Build 42.15 o posterior |
| Water Pipes | Esta guía cubre la serie v0.10.x |
| Un jugador | Funciona |
| [Multijugador](glossary.md#multijugador) y servidores dedicados | Funciona; las construcciones y los movimientos de líquido los decide y comprueba el servidor |
| Idiomas del mod | Inglés, español y chino simplificado |
| Idiomas de esta guía | Inglés y español |

Está comprobado que funciona con los aparatos de **Take A Bath And Shower** y con los barriles de **Useful Barrels**. El mod reconoce los depósitos por cómo se comportan, no por una lista de nombres, y avisa cada vez que cambia su nivel para que los mods de barriles puedan actualizar su dibujo. Aun así, un mod que no se ha probado no tiene la compatibilidad garantizada.

## Servidores dedicados: lista de comprobación

1. Instala el mod desde Steam Workshop (ID `3739595559`) en el servidor y en todos los jugadores.
2. Añade el ID de mod `waterpipes` y usa la misma versión en todos.
3. Ajusta el grupo de opciones de sandbox **Tuberías de Agua** antes de empezar o reiniciar la partida.
4. Haz una copia de seguridad de la partida antes de actualizar, y después de actualizar prueba las redes importantes.
5. Si un aparato conectado con una versión anterior funciona mal, desinstálalo y vuelve a instalarlo.

## Retirar el mod

Haz antes una copia de seguridad. En Build 42, quitar de una partida existente un mod que añade objetos construibles puede provocar un error de carga `WorldDictionary`. Desmonta los objetos de Water Pipes que puedas, detén el servidor, haz otra copia de seguridad y quita el mod del servidor y de todos los jugadores a la vez. Si la partida no carga, restaura la copia y sigue la [guía de recuperación de World Dictionary](https://steamcommunity.com/sharedfiles/filedetails/?id=3187340365).

## API para autores de mods

*Esta sección es para programadores que quieran conectar su propio mod con Water Pipes.*

Desde que arranca la partida o el servidor está disponible la tabla global `WaterPipesAPI`. Cada función recibe un `IsoGridSquare` (una casilla) que contenga una tubería:

| Miembro | Devuelve |
|---|---|
| `VERSION` | Versión de la API; ahora mismo, `1` |
| `hasNetwork(square)` | Si hay una red conectada a esa casilla |
| `getWaterAmount(square)` | Cantidad utilizable, o `0` si no hay nada o si la red tiene a la vez líquidos incompatibles |
| `getWaterSummary(square)` | `{ amount, capacity, fluidType, isMixed }` o `nil`. `isMixed` indica que la red tiene depósitos con líquidos distintos, no que haya líquidos mezclados dentro de un mismo depósito |
| `drawWater(square, fluidType, amount)` | Cantidad que se ha sacado realmente |
| `fillWater(square, fluidType, amount)` | Cantidad que se ha añadido realmente; nunca crea una mezcla |

Las funciones de lectura se pueden usar en el servidor y en los clientes. `drawWater` y `fillWater` cambian el contenido de los depósitos, así que solo funcionan en el servidor o en una partida de un jugador; en un cliente multijugador devuelven `0`. Comprueba siempre que `WaterPipesAPI` existe antes de usarla.
