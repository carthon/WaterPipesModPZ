# Enrutadores, válvulas y manómetros

| Componente | Receta | Dónde se coloca |
|---|---|---|
| Enrutador de fluidos | Llave para tubos, 2 Tubos metálicos, 1 Chapa metálica | Sustituye a una tubería de suelo; gíralo con **R** |
| Válvula de corte | Llave para tubos, 1 Tubo metálico, 1 Barra de hierro - Media | Sobre una tubería de suelo normal ya construida |
| Manómetro | Llave para tubos, 1 Tubo metálico, 1 Chatarra electrónica | Sobre una tubería ya construida que no tenga válvula |

## Enrutador de fluidos

El [enrutador](glossary.md#enrutador) tiene una franja verde, que es la **entrada**, y una roja, que es la **salida**. El agua y la presión solo pasan en ese sentido, nunca al revés. Sin nada encima, mueve hasta 30 L por minuto de juego y puede rebajar la presión de salida hasta el tope que elijas, pero nunca la aumenta. Si varios enrutadores toman agua de la misma fuente, se turnan; no multiplican lo que da la fuente.

Haz clic derecho en el enrutador y elige **Fijar límite de presión...**. La ventana muestra la presión que entra y la que sale. Déjalo sin límite si solo quieres que el agua no vuelva hacia atrás; ponlo por debajo de 15 m para proteger goteros con los valores por defecto, o en 20 m como mínimo si detrás hay un aspersor que tiene que funcionar. Si colocas un depósito o un purificador en la casilla del enrutador, los dos lados quedan totalmente separados y solo intercambian agua a través de ese objeto.

<div class="wp-gallery wp-gallery--2" markdown>
![Enrutador de fluidos con su entrada verde y su salida roja](../assets/images/10-router-orientation-cropped.png){ .wp-screenshot loading=lazy }
![Ventana Fijar límite de presión del enrutador](../assets/images/11-router-pressure-dialog-cropped.png){ .wp-screenshot loading=lazy }
</div>

## Válvula de corte

La [válvula](glossary.md#valvula-de-corte) se construye abierta y no cambia nada mientras siga abierta. Haz clic derecho y elige **Cerrar válvula** o **Abrir válvula**: se gira a mano, sin herramientas. Una válvula vinculada a un [Sensor de humedad](irrigation.md#sensor-de-humedad) se abre y se cierra sola; si la cierras a mano, se queda cerrada diga lo que diga el sensor. Al cerrarla, su casilla deja de conducir: los dos lados dejan de compartir líquido, presión y contaminación. Sirve para aislar una zona mientras la reparas, para mantener la gasolina separada del agua o para que una contaminación no se extienda mientras cambias la instalación. No puede compartir casilla con un manómetro, un enrutador, una bomba, un gotero ni un aspersor.

<div class="wp-gallery wp-gallery--2" markdown>
![Válvula de corte cerrada](../assets/images/12a-valve-closed-cropped.png){ .wp-screenshot loading=lazy }
![Válvula de corte abierta](../assets/images/12a-valve-open-cropped.png){ .wp-screenshot loading=lazy }
</div>
