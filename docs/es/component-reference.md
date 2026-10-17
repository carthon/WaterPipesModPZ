# Catálogo de tuberías y componentes de Water Pipes

Aquí tienes todo lo que se construye desde el [menú de Construcción](glossary.md#menu-de-construccion) → **Fontanería** en Water Pipes v0.11.x. Primero las tuberías y después los [componentes](glossary.md#componente), que son todo lo demás que construye el mod. En todas las recetas que la piden, la Llave para tubos no se gasta.

Los nombres de habilidades y objetos son los que muestra el juego en español. Al lado de cada pieza aparece su nombre en inglés, útil si juegas con el juego en inglés o buscas ayuda en foros.

## Tuberías

| Nombre en el juego | En inglés | Materiales y habilidad | Dónde va y para qué sirve |
|---|---|---|---|
| **Tubería de fluidos** | Fluid Pipe | 1 Tubo metálico o 1 Segmento de tubería de arcilla (cocido); sin habilidad | En el suelo; se une sola con las vecinas formando extremos, rectas, esquinas, uniones en T y cruces |
| **Tubería vertical de fluidos** | Vertical Fluid Pipe | 1 Tubo metálico o 1 Segmento de tubería de arcilla (cocido); sin habilidad | En una pared norte u oeste; une las tuberías de dos plantas |
| **Tubería de fluidos oculta** | Concealed Fluid Pipe | 1 tubo o segmento y 1 cubo lleno de cemento de arcilla o de hormigón; sin habilidad | En el suelo, pero invisible al terminarla; se ve con **Mostrar red de tuberías** |
| **Tubería vertical de fluidos oculta** | Concealed Vertical Fluid Pipe | Igual que la oculta de suelo; sin habilidad | Tubería vertical invisible en una pared norte u oeste |

Cada tubería oculta gasta un cubo entero; los cubos válidos están en [Redes de tuberías](pipe-networks.md#recetas-de-tuberias). Al desmontar una tubería metálica construida por ti hay un 90 % de probabilidades de recuperar el Tubo metálico. Las de arcilla, y las tuberías ocultas que aparecen al revisar un edificio con **Conectar la fontanería del edificio**, no devuelven nada.

<!-- SCREENSHOT: 03-pipe-shapes.png — Formas de la Tubería de fluidos y un ejemplo visible y otro oculto. -->
<!-- SCREENSHOT: 04-vertical-pipe-floors.png — Tubería vertical de fluidos uniendo dos plantas. -->

## Suministro y presión

### Bomba de agua — Water Pump

- **Para qué sirve:** suma presión a toda su red. Junto a un pozo, un río o un lago, además saca agua de ellos.
- **Receta:** Electrónica 3 y Metalistería 2; 2 usos de Soplete, 1 uso de Varillas para soldar, 2 Tubos metálicos, 4 Chapas metálicas, 2 Chatarras electrónicas y 1 Alambre.
- **Colocación:** va sobre una tubería de suelo y solo conecta en una dirección (norte–sur o este–oeste); gírala antes de construirla.
- **Valores por defecto:** +25 m de presión; [aspira](glossary.md#aspiracion) hasta 7 m por debajo; saca 20 L/min de un pozo, río o lago.
- **Más información:** [Bombas y presión](pumps-and-pressure.md).

<!-- SCREENSHOT: 08-pump-source-placement.png — Bomba de agua bien colocada junto a una fuente. -->

### Manómetro — Pressure Gauge

- **Para qué sirve:** indica la presión que hay en su casilla y si es suficiente para un aspersor.
- **Receta:** 1 Tubo metálico y 1 Chatarra electrónica; sin habilidad.
- **Colocación:** sobre una tubería ya construida que no tenga válvula ni otro componente incompatible.
- **Más información:** [Bombas y presión](pumps-and-pressure.md#diagnostico).

## Dirección y corte

### Enrutador de fluidos — Fluid Router

- **Para qué sirve:** deja pasar el agua en un solo sentido, de la franja verde (entrada) a la roja (salida), y si quieres limita la presión que sale. Funciona como una válvula antirretorno con reductor de presión; no tiene nada que ver con un router de internet.
- **Receta:** 2 Tubos metálicos y 1 Chapa metálica; sin habilidad.
- **Colocación:** sustituye a una tubería de suelo; gíralo antes de construirlo. Si pones un depósito o un purificador en su casilla, el agua pasa de un lado a otro a través de ese objeto.
- **Caudal por defecto:** hasta 30 L/min si no tiene nada encima.
- **Más información:** [Enrutadores y válvulas](routers-and-valves.md#enrutador-de-fluidos).

<!-- SCREENSHOT: 10-router-orientation.png — Enrutador con la entrada verde y la salida roja. -->

### Válvula de corte — Shut-off Valve

- **Para qué sirve:** abierta no cambia nada; cerrada divide la red en dos y no deja pasar ni líquido, ni presión, ni contaminación en ningún sentido. Se gira a mano, o sola si está vinculada a un Sensor de humedad.
- **Receta:** 1 Tubo metálico y 1 Barra de hierro - Media; sin habilidad.
- **Colocación:** sobre una tubería de suelo normal ya construida. No puede compartir casilla con un enrutador, una bomba, un gotero, un aspersor ni un manómetro.
- **Más información:** [Enrutadores y válvulas](routers-and-valves.md#valvula-de-corte).

<!-- SCREENSHOT: 12-valve-open-closed.png — Válvula de corte abierta y cerrada. -->

## Tratamiento del agua

### Purificador de agua (eléctrico) — Water Purifier (Electric)

- **Para qué sirve:** convierte el agua contaminada que le entra en agua limpia.
- **Habilidades:** Electrónica 4 y Metalistería 3.
- **Receta:** 3 usos de Soplete, 2 usos de Varillas para soldar, 3 Tubos metálicos, 2 Chapas metálicas, 1 Chatarra electrónica, 1 Alambre, 1 Mechero - Batería improvisada, 1 Carbón vegetal y 2 Retales de tela.
- **Colocación:** ocupa 2×2 casillas; su esquina superior (la del fondo) va sobre un Enrutador de fluidos bien orientado. Deja libre el suelo de la planta de arriba sobre esa esquina; el motor del juego exige además las cuatro casillas despejadas. Consulta las [condiciones para colocarlo](purification.md#condiciones-para-colocarlo).
- **Funcionamiento:** con corriente, filtra hasta 10 L/min; tiene un depósito interno de entrada y otro de salida de 50 L cada uno. Cuando el filtro se gasta, se repara con 1 Carbón vegetal y 2 Retales de tela.
- **Más información:** [Purificación](purification.md).

<!-- SCREENSHOT: 13-purifier-placement.png — Vista previa del purificador colocado sobre un Enrutador de fluidos. -->

## Riego

### Gotero — Drip Emitter

- **Para qué sirve:** riega la planta viva de su propia casilla y deja pasar el agua hacia las siguientes tuberías.
- **Receta:** Agricultura 1 y 1 Tubo metálico.
- **Presión:** no necesita un mínimo, pero por defecto revienta por encima de 15 m. Un gotero reventado sigue dejando pasar el agua, pero ya no riega.
- **Reparación:** Llave para tubos y 1 Cinta americana.
- **Más información:** [Riego](irrigation.md).

### Aspersor — Sprinkler

- **Para qué sirve:** riega un cuadrado de 3×3 casillas y puede mojar a los personajes que estén dentro.
- **Receta:** Agricultura 2, 1 Tubo metálico y 1 Chapa metálica.
- **Presión:** por defecto necesita 20 m. Gasta agua por las nueve casillas, haya cultivos o no, y su ruido puede atraer zombis.
- **Más información:** [Riego](irrigation.md).

<!-- SCREENSHOT: 17-sprinkler-coverage.png — Aspersor regando toda su zona de 3×3. -->

### Sensor de humedad — Soil Moisture Sensor

- **Para qué sirve:** mide la humedad del cultivo de su casilla y abre las Válvulas de corte vinculadas cuando el cultivo se seca hasta un mínimo; las vuelve a cerrar al llegar a un máximo (80 % y 95 % por defecto).
- **Receta:** Electrónica 3, Destornillador (no se gasta), 1 Sensor de movimiento, 1 Receptor, 1 Cable Eléctrico y 2 Chatarra electrónica.
- **Colocación:** en tierra cultivable o en una casilla con surco o cultivo, uno por casilla; gíralo con **R** para elegir su esquina. Comparte casilla con cualquier otra pieza.
- **Energía:** la electricidad de la casilla o una Pila (30 días por defecto).
- **Más información:** [Sensor de humedad](irrigation.md#sensor-de-humedad).

## Receta relacionada

**Forjar un Tubo metálico** (en inglés, *Forge an Iron Pipe*) se hace en una Forja Primitiva y produce un Tubo metálico. Gasta 1 Carbón vegetal, 1 Barra de hierro - Media y 1 Barra de hierro - Cuarto, y necesita un martillo, unas tenazas o unos alicates de metalurgia y un punzón para metal, que no se gastan. Requiere Herrería 0 y da 10 XP de Herrería.
