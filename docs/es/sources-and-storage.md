# Fuentes y almacenamiento

## Qué se une a una red

Un recipiente de fluidos finito se incorpora cuando una tubería de suelo ocupa su **propia casilla**. Esto incluye barriles y recolectores del juego base, ánforas y tanques, además de recipientes de otros mods que expongan una capacidad normal. Las lavadoras y demás aparatos se tratan como consumidores, no como depósitos. Los objetos con capacidad de 9999 o más se excluyen del equilibrado de recipientes finitos; solo actúan como fuentes cuando una lógica específica los reconoce como tales.

El almacenamiento se asienta cada dos minutos de juego: primero se llenan las plantas inferiores y los recipientes de la misma planta se nivelan según su capacidad. Una bomba no almacena; incluye siempre un recipiente donde pueda quedar el agua entrante.

![Orden de almacenamiento por gravedad](../assets/images/diagram-storage-gravity.svg){ .wp-diagram }

- **1** Recipientes de la planta inferior: se llenan y se nivelan primero.
- **2** Recipiente de la planta superior: recibe el agua que rebosa cuando los de abajo están llenos.

| Fuente | Fluido | Caudal o reserva predeterminados | Preparación |
|---|---|---:|---|
| Barril, recolector, ánfora o tanque | Contenido existente | Capacidad del recipiente | Coloca una tubería en su casilla; destapa los recipientes que solo exponen almacenamiento al abrirlos |
| Pozo | Agua limpia | Bomba: 20 L/min | Coloca una bomba con corriente dentro del alcance de aspiración |
| Río o lago | Agua contaminada | Bomba: 20 L/min, fuente ilimitada | Coloca una bomba junto al agua; debe permitirlo la opción de sandbox |
| Red municipal | Agua limpia | 60 L/min a 25 m de presión | Fontanea un aparato interior antes del corte del agua |
| Boca de incendios | Agua limpia | 60 L/min; reserva de 1000 L tras el corte | Coloca una tubería en su casilla y ábrela con una Llave para tubos |

<!-- SCREENSHOT: 06-source-types.png — Ejemplos de barril, bomba en pozo, bomba en agua abierta, aparato municipal e hidrante. -->

## Calidad y mezcla de fluidos

El agua limpia y contaminada se combinan como agua contaminada. Con purificación realista, solo el **Purificador de agua (eléctrico)** recupera agua limpia. Agua y gasolina en un mismo componente forman una red mezclada; se detienen el suministro a aparatos y el repostaje de generadores.

Para recuperar una red mezclada, cierra una válvula o desmonta una tubería de enlace para aislar los líquidos y después vacía o sustituye todos los recipientes contaminados del componente antes de reconectarlo. La secuencia exacta dentro del juego todavía debe verificarse porque las acciones disponibles dependen del tipo de recipiente.

<!-- TODO: Verificar el procedimiento más seguro dentro del juego para vaciar todos los recipientes compatibles tras una mezcla accidental. -->
