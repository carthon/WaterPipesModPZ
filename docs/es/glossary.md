# Glosario

Esta página explica los términos que usa la guía. Está pensada para quien nunca ha jugado a Project Zomboid o no tiene experiencia con mods. Las palabras **en negrita** dentro de una definición tienen su propia entrada.

## El juego

### Project Zomboid { #project-zomboid }
Videojuego de supervivencia en un mundo invadido por zombis. El jugador busca comida, agua y materiales, y construye y mantiene su propia base. A las pocas semanas de empezar la partida se cortan el agua y la luz de la ciudad (ver **corte de suministros**), y desde entonces el agua pasa a ser un problema serio.

### Build 42 { #build-42 }
La versión del juego que necesita este mod. «Build» es el nombre que usan los desarrolladores para cada versión principal; Water Pipes funciona en la 42.15 o posteriores.

### Mod { #mod }
Una ampliación hecha por la comunidad que añade cosas al juego. Water Pipes es un mod: hay que activarlo antes de empezar o cargar la partida.

### Partida y opciones de sandbox { #opciones-de-sandbox }
Al crear una partida personalizada (en el juego, «Mundo abierto») puedes cambiar muchas reglas de la simulación. Esas reglas son las **opciones de sandbox** y se guardan con la partida. Las de este mod están en el grupo **Water Pipes**. Consulta [Opciones de sandbox](sandbox-settings.md).

### Casilla { #casilla }
El mapa del juego está dividido en cuadrados del mismo tamaño, como un tablero. Cada cuadrado es una casilla. En una casilla cabe una tubería de suelo, y la mayoría de objetos ocupan una sola casilla.

### Planta { #planta }
Cada piso de un edificio. La planta baja está al nivel del suelo, y cada planta añade unos 3 metros de altura. Esa altura es la que da presión al agua (ver **presión**).

### Clic derecho y menú contextual { #clic-derecho }
Casi todas las acciones del juego se hacen con clic derecho sobre un objeto: aparece una lista de opciones (el menú contextual) y eliges una. En esta guía, los nombres de esas opciones aparecen **en negrita**, tal como los muestra el juego.

### Receta { #receta }
Lo que hace falta para construir algo: materiales, herramientas y, a veces, un nivel mínimo de **habilidad**. Los materiales se gastan. Algunas herramientas, como la Llave para tubos, solo hay que llevarlas encima; otras, como el Soplete, gastan parte de su carga.

### Habilidad y XP { #habilidad }
El personaje mejora en cada oficio (Electrónica, Metalistería, Agricultura, Herrería…) a medida que lo practica. La experiencia que gana se mide en XP, y al acumular suficiente sube de nivel. Algunas recetas exigen un nivel mínimo.

### Menú de Construcción { #menu-de-construccion }
La ventana del juego donde se eligen las cosas que se pueden construir. Todo lo que añade Water Pipes está en la categoría **Fontanería**.

### Corte de suministros { #corte-de-suministros }
Al empezar la partida la ciudad todavía tiene agua corriente y electricidad. Pasado un tiempo (configurable en las opciones de sandbox) se cortan para siempre. A partir de ese día, el agua que no hayas almacenado o sacado de un pozo o un río ya no llega.

### Agua contaminada { #agua-contaminada }
Agua que hace enfermar si se bebe sin tratar: la de ríos y lagos, el agua de lluvia en recipientes destapados o el agua que lleva demasiado tiempo quieta. Si se mezcla con agua limpia, todo pasa a estar contaminado. En este mod, solo el **purificador** la vuelve potable (salvo que desactives la purificación realista).

### Generador { #generador }
Máquina de gasolina que da electricidad cuando ya no hay luz en la ciudad. Water Pipes puede rellenar su depósito de combustible a través de las tuberías.

### Steam Workshop { #steam-workshop }
La sección de Steam donde se publican y descargan los mods. Water Pipes tiene allí la página con ID 3739595559.

### Multijugador, servidor y cliente { #multijugador }
En una partida multijugador, el **servidor** es el ordenador que guarda el mundo y decide qué pasa en él; cada jugador conectado es un **cliente**. Por eso algunas acciones tardan un instante: el servidor tiene que comprobarlas antes de aplicarlas.

## El mod

### Red { #red }
Conjunto de tuberías y de todo lo que está conectado a ellas sin que nada lo corte: depósitos, componentes, aparatos y generadores. Todo lo que forma parte de una misma red comparte el agua, como si fuera un único depósito grande. Una **válvula de corte** cerrada, un **enrutador** o simplemente una casilla sin tubería dividen la red en dos.

### Tubería { #tuberia }
La pieza básica del mod. Se construye en el suelo de una casilla y se une sola con las tuberías vecinas, formando rectas, esquinas y cruces. No es un componente: los componentes se colocan sobre las tuberías o al lado de ellas.

### Tubería vertical { #tuberia-vertical }
Tubería que sube o baja por una pared (norte u oeste) para unir las tuberías de dos plantas.

### Tubería oculta { #tuberia-oculta }
Tubería que funciona igual que una normal, pero queda invisible una vez construida, como si estuviera empotrada en el suelo o la pared. Se ve con **Mostrar red de tuberías**.

### Componente { #componente }
Cualquier cosa que construye el mod excepto las tuberías: bomba de agua, manómetro, enrutador de fluidos, válvula de corte, purificador, gotero, aspersor y sensor de humedad. Consulta el [catálogo](component-reference.md).

