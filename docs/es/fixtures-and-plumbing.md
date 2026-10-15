# Aparatos y fontanería

## Qué objetos se pueden conectar

Water Pipes reconoce como [aparato](glossary.md#aparato) cualquier objeto que el propio juego marque como conectable a una tubería o como alimentado por agua externa, además de las tres lavadoras de Build 42. En la práctica:

| Tipo | Ejemplos | Qué hace con la red |
|---|---|---|
| Grifos y lavabos | Fregaderos y lavabos | Beber, lavarse, llenar recipientes y trasvasar agua desde la red |
| Baño | Duchas, bañeras e inodoros | Consumen agua |
| Electrodomésticos | Lavadora, lavadora-secadora y lavadora-secadora apilada | Llenan su propio depósito interno |
| Aparatos de otros mods | Por ejemplo, Take A Bath And Shower | Consumen agua si el mod los marca como el juego espera |

El mod no usa una lista cerrada de objetos: reconoce cualquier aparato que el juego marque de esa forma, así que muchos aparatos de otros mods funcionan sin estar nombrados aquí.

## Conectar un aparato

1. Construye una tubería de suelo en la **misma casilla** del aparato.
2. Lleva una Llave para tubos utilizable.
3. Haz [clic derecho](glossary.md#clic-derecho) en el aparato y elige **[Instalar](glossary.md#instalar)** (aparece seguido de su nombre, por ejemplo «Instalar Fregadero»).
4. Úsalo como siempre. Si no le llega agua, usa **Mostrar red de tuberías** para ver qué falla.
5. Para desconectarlo, elige **Desinstalar**: el aparato vuelve a quedar como estaba, con su agua y su conexión a la red municipal originales.

Si quitas la tubería de su casilla, el aparato también se desconecta; un corte más lejos en la tubería solo lo deja sin agua. Mientras la ciudad siga teniendo agua corriente y la opción de sandbox correspondiente esté activada, un aparato instalado dentro de una casa mete en tu red agua limpia y la presión de la [red municipal](glossary.md#red-municipal).

!!! note "La lavadora"
    Una lavadora conectada se sigue usando desde su ventana de inventario. Cuando su depósito tiene agua, Build 42 puede quitar del menú de clic derecho la opción **Encender**, que ya está repetida en esa ventana.

![Tubería en la casilla de un fregadero con la opción Instalar visible](../assets/images/19-fixture-plumb-menu-cropped.png){ .wp-screenshot loading=lazy }
<!-- SCREENSHOT: 20-supported-fixtures.png — Fregadero, ducha, inodoro y lavadora conectados a la misma red. -->
