# Instalaciones prácticas con Water Pipes

Estos ejemplos de fontanería para Project Zomboid utilizan mecánicas verificadas de v0.10.0. Consulta las recetas en el [catálogo de componentes](component-reference.md) y usa [Resolución de problemas](troubleshooting.md) si falla la comprobación final.

## Primera red de agua

**Objetivo:** abastecer un fregadero desde un recipiente finito.

**Materiales:** Llave para tubos, un recipiente y una Tubería de metal o Segmento de arcilla cocida por casilla.

1. Coloca el recipiente y, si su diseño lo exige, ábrelo o destápalo.
2. Construye una **Tubería de fluidos** en la propia casilla del recipiente.
3. Extiende la ruta y coloca la última tubería en la propia casilla del fregadero.
4. Con la llave en el inventario, haz clic derecho en el fregadero y elige **Instalar**.
5. Usa **Mostrar red de tuberías** y prueba el fregadero.

**Comprobación:** recipiente/fuente verde, fregadero azul y ruta roja completa. **Errores habituales:** tubería adyacente, falta de vertical o esperar que la bomba almacene agua. Consulta [Redes de tuberías](pipe-networks.md) y [Aparatos](fixtures-and-plumbing.md).

## Fontanear automáticamente una vivienda

**Objetivo:** generar un árbol oculto y sin anillos hasta los aparatos compatibles de un edificio existente.

**Materiales:** Llave utilizable y, por defecto, una Tubería de metal por aparato que vaya a conectarse.

1. Sitúate dentro y elige una casilla con suelo próxima al suministro previsto.
2. Haz clic derecho y selecciona **Fontanear el edificio**; revisa el coste.
3. Deja terminar la acción. Si se interrumpe, lo ya construido permanece.
4. Une la raíz al almacenamiento o fuente y revela la red.
5. Si el resultado es parcial, lee el motivo y repite desde un lugar mejor.

**Comprobación:** cada aparato alcanzado aparece azul y el árbol se revela. **Errores habituales:** edificio no reconocido, tuberías insuficientes, ausencia de pared norte/oeste o límite de 200 tramos nuevos. Las casas construidas por jugadores y bañeras multicasilla siguen [pendientes de prueba real](building-plumbing.md).

## Extraer agua de un pozo o río

**Objetivo:** llenar almacenamiento desde una fuente natural.

**Materiales:** receta de Bomba de agua, electricidad, tuberías y un recipiente finito.

1. Construye la bomba sobre o junto al pozo/agua abierta, dentro de los 7 m de aspiración predeterminados.
2. Conecta su eje a la red de almacenamiento y alimenta eléctricamente su casilla.
3. Haz clic derecho y elige **Encender**.
4. Usa **Ver estado de la bomba** para confirmar corriente y fuente.

**Comprobación:** informa de pozo o agua abierta y el depósito sube hasta 20 L/min por defecto. **Errores habituales:** apagada, sin corriente, fuente fuera de alcance, destino lleno o extracción de ríos desactivada. El agua abierta está contaminada; el pozo es limpio. Consulta [Fuentes y almacenamiento](sources-and-storage.md).

## Purificar agua contaminada

**Objetivo:** separar entrada contaminada y salida limpia.

**Materiales:** Enrutador de fluidos, Purificador de agua (eléctrico), suministro contaminado, electricidad y almacenamiento limpio opcional.

1. Orienta el enrutador con la entrada verde hacia la red contaminada y la salida roja hacia la limpia.
2. Coloca el anclaje superior/trasero del purificador sobre el enrutador y deja libre el suelo superior.
3. Dale corriente y usa **Abrir purificador**.
4. Comprueba entrada contaminada, filtro y espacio en el búfer OUT de 50 unidades.
5. Añade almacenamiento limpio para ampliar capacidad y presión posterior si hace falta.

**Comprobación:** la ventana muestra **Filtrando** y aumenta la salida limpia, hasta 10 unidades/min. **Errores habituales:** enrutador invertido, entrada limpia/mezclada, sin corriente, filtro saturado o salida llena. Consulta [Purificación](purification.md).

## Instalar riego

**Objetivo:** regar automáticamente sin reventar emisores de baja presión.

**Materiales:** Goteros o Aspersores, almacenamiento y dispositivos de presión/control necesarios.

1. Usa un gotero por cultivo para baja presión o un aspersor central para un 3×3.
2. Para goteros tras una bomba de +25 m, añade un enrutador y limita por debajo de 15 m.
3. Para aspersores, aporta al menos 20 m en el emisor por defecto.
4. Usa **Comprobar emisor de riego** y corrige la condición indicada.

**Comprobación:** los cultivos vivos que necesitan agua la reciben. **Errores habituales:** red seca, poca presión para aspersor, exceso para gotero, cultivo muerto/ausente o demanda compartida. Consulta [Riego automático](irrigation.md).

## Abastecer un generador con gasolina

**Objetivo:** auto-repostar un generador desde una red aislada de gasolina.

**Materiales:** recipiente exclusivo de gasolina, tuberías, Llave para tubos y, opcionalmente, bomba con corriente.

1. Pon una **Tubería de fluidos** en la casilla del recipiente y construye una ruta aislada.
2. Coloca la última tubería en la casilla del generador.
3. Haz clic derecho con la llave y elige **Instalar Generador**.
4. Mantén todos los recipientes conectados solo con gasolina. Añade presión si la distancia o altura lo exige.
5. Deja que baje del 25 % predeterminado; comprueba cada minuto y extrae hacia el 100 %.

**Comprobación:** sale gasolina del depósito y entra en el generador. **Errores habituales:** red con agua/mezclada, depósito vacío, poca presión, umbral 0 o generador no instalado. Consulta [Transporte de combustible](fuel-transport.md).

## Separar y controlar ramales

**Objetivo:** aislar zonas con válvula o imponer flujo unidireccional con enrutador.

1. Monta una **Válvula de corte** sobre una tubería normal para una frontera reversible en ambos sentidos.
2. Ciérrala antes de mantener la red o de que puedan encontrarse dos líquidos distintos; ábrela tras comprobar ambos lados.
3. Usa un **Enrutador de fluidos** para flujo unidireccional: entrada verde a la fuente y salida roja aguas abajo.
4. Fija un techo de presión para proteger goteros o dividir consumidores.
5. Revela ambos lados para confirmar la frontera.

**Comprobación:** la válvula cerrada crea dos redes; el enrutador solo transfiere IN→OUT. **Errores habituales:** enrutador invertido, abrir entre gasolina y agua o límite inferior al mínimo del consumidor. Consulta [Enrutadores y válvulas](routers-and-valves.md).

