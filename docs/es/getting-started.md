# Primeros pasos

Water Pipes es un mod para **Project Zomboid Build 42.15 o posterior**. Sus piezas se construyen desde **Menú de construcción → Fontanería**. Lleva una Llave para tubos utilizable en el inventario: hace falta para la mayoría de construcciones y conexiones, pero no se consume.

## Primera red para una base pequeña

Necesitas una Llave para tubos, una Tubería de metal o un Segmento de tubería de arcilla cocida por cada casilla, un recipiente de agua y un aparato compatible como un fregadero.

1. Coloca un barril, recolector de lluvia, ánfora u otro recipiente donde la red almacenará el agua.
2. Construye una **Tubería de fluidos** en la misma casilla del recipiente.
3. Extiende el trazado hasta el aparato. Las tuberías forman automáticamente rectas, esquinas, uniones y cruces.
4. Construye la última tubería en la misma casilla del aparato; una casilla adyacente no basta.
5. Con la Llave para tubos en el inventario, haz clic derecho en el aparato y elige **Fontanear**.
6. Haz clic derecho en cualquier tubería y elige **Mostrar red de tuberías**. Las tuberías aparecen rojas, las fuentes y depósitos verdes, los consumidores azules y los enrutadores regulados ámbar.
7. Prueba el aparato. Si no da agua, comprueba que el recipiente tiene agua y está en la planta del aparato o más arriba; si no, consulta las instalaciones de abajo.

<!-- SCREENSHOT: 01-getting-started-materials.png — Llave, tuberías y recipiente preparados para la red inicial. -->
<!-- SCREENSHOT: 02-getting-started-small-network.png — Red inicial completa entre recipiente y fregadero, con la superposición visible. -->

## Tres instalaciones de inicio

La altura se cuenta en plantas y la distancia en casillas, pero la presión se da en metros (m), la unidad que usan todos los manómetros y las ventanas de bombas y enrutadores del juego. La regla práctica: **1 planta = 3 m**, así que los 25 m de una bomba equivalen a subir el depósito unas 8 plantas. Las cifras van redondeadas al metro. Con los valores predeterminados, un aparato recibe:

- **Lo que construyen los depósitos.** Cada recipiente con agua aporta 1 m en su propia planta, más 3 m por cada planta que esté por encima del aparato. Los recipientes no se suman: manda el más alto.
- **Más 25 m por cada bomba con corriente** de la red. La bomba eleva todos los recipientes de la red, y las bombas en serie se suman.
- **Con el tope de un enrutador**, si hay uno en medio. Un enrutador puede bajar la presión, nunca subirla.

La distancia solo cuesta presión donde el riego hace pasar agua por la tubería: unos 0,2 m por casilla por cada aspersor aguas abajo y unos 0,02 m por casilla por cada gotero. Fregaderos, duchas, inodoros y demás aparatos no pierden nada por la distancia. Un aparato funciona con cualquier presión por encima de cero; un aspersor necesita 20 m y un gotero revienta por encima de 15 m.

Como referencia: todos los recipientes aportan el mismo 1 m, sea cual sea su tipo, así que un barril o un ánfora en la planta del fregadero lo alimentan a cualquier distancia. Con ese 1 m, un solo gotero llega a unas 45 casillas (1 m ÷ 0,022 m por casilla). Los 20 m de un aspersor exigen unas 7 plantas de altura o una bomba.

### 1. Solo depósitos

![Instalaciones solo con depósitos](../assets/images/diagram-install-storage-es.svg){ .wp-diagram }

- **1** Barril en la misma planta que **2**, un fregadero: 1 m de base = **1 m**. Poco, pero suficiente para un aparato.
- **3** Barril una planta más arriba, con tubería bajando hasta **4**, un fregadero en la planta baja: 1 m + 1 planta × 3 m = **4 m**.

El propio depósito es la fuente de presión: subirlo es la forma más barata de ganarla. Al revés no funciona: un fregadero una planta por encima de su único barril recibe 1 m − 1 planta × 3 m = −2 m y no da agua. Sube el barril o añade una bomba.

### 2. Depósito y bomba de agua

![Depósito con bomba de agua](../assets/images/diagram-install-pump-es.svg){ .wp-diagram }

- **1** Barril en la planta baja: 1 m.
- **2** Bomba de agua con corriente, a 2 casillas del barril: 1 m + 25 m = **26 m** para toda la red.
- **3** Fregadero una planta más arriba, con la subida a 6 casillas del barril: el caudal del aspersor le quita 6 casillas × 0,2 m del tramo compartido y la planta 3 m, así que recibe **22 m**.
- **4** Aspersor a 10 casillas del barril: 26 m − 10 casillas × 0,2 m = **24 m**, por encima de los 20 m que necesita. Sin la bomba recibiría 1 m − 10 casillas × 0,2 m = −1 m y no regaría.

El barril sigue siendo necesario: la bomba empuja y mueve el agua, pero no almacena nada.

### 3. Bomba con una zona de goteo protegida por un enrutador

![Línea con bomba y zona de goteo protegida por un enrutador](../assets/images/diagram-install-router.svg){ .wp-diagram }

- **1–2** Barril y bomba con corriente, como antes: **26 m**.
- **3** Fregadero en la línea principal: **26 m**.
- **4** Enrutador de fluidos, con la banda verde de entrada hacia la bomba y la roja de salida hacia los cultivos, y **Fijar límite de presión** en 12 m. El agua y la presión solo pasan de la entrada a la salida.
- **5** Goteros detrás del enrutador: **12 m**, por debajo de los 15 m que los revientan. Conectados directamente a la línea de la bomba recibirían 26 m y reventarían.

Un enrutador no necesita corriente y nunca añade presión: con la bomba apagada, los goteros reciben el 1 m del barril. Más en [Enrutadores y válvulas](routers-and-valves.md) y [Riego](irrigation.md).

!!! warning
    Una bomba aporta o mueve agua, pero no la almacena. Añade al menos un recipiente y nunca unas gasolina y agua en la misma red.

## Encuentra lo que necesitas

| Quiero… | Consulta… |
|---|---|
| Ver todas las recetas de construcción | [Redes de tuberías](pipe-networks.md), [Bombas y presión](pumps-and-pressure.md), [Enrutadores y válvulas](routers-and-valves.md), [Purificación](purification.md) y [Riego](irrigation.md) |
| Comparar todos los componentes construibles | [Catálogo de componentes](component-reference.md) |
| Seguir instalaciones completas de ejemplo | [Ejemplos prácticos](practical-examples.md) |
| Extraer de un pozo, río, red municipal o hidrante | [Fuentes y almacenamiento](sources-and-storage.md) |
| Conectar un fregadero, ducha, inodoro o lavadora | [Aparatos y fontanería](fixtures-and-plumbing.md) |
| Fontanear automáticamente una casa existente | [Fontanería de edificios](building-plumbing.md) |
| Transportar gasolina y repostar un generador | [Transporte de combustible](fuel-transport.md) |
| Cambiar la dificultad o los valores de simulación | [Opciones de sandbox](sandbox-settings.md) |
| Diagnosticar algo que no funciona | [Resolución de problemas](troubleshooting.md) y [Preguntas frecuentes](faq.md) |

## Siguientes pasos

- Aprende a colocar y desmontar en [Redes de tuberías](pipe-networks.md).
- Añade fuentes naturales y depósitos en [Fuentes y almacenamiento](sources-and-storage.md).
- Resuelve recorridos largos o cuesta arriba en [Bombas y presión](pumps-and-pressure.md).
- Conecta una casa completa en [Fontanería de edificios](building-plumbing.md).
