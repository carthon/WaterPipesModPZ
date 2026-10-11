# Catálogo de componentes de Water Pipes

Este catálogo reúne todos los componentes disponibles en **Menú de construcción → Fontanería** en Water Pipes v0.10.0. La Llave para tubos utilizable se conserva en todas las recetas que la requieren.

## Tuberías

| Entrada de construcción | Nombre inglés | Materiales y habilidades | Colocación y función |
|---|---|---|---|
| **Tubería de fluidos** | Fluid Pipe | 1 Tubería de metal o Segmento de tubería de arcilla cocida; sin habilidad | Tubería de suelo; forma automáticamente extremos, rectas, esquinas, T y cruces |
| **Tubería vertical de fluidos** | Vertical Fluid Pipe | 1 Tubería de metal o Segmento de arcilla; sin habilidad | Pared norte u oeste; conecta tuberías entre plantas |
| **Tubería de fluidos oculta** | Concealed Fluid Pipe | 1 tubería y 1 cubo compatible completo de cemento de arcilla u hormigón preparado; sin habilidad | Tubería de suelo invisible; revélala con **Mostrar red de tuberías** |
| **Tubería vertical de fluidos oculta** | Concealed Vertical Fluid Pipe | Igual que la oculta de suelo; sin habilidad | Montante oculto norte/oeste entre plantas |

Cada tubería oculta consume un cubo preparado completo; consulta las variantes admitidas en [Redes de tuberías](pipe-networks.md#recetas-de-tuberias). Las tuberías metálicas manuales tienen un 90 % de recuperación; las de arcilla y las generadas automáticamente no devuelven tubería.

<!-- SCREENSHOT: 03-pipe-shapes.png — Formas de la Tubería de fluidos y ejemplos visible/oculto. -->
<!-- SCREENSHOT: 04-vertical-pipe-floors.png — Tubería vertical de fluidos uniendo dos plantas. -->

## Suministro y presión

### Bomba de agua — Water Pump

- **Función:** aumenta la presión; junto a un pozo o agua abierta también abastece la red.
- **Receta:** Electricidad 3, Soldadura 2; 2 usos de Soplete, 1 uso de Varilla, 2 Tuberías de metal, 4 Chapas metálicas, 2 Restos electrónicos y 1 Cable.
- **Colocación:** ocupa una casilla de tubería y tiene eje fijo; gírala antes de construir.
- **Valores predeterminados:** +25 m, aspiración máxima de 7 m y entrada natural de 20 L/min.
- **Detalles:** [Bombas y presión](pumps-and-pressure.md).

<!-- SCREENSHOT: 08-pump-source-placement.png — Bomba colocada correctamente junto a una fuente. -->

### Manómetro — Pressure Gauge

- **Función:** lee la presión local e indica si hay presión suficiente para un aspersor.
- **Receta:** 1 Tubería de metal y 1 Resto electrónico; sin habilidad.
- **Colocación:** sobre una tubería existente sin válvula ni dispositivo incompatible.
- **Detalles:** [Bombas y presión](pumps-and-pressure.md#diagnostico).

## Dirección y aislamiento

### Enrutador de fluidos — Fluid Router

- **Función:** frontera unidireccional desde la entrada verde hacia la salida roja, con límite opcional de presión.
- **Receta:** 2 Tuberías de metal y 1 Chapa metálica; sin habilidad.
- **Colocación:** sustituye una tubería de suelo; gíralo antes de construir. Un recipiente o purificador en su casilla intercambia fluido a través de la frontera.
- **Transferencia predeterminada:** hasta 30 unidades/min si está vacío.
- **Detalles:** [Enrutadores y válvulas](routers-and-valves.md#enrutador-de-fluidos).

<!-- SCREENSHOT: 10-router-orientation.png — Enrutador mostrando entrada verde y salida roja. -->

### Válvula de corte — Shut-off Valve

- **Función:** abierta mantiene una red; cerrada separa líquido, presión y contaminación en ambos sentidos.
- **Receta:** 1 Tubería de metal y media barra de hierro; sin habilidad.
- **Colocación:** sobre una tubería de suelo normal. No comparte casilla con enrutador, bomba, emisores, aspersor o manómetro.
- **Detalles:** [Enrutadores y válvulas](routers-and-valves.md#valvula-de-corte).

<!-- SCREENSHOT: 12-valve-open-closed.png — Válvula de corte abierta y cerrada. -->

## Tratamiento

### Purificador de agua (eléctrico) — Water Purifier (Electric)

- **Función:** convierte agua contaminada de entrada en agua limpia de salida.
- **Habilidades:** Electricidad 4 y Soldadura 3.
- **Receta:** 3 usos de Soplete, 2 de Varilla, 3 Tuberías, 2 Chapas, 1 Resto electrónico, 1 Cable, 1 Batería de encendedor, 1 carbón y 2 Trozos de tela.
- **Colocación:** ocupa 2×2; su anclaje superior/trasero se sitúa sobre un Enrutador correctamente orientado. Deja libre el suelo sobre el anclaje.
- **Funcionamiento:** filtra con corriente hasta 10 unidades/min; búferes IN y OUT de 50. Repara el filtro con 1 carbón y 2 Trozos de tela.
- **Detalles:** [Purificación de agua](purification.md).

<!-- SCREENSHOT: 13-purifier-placement.png — Fantasma del purificador anclado sobre el Enrutador. -->

## Riego

### Gotero — Drip Emitter

- **Función:** riega el cultivo vivo de su casilla y continúa el trazado.
- **Receta:** Agricultura 1 y 1 Tubería de metal.
- **Presión:** sin mínimo; revienta por encima de 15 m por defecto. Reventado sigue conduciendo, pero no riega.
- **Reparación:** Llave para tubos y 1 Cinta americana.
- **Detalles:** [Riego automático](irrigation.md).

### Aspersor — Sprinkler

- **Función:** riega todo el 3×3 y puede mojar personajes próximos.
- **Receta:** Agricultura 2, 1 Tubería de metal y 1 Chapa metálica.
- **Presión:** necesita 20 m por defecto; cobra agua por las nueve casillas y puede atraer zombis.
- **Detalles:** [Riego automático](irrigation.md).

<!-- SCREENSHOT: 17-sprinkler-coverage.png — Aspersor funcionando sobre toda su zona 3×3. -->

## Receta relacionada

**Forjar una tubería de metal — Forge a Metal Pipe** se realiza en una forja primitiva. Consume un carbón, media barra y un cuarto de barra de hierro; conserva martillo, tenazas o alicates y punzón compatibles. Requiere Herrería 0 y concede 10 XP de Herrería.
