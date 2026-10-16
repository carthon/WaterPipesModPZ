# Preguntas frecuentes

Aquí también se responden dudas que han planteado los jugadores en los [comentarios y debates de Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3739595559). Si no conoces algún término, consulta el [glosario](glossary.md).

## Instalación y requisitos

### ¿Con qué versión del juego funciona?

Water Pipes v0.11.x necesita **Project Zomboid Build 42.15 o posterior**. Consulta [Compatibilidad](compatibility.md).

### ¿Water Pipes necesita otros mods?

No, no depende de ningún otro mod. En multijugador, instálalo en el servidor y en todos los jugadores.

### ¿Puedo añadirlo a una partida que ya tengo empezada?

No hace falta empezar un mundo nuevo, pero añadirlo a una partida avanzada no se ha probado de forma automática. Haz antes una copia de seguridad y prueba primero con una red pequeña, antes de confiarle tus reservas de agua importantes.

### ¿Puedo quitarlo sin problemas?

Haz antes una copia de seguridad. En Build 42, quitar un mod que añade objetos construibles puede provocar un error de carga `WorldDictionary`. Desmonta los objetos de Water Pipes que puedas y sigue los pasos de [Retirar el mod](compatibility.md#retirar-el-mod).

### ¿Se gastan las herramientas?

La Llave para tubos hace falta para muchas acciones, pero no se gasta. Lo que se gasta depende de cada [receta](glossary.md#receta).

## Construcción y conexiones

### ¿Por qué no se conecta un barril o un fregadero que está al lado de la tubería?

La tubería tiene que estar en la **propia casilla** del objeto; al lado no basta. Para cambiar de planta, añade una Tubería vertical de fluidos.

### ¿Cómo conecto un barril a la red?

Construye una Tubería de fluidos en la **misma casilla**. Los depósitos se unen a la red solos; no hace falta ninguna acción más. En el juego sin mods, el barril que guarda agua es el Barril recolector de lluvia; los barriles del mapa solo sirven con el mod [Useful Barrels](glossary.md#barril), y hay que abrirlos antes desenroscando el tapón con una Llave para tubos.

### ¿Cómo veo las tuberías ocultas?

Haz clic derecho en cualquier tubería y elige **Mostrar red de tuberías**. La red se queda resaltada unos segundos.

## Almacenamiento y líquidos

### ¿Una bomba guarda agua?

No. Conecta al menos un depósito: las fuentes dan agua, pero no sustituyen a un sitio donde guardarla.

### ¿Puede una misma red llevar agua y gasolina?

El agua y la gasolina nunca se mezclan: el mod rechaza el trasvase. Aun así, mantenlas en redes separadas, porque los aparatos y los generadores necesitan cada uno su líquido. El agua limpia sí se puede juntar con la contaminada, pero el resultado queda contaminado.

## Bombas y presión

### ¿Por qué llega agua a un aparato y a otro no?

La altura, la distancia, el consumo de otros puntos de la línea y la presión disponible cambian a lo largo del recorrido. Usa **Ver estado de la bomba**, un manómetro y la página [Bombas y presión](pumps-and-pressure.md).

## Purificación

### ¿Los fregaderos limpian el agua contaminada?

Con la purificación realista, que viene activada por defecto, no. Usa un **Purificador de agua (eléctrico)**.

### ¿Por qué se ha parado el purificador?

Necesita corriente, agua contaminada en la entrada, sitio en la salida y un filtro en buen estado. Abre su ventana con **Abrir purificador** para ver qué le falta.

### ¿Cómo coloco el purificador sobre el enrutador?

El purificador ocupa 2 × 2 casillas. Su esquina superior (la del fondo) tiene que quedar justo encima de la casilla del Enrutador de fluidos, sin suelo en la planta de encima de esa casilla. El lado verde del enrutador es la entrada y el rojo, la salida; el purificador no se gira, así que orienta antes el enrutador. Las cuatro casillas tienen que pasar además las comprobaciones que el motor del juego hace a cualquier construcción: suelo firme, nada sólido encima, nadie de pie y ningún muro entre ellas. Consulta las [condiciones para colocarlo](purification.md#condiciones-para-colocarlo).

### El purificador funciona, pero no llega agua a los aparatos. ¿Por qué?

El purificador tiene un depósito interno de 50 L para el agua limpia, así que no es obligatorio añadir otro. Un ánfora o un barril recolector de lluvia después del purificador te da más capacidad. Si los aparatos siguen sin recibir agua, revisa ese depósito de salida, la presión disponible y la conexión del lado rojo.

### ¿Cómo se usa una boca de incendios?

Construye una Tubería de fluidos en su misma casilla, equípate una Llave para tubos y elige **Abrir boca de incendios**. Mientras la ciudad tenga agua, da agua municipal; después del corte, da la reserva que se haya configurado. Consulta [Fuentes y almacenamiento](sources-and-storage.md).

## Riego

### ¿Por qué se ha roto mi gotero?

Por defecto, revienta si la presión pasa de 15 m. Pon antes de él un Enrutador de fluidos con el límite de presión adecuado.

### ¿Por qué no riega el aspersor?

Por defecto necesita 20 m de presión, agua en la red y una planta viva que necesite riego. Usa **Comprobar emisor de riego**.

### ¿Cómo riego los cultivos de forma automática?

Pon una Válvula de corte en la tubería que alimenta los goteros o aspersores, clava un Sensor de humedad entre los cultivos y vincula la válvula desde la ventana del sensor. La válvula se abre cuando el cultivo se seca hasta el mínimo y se cierra al llegar al máximo. Consulta [Sensor de humedad](irrigation.md#sensor-de-humedad).

## Combustible y generadores

### ¿Cuándo se rellena un generador instalado?

Una vez por minuto de juego, si está por debajo del umbral configurado (25 % por defecto), hasta llegar al objetivo (100 % por defecto), y siempre desde una red que solo tenga gasolina.

### ¿Por qué el generador no recibe gasolina aunque tenga una tubería debajo?

Además de poner la tubería en su casilla, equípate una Llave para tubos y elige **Instalar Generador**. La red tiene que tener solo gasolina y presión suficiente para la altura y la distancia. Sigue el [ejemplo completo](practical-examples.md#abastecer-un-generador-con-gasolina).

### ¿Cómo se usa una Válvula de corte?

Constrúyela sobre una tubería de suelo normal. Haz clic derecho: **Cerrar válvula** separa los dos lados en redes independientes y **Abrir válvula** los vuelve a unir; se gira a mano, sin herramientas. Si la vinculas a un [Sensor de humedad](irrigation.md#sensor-de-humedad), se abre y se cierra sola. Nunca la abras si a un lado hay gasolina y al otro agua. Consulta el [ejemplo de control](practical-examples.md#separar-y-controlar-ramales).

### ¿Qué hace realmente «Conectar la fontanería del edificio»?

En un edificio que ya venía en el mapa, revisa y saca a la luz la fontanería que se considera que ya tenía. El mod solo crea esas tuberías ocultas cuando se lo pides, para no tener que crearlas en todos los edificios del mapa. **No** pone tuberías en edificios construidos por jugadores; en esos se ponen a mano. Consulta el [paso a paso completo](practical-examples.md#inspeccionar-la-fontaneria-de-una-casa-del-mapa).

## Movimiento y colisiones

### ¿Las tuberías del suelo bloquean el paso a personajes o vehículos?

No. Las tuberías no bloquean el movimiento.

## Compatibilidad y multijugador

### ¿Funciona en multijugador?

Sí. Las acciones que cambian algo importante las comprueba el servidor antes de aplicarlas.

### ¿Con qué mods está comprobado que funciona?

Con los aparatos de Take A Bath And Shower, los barriles de Useful Barrels y, con el complemento opcional que viene en el mismo objeto de Workshop, Project Viewpoint. Consulta [Compatibilidad](compatibility.md).
