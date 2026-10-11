# Preguntas frecuentes

Esta sección también recoge dudas planteadas por jugadores en los [comentarios y discusiones de Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3739595559).

## Instalación y requisitos

### ¿Qué versión del juego es compatible?

Water Pipes v0.10.0 requiere **Project Zomboid Build 42.15 o posterior**. Consulta [Compatibilidad](compatibility.md).

### ¿Water Pipes tiene dependencias?

No declara dependencias de otros mods. Instala Water Pipes en el servidor y en todos los clientes multijugador.

### ¿Puedo añadirlo a una partida existente?

El mod no exige un mundo nuevo, pero este caso no está cubierto por una prueba automatizada dentro del juego. Haz una copia, prueba primero una red pequeña y después compromete recursos importantes.

### ¿Puedo retirarlo sin problemas?

Haz primero una copia. Retirar mods de Build 42 con objetos construibles registrados puede provocar un error `WorldDictionary`. Desmonta los objetos cuando sea posible y sigue [Retirar el mod](compatibility.md#retirar-el-mod).

### ¿Se gastan las herramientas?

La llave para tubos se necesita para muchas acciones, pero no se consume. Las piezas y consumibles dependen de cada receta.

## Construcción y conexiones

### ¿Por qué no se conecta un barril o fregadero cercano?

La tubería debe estar en la **propia casilla** del objeto; al lado no basta. Entre plantas, añade una Tubería vertical de fluidos.

### ¿Cómo conecto un barril a la red?

Si tiene tapón o tapa, destápalo primero con una Llave para tubos. Después construye una Tubería de fluidos en la **misma casilla**. Los recipientes se incorporan automáticamente: no necesitan una acción adicional de instalación.

### ¿Cómo puedo ver tuberías ocultas?

Haz clic derecho en una tubería y elige **Mostrar red de tuberías**. La superposición permanece unos segundos.

## Almacenamiento y líquidos

### ¿Una bomba almacena agua?

No. Conecta al menos un recipiente; las fuentes aportan líquido, pero no sustituyen al almacenamiento.

### ¿Puede una red llevar agua y gasolina?

Puede mezclarse físicamente, pero el suministro normal se detiene. Separa líquidos mediante un hueco, una válvula cerrada o un enrutador.

## Bombas y presión

### ¿Por qué llega agua a un aparato y a otro no?

La altura, distancia, demanda compartida y presión disponible varían por el recorrido. Usa **Ver estado de la bomba**, un manómetro y [Bombas y presión](pumps-and-pressure.md).

## Purificación

### ¿Los fregaderos limpian agua contaminada?

Con la purificación realista, activada por defecto, no. Usa un **Purificador de agua (eléctrico)**.

### ¿Por qué se ha parado el purificador?

Necesita corriente, agua contaminada en la entrada, espacio de salida y un filtro utilizable. Abre su ventana de estado.

### ¿Cómo se coloca el purificador sobre el enrutador?

El purificador ocupa 2 × 2 casillas. Su esquina superior/trasera debe quedar directamente sobre la casilla del Enrutador de fluidos. El lado verde del enrutador es la entrada y el rojo es la salida.

### ¿Por qué el purificador funciona pero no llega agua a los aparatos?

El purificador tiene un búfer interno de 50 unidades de agua limpia, por lo que no es obligatorio añadir otro recipiente. Un ánfora, barril o tanque posterior aporta capacidad adicional. Si los aparatos siguen sin recibir agua, revisa el búfer de salida, la presión disponible y la conexión del lado rojo.

### ¿Cómo se utiliza una boca de incendios?

Construye una Tubería de fluidos en su propia casilla, equipa una Llave para tubos y ábrela. Utiliza la red municipal antes del corte y después su reserva configurada. Consulta [Fuentes y almacenamiento](sources-and-storage.md).

## Riego

### ¿Por qué se ha roto el gotero?

Por defecto revienta al superar 15 m de presión. Coloca antes un enrutador con un límite adecuado.

### ¿Por qué no funciona el aspersor?

Por defecto necesita 20 m de presión, agua en la red y un cultivo vivo que necesite riego. Usa **Comprobar emisor de riego**.

## Combustible y generadores

### ¿Cuándo reposta un generador instalado?

Una vez por minuto al bajar del umbral configurado (25 % por defecto), hasta el objetivo (100 %), desde una red exclusiva de gasolina.

### ¿Por qué el generador no toma gasolina aunque haya una tubería debajo?

Además de colocar la tubería en su casilla, equipa una Llave para tubos y usa **Instalar Generador**. La red debe contener solo gasolina y disponer de presión suficiente. Sigue el [ejemplo completo](practical-examples.md#abastecer-un-generador-con-gasolina).

### ¿Cómo se utiliza una Válvula de corte?

Constrúyela sobre una tubería de suelo normal. **Cerrar válvula** separa ambos lados y **Abrir válvula** vuelve a unirlos. Nunca la abras entre gasolina y agua. Consulta el [ejemplo de control](practical-examples.md#separar-y-controlar-ramales).

### ¿Cómo se fontanea un edificio entero?

Sitúate dentro con una Llave utilizable y suficientes Tuberías de metal, haz clic derecho en una casilla con suelo y elige **Fontanear el edificio**. Consulta el [procedimiento completo](practical-examples.md#fontanear-automaticamente-una-vivienda).

## Movimiento y colisiones

### ¿Las tuberías colocadas en el suelo bloquean personajes o vehículos?

No. Las tuberías no bloquean el movimiento.

## Compatibilidad y multijugador

### ¿Funciona en multijugador?

Sí. Las acciones que cambian estados importantes son validadas por el servidor.

### ¿Qué integraciones están confirmadas?

Los aparatos de Take A Bath And Shower y los recipientes de Useful Barrels. Consulta [Compatibilidad](compatibility.md).
