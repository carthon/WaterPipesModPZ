# Fuentes y almacenamiento

## Qué se une a una red

Un [depósito](glossary.md#deposito) del mapa se une a la red en cuanto hay una tubería de suelo en su **propia casilla**. Valen los barriles y recolectores de lluvia del juego, las ánforas y los tanques, y también los depósitos de otros mods si el juego los trata como recipientes de líquido normales. Las lavadoras y los demás [aparatos](glossary.md#aparato) no guardan agua para la red: solo la consumen. Los objetos que el juego trata como agua prácticamente inagotable (con capacidad de 9999 L o más, como un grifo conectado a la red municipal) no se reparten como un depósito más: solo aportan agua cuando el mod los reconoce como una fuente concreta.

Cada dos minutos de juego, el agua de la red se reparte entre los depósitos: primero se llenan los de las plantas más bajas, y los que están en la misma planta se igualan según su capacidad. Una bomba no es un depósito; pon siempre algún recipiente donde se pueda quedar el agua que entra.

![Cómo se llenan los depósitos por gravedad](../assets/images/diagram-storage-gravity.svg){ .wp-diagram }

- **1** Depósitos de la planta de abajo: se llenan y se igualan primero.
- **2** Depósito de la planta de arriba: recibe lo que sobra cuando los de abajo están llenos.

| Fuente | Líquido | Caudal o reserva por defecto | Cómo se prepara |
|---|---|---:|---|
| Barril, recolector, ánfora o tanque | Lo que contenga | Su capacidad | Pon una tubería en su casilla. Si tiene tapa, quítasela: algunos solo se conectan destapados |
| Pozo | Agua limpia | Bomba: 20 L/min | Pon una bomba con corriente lo bastante cerca para que [aspire](glossary.md#aspiracion) |
| Río o lago | [Agua contaminada](glossary.md#agua-contaminada) | Bomba: 20 L/min, sin límite | Pon una bomba con corriente en la orilla; la opción de sandbox correspondiente tiene que estar activada |
| [Red municipal](glossary.md#red-municipal) | Agua limpia | 60 L/min a 25 m de presión | [Instala](glossary.md#instalar) un aparato dentro de una casa antes del [corte del agua](glossary.md#corte-de-suministros) |
| [Boca de incendios](glossary.md#boca-de-incendios) | Agua limpia | 60 L/min; después del corte, una reserva de 1000 L | Pon una tubería en su casilla y ábrela con una Llave para tubos |

<div class="wp-gallery wp-gallery--2" markdown>
![Depósitos compatibles](../assets/images/06-source-types-cropped.png){ .wp-screenshot loading=lazy }
![Fuentes para una bomba: un pozo y un río](../assets/images/06b-source-well-river-cropped.png){ .wp-screenshot loading=lazy }
![Aparato conectado a la red municipal y boca de incendios](../assets/images/06c-source-mains-hydrant.png){ .wp-screenshot loading=lazy }
</div>

## Líquidos compatibles y calidad del agua

Los líquidos incompatibles nunca se mezclan. Si un trasvase fuera a juntar gasolina con agua, u otros dos líquidos incompatibles, el mod lo rechaza y ninguno de los dos depósitos se estropea. Aun así, usa redes separadas: los aparatos y los generadores necesitan su líquido concreto.

La excepción son el agua limpia y la contaminada: sí pueden juntarse, pero el resultado queda contaminado. Con la purificación realista activada, solo el **Purificador de agua (eléctrico)** devuelve el agua a su estado limpio.
