# Purificación

## Construcción

El **Purificador de agua (eléctrico)** necesita Electrónica 4, Metalistería 3, una Llave para tubos, 3 usos de Soplete, 2 usos de Varillas para soldar, 3 Tubos metálicos, 2 Chapas metálicas, 1 Chatarra electrónica, 1 Alambre, 1 Mechero - Batería improvisada, 1 Carbón vegetal y 2 Retales de tela. Construirlo da 40 XP de Electrónica y 30 XP de Metalistería.

Primero construye y orienta un [Enrutador de fluidos](glossary.md#enrutador): la franja verde es la **entrada** del agua contaminada y la roja la **salida** del agua limpia. El purificador ocupa 2×2 casillas; su esquina superior (la del fondo) va sobre la casilla del enrutador, y el suelo de la planta de arriba sobre esa esquina tiene que estar libre. No se puede colocar sin enrutador ni encima de otro purificador.

![Recorrido del agua en el purificador](../assets/images/diagram-purifier-flow.svg){ .wp-diagram }

- **1** Depósito de agua contaminada.
- **2** Entrada verde del enrutador.
- **3** Purificador con corriente y filtro, colocado sobre el enrutador.
- **4** Salida roja del enrutador.
- **5** Depósito de agua limpia.

<!-- SCREENSHOT: 13-purifier-placement.png — Vista previa del purificador, con su esquina sobre el enrutador y sus 2×2 casillas. -->

## Funcionamiento y filtro

Con corriente, toma hasta 20 L/min de agua contaminada y limpia hasta 10 L/min (en su ventana, la cantidad aparece en «u», unidades; una unidad es un litro). Tiene dos depósitos internos de 50 L: uno para el agua que entra y otro para la que sale limpia. No hace nada con el agua que ya está limpia ni con líquidos que no sean agua. Un depósito externo en el lado limpio es opcional, pero recomendable: sin él, el purificador se para en cuanto se llenan sus 50 L de salida.

El filtro empieza al 100 %. Con el desgaste por defecto, limpia unos 5000 L antes de atascarse. Para repararlo, haz clic derecho, elige **Reparar filtro** y gasta 1 Carbón vegetal y 2 Retales de tela; vuelve al 100 %. **Abrir purificador** muestra si tiene corriente, cuánta agua hay en la entrada y en la salida, a qué ritmo filtra y cómo está el filtro. El zumbido de la máquina se puede quitar en **Opciones → Mods → Tuberías de Agua**.

Por defecto, al lado limpio solo le llega el 60 % de la [presión](glossary.md#presion) que entra: 25 m se quedan en 15 m, suficiente para grifos y goteros, pero por debajo de los 20 m que necesita un aspersor. Si hace falta más, pon una bomba después del purificador o cambia ese porcentaje en las opciones de sandbox.

## Desmontaje

Necesitas un Soplete con combustible y una Máscara de soldador. Cada material se recupera por separado: 1 Chapa metálica y 2 Tubos metálicos con un 80 % de probabilidades, y 1 Chatarra electrónica y 1 Alambre con un 60 %. La batería, el carbón y los retales no se recuperan; si el purificador se destruye, no devuelve nada.

<!-- SCREENSHOT: 15-purifier-status-window.png — Ventana del purificador mientras filtra. -->