### Aparato { #aparato }
Un objeto del mundo que usa agua: fregadero, lavabo, ducha, bañera, inodoro o lavadora. Los aparatos no los construye el mod; ya existen en las casas o los construyes con el juego. El mod los conecta a una red con la acción **Instalar**.

### Instalar y Desinstalar { #instalar }
Acción del juego (no del mod) que conecta un aparato o un generador a la tubería que tiene debajo. En el menú aparece como **Instalar** seguido del nombre del objeto, por ejemplo «Instalar Generador». **Desinstalar** lo desconecta sin quitar la tubería. Hace falta llevar una Llave para tubos.

### Depósito { #deposito }
Cualquier objeto que guarda líquido dentro de una red. En el juego sin mods son el Barril recolector de lluvia, la Caja recolectora de lluvia y el Ánfora; otros mods pueden añadir más, como los [barriles de Useful Barrels](#barril). Un depósito se une a la red en cuanto hay una tubería en su propia casilla.

### Barril (Useful Barrels) { #barril }
En el juego sin mods, los barriles que se encuentran por el mapa (Barril verde claro, Barril verde oscuro, Barril naranja y Bidón de metal) son decoración: no guardan líquido. **Useful Barrels**, un mod aparte, los convierte en depósitos: se abren desenroscando el tapón con una Llave para tubos (o cortándoles la tapa con un Soplete), y desde ese momento Water Pipes los conecta como cualquier otro depósito. En los ejemplos de este manual, «barril» vale por cualquier depósito; si juegas sin Useful Barrels, usa un Barril recolector de lluvia.

### Fuente { #fuente }
De donde sale el agua que entra en la red: un depósito con agua, un pozo o un río (a través de una bomba), la red municipal o una boca de incendios.

### Red municipal { #red-municipal }
El agua corriente de la ciudad. Mientras no llegue el corte de suministros, un aparato instalado dentro de una casa puede meter esa agua en tu red, con presión y gratis.

### Boca de incendios { #boca-de-incendios }
El hidrante rojo de la calle. Con una tubería en su casilla y abierto con una Llave para tubos, alimenta tu red con mucha presión; después del corte aún da una reserva limitada.

### Mostrar red de tuberías { #mostrar-red }
Opción del clic derecho sobre cualquier tubería. Durante unos segundos colorea toda la red: las tuberías en rojo, los depósitos y fuentes en verde, los aparatos en azul y los enrutadores con límite de presión en ámbar. Es la mejor forma de comprobar qué está conectado y qué no.

### Presión (metros de columna de agua) { #presion }
La fuerza con la que llega el agua. El mod la mide en metros (m), como en la fontanería real: 1 m es la presión que haría una columna de agua de 1 metro de alto. Por eso subir un depósito una planta (unos 3 m) da 3 m más de presión. Si la presión no llega a cero, el agua no sale; si es demasiado alta, algunos componentes (los goteros) revientan.

### Aguas arriba y aguas abajo { #aguas-arriba }
Expresiones de fontanería que indican la posición siguiendo el sentido del agua. «Aguas arriba» es antes, más cerca de la fuente; «aguas abajo» es después, hacia donde va el agua.

### Demanda compartida { #demanda-compartida }
Cuando varios consumidores sacan agua por el mismo tramo de tubería, ese tramo pierde más presión. Por eso los aspersores del final de una línea larga pueden quedarse sin presión aunque los primeros funcionen bien.

### Bomba de agua { #bomba }
Componente eléctrico que suma presión a toda su red. Si se coloca junto a un pozo, un río o un lago, además saca agua de ellos. No guarda agua: hace falta al menos un depósito en la red.

### Aspiración { #aspiracion }
La profundidad máxima desde la que una bomba puede sacar agua: por defecto, 7 m (unas dos plantas) por debajo de ella.

### Enrutador de fluidos { #enrutador }
Componente que deja pasar el agua en un solo sentido, de su lado verde (entrada) a su lado rojo (salida), y que además puede limitar la presión que sale. No tiene nada que ver con el router de internet: en fontanería real sería una válvula antirretorno con reductor de presión.

### Válvula de corte { #valvula-de-corte }
Componente que, al cerrarse, divide la red en dos partes independientes. Abierta, no cambia nada. Se gira a mano, o sola si está vinculada a un [sensor de humedad](#sensor-de-humedad).

### Manómetro { #manometro }
Componente que muestra la presión que hay en su casilla.

### Purificador de agua { #purificador }
Componente eléctrico que convierte agua contaminada en agua limpia. Se coloca sobre un enrutador y su filtro se desgasta con el uso.

### Gotero y aspersor { #gotero }
Componentes de riego. El gotero riega la planta de su propia casilla con poca presión. El aspersor riega un cuadrado de 3×3 casillas, pero necesita bastante presión.

### Sensor de humedad { #sensor-de-humedad }
Componente que se clava en la tierra junto a un cultivo. Mide el agua que tiene el cultivo y abre o cierra las válvulas vinculadas, así el riego empieza y para solo. Consulta [Riego](irrigation.md#sensor-de-humedad).

### Unidad { #unidad }
Algunas ventanas del mod (purificador, enrutador) indican cantidades en «u» o «unidades». Una unidad equivale a un litro.

### Conectar la fontanería del edificio { #conectar-la-fontaneria }
Nombre de la acción del mod que revela la fontanería escondida de un edificio del mapa (no de uno construido por ti). Consulta [Inspeccionar la fontanería de un edificio](building-plumbing.md).
