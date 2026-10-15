# Riego

| Componente | Receta | Qué riega | Presión por defecto | Agua que gasta |
|---|---|---|---:|---:|
| Gotero | Agricultura 1, Llave para tubos, 1 Tubo metálico | Su propia casilla | Sin mínimo; revienta por encima de 15 m | 0,2 L/hora |
| Aspersor | Agricultura 2, Llave para tubos, 1 Tubo metálico, 1 Chapa metálica | Un cuadrado de 3×3 casillas | Necesita 20 m | 1,8 L/hora |

Construir un gotero da 10 XP de Agricultura, y un aspersor, 20. Los dos funcionan también como tubería: dejan pasar el agua hacia las siguientes y se pueden poner encima de los cultivos. Mientras una planta viva necesite agua, le suman 10 puntos de riego por cada hora de juego. El [agua contaminada](glossary.md#agua-contaminada) riega igual de bien que la limpia.

El gotero solo gasta agua en su casilla. El aspersor gasta agua por las nueve casillas, haya cultivos o no, y, si está activado en las opciones de sandbox, hace ruido que se oye a 12 casillas (y atrae zombis). Su chorro también moja a los personajes que estén dentro del cuadrado.

## Instalaciones seguras

- **Línea de goteros:** fuente o bomba → enrutador con un límite por debajo de la presión que revienta los goteros → fila de goteros.
- **Zona de aspersores:** fuente → bomba o red municipal → enrutador → ramal corto de aspersores. Divide las granjas grandes en varias zonas: si todos los aspersores comparten la misma línea, los del final se quedan sin presión (es la [demanda compartida](glossary.md#demanda-compartida)).
- Haz clic derecho en un gotero o aspersor y elige **Comprobar emisor de riego** para saber si no tiene agua, si le falta presión, si está a punto de reventar o si ya ha reventado.

![Línea de goteros con presión segura](../assets/images/diagram-irrigation-safe.svg){ .wp-diagram }

- **1–2** Barril y bomba con corriente: 1 m + 25 m = **26 m**.
- **3** Enrutador con **Fijar límite de presión** en 12 m, por debajo de los 15 m que revientan un gotero.
- **4** Cuatro goteros de 0,2 L/hora en casillas seguidas: **12 m**. Entre los cuatro pierden menos de 0,1 m por casilla.

Un gotero reventado sigue dejando pasar el agua, pero deja de regar. Se repara con **Reparar gotero**, una Llave para tubos y 1 Cinta americana. Si pones la presión de rotura a 0 en las opciones de sandbox, los goteros no revientan nunca.

<!-- SCREENSHOT: 17-sprinkler-coverage.png — Aspersor regando toda su zona de 3×3. -->
<!-- SCREENSHOT: 18-emitter-diagnostics.png — Resultado de Comprobar emisor de riego con un problema de presión. -->
