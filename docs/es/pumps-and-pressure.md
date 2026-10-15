# Bombas y presión

## Construir una bomba

La **Bomba de agua** necesita Electrónica 3, Metalistería 2, una Llave para tubos, 2 usos de Soplete, 1 uso de Varillas para soldar, 2 Tubos metálicos, 4 Chapas metálicas, 2 Chatarras electrónicas y 1 Alambre. Construirla da 30 XP de Electrónica y 20 XP de Metalistería. Antes de colocarla, gírala para elegir si conecta en dirección norte–sur o este–oeste.

Para funcionar necesita electricidad y tener su interruptor encendido. En una línea que ya tiene agua, solo aumenta la presión. Junto a un pozo, un río o un lago, además saca agua de ellos y la mete en la red. Colócala abajo: puede [aspirar](glossary.md#aspiracion) agua como mucho 7 m por debajo de ella (unas dos plantas), mientras que empujando hacia arriba suma 25 m. Si pones varias bombas encendidas en la misma línea, sus presiones se suman.

<div class="wp-gallery wp-gallery--2" markdown>
![Bomba con corriente sacando agua de un río o lago](../assets/images/08-pump-source-placement-river-cropped.png){ .wp-screenshot loading=lazy }
![Bomba con corriente sacando agua de un pozo, con la ventana Ver estado de la bomba abierta](../assets/images/08-pump-source-placement-well-cropped.png){ .wp-screenshot loading=lazy }
</div>

## Cómo se calcula la presión

La [presión](glossary.md#presion) se mide en metros de columna de agua (m). Con el modelo **Realista**, que es el que viene por defecto:

- un depósito empieza con 1 m de presión;
- cada planta que la fuente esté por encima del consumidor suma 3 m;
- la distancia resta presión según cuánta agua pase por la tubería y cuántos consumidores la compartan [aguas abajo](glossary.md#aguas-arriba);
- cada bomba encendida y con corriente suma 25 m;
- los enrutadores pueden poner un tope a la presión que sale, pero nunca aumentarla.

El modelo **Simple** tiene en cuenta la altura, pero no la distancia. **Desactivado** recupera el comportamiento antiguo, en el que el agua llega a cualquier punto que esté por debajo del depósito. Con poca presión, el agua sigue llegando, pero más despacio, hasta que baja del mínimo que necesita el consumidor.

![Presión que dan la altura y las bombas](../assets/images/diagram-pressure-es.svg){ .wp-diagram }

- **1** Barril una planta por encima de la línea: 1 m + 1 planta × 3 m = 4 m.
- **2–3** Dos bombas con corriente. Cada una suma 25 m a toda la red, esté donde esté: 4 m + 2 × 25 m = **54 m**.
- **4** Aspersor a 10 casillas. Por ese tramo pasa el agua de los dos aspersores: 54 m − 10 casillas × 2 × 0,2 m = **50 m**.
- **5** Aspersor a 20 casillas. De la casilla 10 a la 20 solo pasa su propia agua: 50 m − 10 casillas × 0,2 m = **48 m**.

Lo que hace cara la distancia es la [demanda compartida](glossary.md#demanda-compartida): cada consumidor de riego que hay más adelante suma su caudal a la pérdida de cada casilla que comparte con los demás.

## Diagnóstico

Haz clic derecho en la bomba y elige **Ver estado de la bomba**: te dirá si está apagada, si no tiene corriente, si no encuentra pozo ni agua cerca o si solo está aportando presión. Para medir la presión en otro punto, construye un **Manómetro** sobre una tubería normal ya colocada (1 Tubo metálico y 1 Chatarra electrónica); con clic derecho verás la presión de esa casilla y si bastaría para un aspersor.

Si a un ramal no le llega suficiente presión: acórtalo, reduce cuántos consumidores funcionan a la vez, divide la instalación en zonas separadas por enrutadores, sube la fuente o añade una bomba con corriente. Todos estos valores se pueden cambiar en las [Opciones de sandbox](sandbox-settings.md).
