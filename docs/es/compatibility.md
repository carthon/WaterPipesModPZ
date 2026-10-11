# Compatibilidad

## Entorno compatible

| Componente | Estado |
|---|---|
| Project Zomboid | Build 42.15 o posterior |
| Water Pipes | La documentación corresponde al mod v0.10.0 |
| Un jugador | Compatible |
| Multijugador y servidor dedicado | Compatible; construcción y cambios de fluido son autoritativos en servidor |
| Idiomas del mod | Inglés, español y chino simplificado |
| Idiomas de esta guía | Inglés y español |

Las integraciones confirmadas son los aparatos de **Take A Bath And Shower** y los recipientes de **Useful Barrels**. Los recipientes se detectan por capacidades y se notifican cambios para que mods de barriles actualicen sus sprites, pero un mod no probado no queda garantizado.

## Lista para servidores dedicados

1. Instala el objeto de Workshop `3739595559` en servidor y clientes.
2. Añade el ID de mod `waterpipes` y conserva la misma versión en todos.
3. Configura el grupo de sandbox Water Pipes antes de iniciar o reiniciar la partida.
4. Haz copia antes de actualizar y prueba las redes importantes después.
5. Si un aparato antiguo se comporta mal tras migrar, desinstálalo y vuelve a fontanearlo.

## Retirar el mod

Haz primero una copia de seguridad. Los mods de Build 42 con objetos construibles pueden provocar un error `WorldDictionary` al retirarlos de un mundo existente. Desmonta los objetos de Water Pipes cuando sea posible, detén el servidor, crea otra copia y elimina el mod de servidor y clientes a la vez. Si el mundo falla, restaura la copia y sigue la [guía de recuperación de World Dictionary](https://steamcommunity.com/sharedfiles/filedetails/?id=3187340365).

## API para desarrolladores

El global compartido `WaterPipesAPI` está disponible desde el arranque de partida/servidor. Pasa una `IsoGridSquare` que contenga tubería:

| Miembro | Resultado |
|---|---|
| `VERSION` | Versión de API; actualmente `1` |
| `hasNetwork(square)` | Si hay una red alcanzable |
| `getWaterAmount(square)` | Cantidad utilizable, o `0` si está vacía/mezclada |
| `getWaterSummary(square)` | `{ amount, capacity, fluidType, isMixed }` o `nil` |
| `drawWater(square, fluidType, amount)` | Cantidad realmente retirada |
| `fillWater(square, fluidType, amount)` | Cantidad añadida; nunca crea mezclas |

Las lecturas son seguras en ambos lados. `drawWater` y `fillWater` modifican recipientes y solo funcionan en servidor o un jugador; en un cliente multijugador normal devuelven `0`. Comprueba siempre que exista `WaterPipesAPI`.

