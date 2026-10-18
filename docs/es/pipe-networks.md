# Redes de tuberías

## Recetas de tuberías

| Construcción | Herramienta | Materiales que se gastan |
|---|---|---|
| Tubería de fluidos | Llave para tubos | 1 Tubo metálico **o** 1 Segmento de tubería de arcilla (cocido) |
| Tubería vertical de fluidos | Llave para tubos | 1 Tubo metálico **o** 1 Segmento de tubería de arcilla (cocido) |
| Tubería de fluidos oculta | Llave para tubos | 1 tubo o segmento y 1 cubo lleno de cemento de arcilla o de hormigón |
| Tubería vertical de fluidos oculta | Llave para tubos | 1 tubo o segmento y 1 cubo lleno de cemento de arcilla o de hormigón |

La Llave para tubos no se gasta. Ninguna de estas tuberías pide nivel de [habilidad](glossary.md#habilidad). Si te faltan tubos metálicos, puedes forjarlos en una Forja Primitiva con Carbón vegetal, una Barra de hierro - Media y una Barra de hierro - Cuarto, usando un martillo, unas tenazas o unos alicates y un punzón (consulta el [catálogo](component-reference.md#receta-relacionada)).

!!! note "Consumo de cemento"
    Cada tubería oculta gasta un cubo entero, así que cada cubo da para una sola casilla de tubería. Sirven el Cubo de cemento de arcilla y el Cubo con hormigón, tanto en cubo normal como en cubo tallado.

## Colocación y conexiones

Las tuberías de suelo se unen solas con las vecinas y forman extremos, rectas, esquinas, uniones en T y cruces. En cada [casilla](glossary.md#casilla) solo cabe una tubería de suelo. Los componentes que solo conectan en una dirección (bomba, enrutador) se giran con **R** antes de colocarlos. Las [tuberías verticales](glossary.md#tuberia-vertical) se montan en paredes norte u oeste y unen las tuberías de dos plantas; en una misma casilla caben una tubería de suelo y las dos verticales (la de la pared norte y la de la oeste).

Las [tuberías ocultas](glossary.md#tuberia-oculta) funcionan exactamente igual, pero desaparecen de la vista al terminar de construirlas. Para verlas, usa **[Mostrar red de tuberías](glossary.md#mostrar-red)** sobre cualquier tubería, visible u oculta: toda la red se resalta durante un rato. **Ocultar red de tuberías** la vuelve a ocultar antes de que desaparezca sola.

!!! tip "Encontrar una red oculta"
    Si no queda ninguna tubería visible sobre la que usar **Mostrar red de tuberías**, elige :material-hammer-screwdriver: **Desmontar** en la barra de acciones de la izquierda. Con su cursor puedes señalar las tuberías ocultas y ver por dónde van. Cancela la acción cuando las encuentres, salvo que de verdad quieras quitar ese tramo.

![Formas que toman las tuberías solas y una tubería vertical entre dos plantas](../assets/images/03-pipe-shapes-cropped.png){ .wp-screenshot loading=lazy }

## Desmontaje y recuperación

Usa la acción :material-hammer-screwdriver: **Desmontar** del juego, no la herramienta para recoger y mover objetos.

- Una tubería metálica construida por ti tiene un 90 % de probabilidades de devolver un Tubo metálico.
- Una tubería de arcilla no devuelve nada: el segmento se gasta al colocarlo.
- Las tuberías ocultas que aparecen con **Conectar la fontanería del edificio** no devuelven nada, porque esa acción se paga por aparato conectado, no por tubería.
- Si la tubería se destruye (con una Almádena, por el fuego o por daños), no devuelve nada.
- Si desmontas una tubería que tiene encima una válvula o un manómetro, cada material de ese componente se recupera por separado, con un 90 % de probabilidades cada uno.

Si quitas la tubería de la casilla de un aparato o un generador instalado, se desconecta automáticamente.
