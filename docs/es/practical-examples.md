# Instalaciones prácticas con Water Pipes

Estos ejemplos de fontanería para Project Zomboid funcionan con la serie v0.11.x. Las recetas completas están en el [catálogo de tuberías y componentes](component-reference.md); si la comprobación final falla, consulta [Resolución de problemas](troubleshooting.md).

## Primera red de agua

**Objetivo:** dar agua a un fregadero desde un recolector de lluvia u otro [depósito](glossary.md#deposito).

**Materiales:** Llave para tubos, un depósito y un Tubo metálico o un Segmento de tubería de arcilla (cocido) por cada casilla de tubería.

1. Coloca el depósito y, si tiene tapa, quítasela.
2. Construye una **Tubería de fluidos** en la casilla del depósito.
3. Sigue con tuberías hasta el fregadero y pon la última en su misma casilla.
4. Con la Llave para tubos en el inventario, haz clic derecho en el fregadero y elige **[Instalar](glossary.md#instalar) Fregadero** (es una acción del propio juego).
5. Elige **Mostrar red de tuberías** y prueba el fregadero.

**Comprobación:** el depósito aparece en verde, el fregadero en azul y toda la tubería en rojo. **Errores habituales:** poner la última tubería al lado del fregadero en vez de debajo, olvidar la tubería vertical al cambiar de planta, o creer que una bomba guarda agua por sí sola. Consulta [Redes de tuberías](pipe-networks.md) y [Aparatos y fontanería](fixtures-and-plumbing.md).

## Inspeccionar la fontanería de una casa del mapa

**Objetivo:** revisar una casa que ya venía en el mapa y sacar a la luz la fontanería oculta que se considera que ya tenía.

El mod crea esas tuberías solo cuando se lo pides, para no tener que crearlas en todos los edificios del mapa. No sirve para casas construidas por ti: en esas tienes que poner las tuberías a mano.

**Materiales:** una Llave para tubos utilizable y, por defecto, un Tubo metálico por cada aparato que se vaya a conectar.

1. Entra en el edificio y elige una casilla con suelo cerca de donde quieras poner el depósito o la fuente; desde ahí saldrán las tuberías.
2. Haz clic derecho y elige **[Conectar la fontanería del edificio](glossary.md#conectar-la-fontaneria)**; mira el coste en la descripción.
3. Deja que termine la acción. Si se interrumpe, las tuberías ya creadas se quedan.
4. Conecta la casilla de partida a un depósito o una fuente y usa **Mostrar red de tuberías** para ver la red.
5. Si se ha quedado a medias, lee el motivo que indica el juego y repite desde un punto mejor.

**Comprobación:** cada aparato al que se ha llegado aparece en azul y las tuberías ocultas se ven al resaltar la red. **Errores habituales:** intentarlo en un edificio construido por ti, hacer clic fuera de un edificio del mapa, no llevar tubos suficientes, que no haya pared norte u oeste para cambiar de planta, o llegar al límite de 200 casillas nuevas. Consulta [Inspeccionar la fontanería de un edificio](building-plumbing.md).

## Sacar agua de un pozo o de un río

**Objetivo:** llenar tus depósitos desde un pozo, un río o un lago.

**Materiales:** lo necesario para la Bomba de agua, electricidad, tuberías y un depósito.

1. Construye la bomba sobre el pozo o la orilla, o en una casilla pegada en línea recta (norte, sur, este u oeste; en diagonal no vale), a no más de 7 m por encima del agua (el límite de [aspiración](glossary.md#aspiracion) por defecto).
2. Une con tuberías los dos lados por los que conecta la bomba con la red del depósito, y dale electricidad.
3. Haz clic derecho en la bomba y elige **Encender**.
4. Usa **Ver estado de la bomba** para confirmar que tiene corriente y que ha encontrado la fuente.

**Comprobación:** la ventana indica que está sacando agua (de un pozo, o de un río o lago), y el depósito se llena a hasta 20 L/min por defecto. **Errores habituales:** bomba apagada, sin electricidad, bomba en diagonal respecto a la fuente, un pozo decorativo que no tiene agua, fuente demasiado abajo, depósito lleno, o la opción de sacar agua de ríos y lagos desactivada. El agua de ríos y lagos está contaminada; la de los pozos, limpia. Consulta [Fuentes y almacenamiento](sources-and-storage.md).

## Purificar agua contaminada

**Objetivo:** que el agua contaminada entre por un lado y salga limpia por el otro.

**Materiales:** Enrutador de fluidos, Purificador de agua (eléctrico), una red con agua contaminada, electricidad y, si quieres, un depósito para el agua limpia.

1. Orienta el enrutador con la entrada verde hacia la red contaminada y la salida roja hacia la limpia.
2. Coloca la esquina superior (la del fondo) del purificador sobre la casilla del enrutador y deja libre el suelo de la planta de arriba.
3. Dale corriente y elige **Abrir purificador**.
4. Comprueba que le entra agua contaminada, que el filtro está bien y que su depósito interno de salida (50 L) tiene sitio.
5. Añade un depósito en el lado limpio si quieres guardar más agua, y una bomba después del purificador si necesitas más presión.

**Comprobación:** la ventana dice **Filtrando** y el agua limpia va subiendo, a hasta 10 L/min. **Errores habituales:** enrutador al revés, agua que ya está limpia o que no es agua, falta de corriente, filtro atascado o salida llena. Consulta [Purificación](purification.md).

## Instalar riego

**Objetivo:** regar los cultivos solos sin reventar los goteros.

**Materiales:** goteros o aspersores, un depósito con agua y, según el caso, bomba y enrutador.

1. Pon un gotero en cada planta si la línea tiene poca presión, o un aspersor en el centro de un cuadrado de 3×3.
2. Si los goteros van detrás de una bomba (que da +25 m por defecto), pon antes un enrutador y fija su límite por debajo de 15 m.
3. Para los aspersores, asegúrate de que llegan al menos 20 m (valor por defecto).
4. Elige **Comprobar emisor de riego** y corrige lo que indique.

**Comprobación:** las plantas vivas que necesitan agua la reciben. **Errores habituales:** red sin agua, poca presión para los aspersores, demasiada para los goteros, plantas muertas o casillas sin plantar, o demasiados emisores en la misma línea, que dejan sin presión a los del final. Consulta [Riego](irrigation.md).

## Abastecer un generador con gasolina

**Objetivo:** que un generador se rellene solo desde una red de gasolina separada.

**Materiales:** un depósito solo para gasolina, tuberías, una Llave para tubos y, si hace falta, una bomba con corriente.

1. Pon una **Tubería de fluidos** en la casilla del depósito de gasolina y lleva las tuberías por un camino separado del agua.
2. Pon la última tubería en la casilla del generador.
3. Con la Llave para tubos, haz clic derecho en el generador y elige **Instalar Generador**.
4. Asegúrate de que todos los depósitos de esa red solo tienen gasolina. Añade presión si la distancia o la altura lo piden.
5. Cuando el generador baje del 25 % (valor por defecto), lo comprobará en el siguiente minuto de juego y se rellenará hasta el 100 %.

**Comprobación:** baja la gasolina del depósito y sube la del generador. **Errores habituales:** la red solo tiene agua, el depósito de gasolina está vacío, falta presión, el umbral está a 0 o el generador no está instalado. Consulta [Transporte de combustible](fuel-transport.md).

## Separar y controlar ramales

**Objetivo:** aislar una zona con una válvula o hacer que el agua vaya en un solo sentido con un enrutador.

1. Monta una **Válvula de corte** sobre una tubería normal si quieres poder separar y volver a unir dos partes de la red.
2. Ciérrala antes de hacer reparaciones o antes de que dos líquidos distintos puedan encontrarse; vuelve a abrirla solo después de revisar los dos lados.
3. Usa un **Enrutador de fluidos** donde el agua tenga que ir en un solo sentido: la entrada verde hacia la fuente y la salida roja hacia donde va el agua.
4. Fija un límite de presión si quieres proteger goteros o repartir los consumidores en zonas.
5. Resalta cada lado con **Mostrar red de tuberías** para comprobar que la separación está donde querías.

**Comprobación:** con la válvula cerrada aparecen dos redes independientes; el enrutador solo deja pasar agua de la entrada a la salida. **Errores habituales:** enrutador al revés, abrir una válvula entre gasolina y agua, o poner un límite por debajo de lo que necesita el consumidor. Consulta [Enrutadores y válvulas](routers-and-valves.md).
