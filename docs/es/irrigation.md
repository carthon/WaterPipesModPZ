# Riego

| Emisor | Receta | Cobertura | Presión predeterminada | Consumo de red |
|---|---|---|---:|---:|
| Gotero | Agricultura 1, Llave para tubos, 1 Tubería de metal | Su propia casilla | Sin mínimo; revienta por encima de 15 m | 0,2 L/hora |
| Aspersor | Agricultura 2, Llave para tubos, 1 Tubería de metal, 1 Chapa metálica | 3×3 completo | Necesita 20 m | 1,8 L/hora |

Construirlos concede 10 XP de Agricultura para el gotero y 20 para el aspersor. Ambos son segmentos de tubería: conducen fluido y se pueden colocar sobre cultivos. Añaden 10 puntos de agua al cultivo por hora de juego cuando una planta viva necesita riego. El agua contaminada riega igual que la limpia.

El gotero solo cobra su casilla. El aspersor gasta por las nueve casillas, tengan cultivo o no, y, si está habilitado en sandbox, hace ruido en un radio de 12 casillas. Su spray también moja a los personajes dentro del 3×3.

## Diseños seguros

- **Línea de goteo:** fuente o bomba → Enrutador limitado por debajo del umbral de rotura → fila de goteros.
- **Zona de aspersión:** fuente → bomba o red municipal → enrutador → rama corta de aspersores. Divide grandes granjas en zonas porque la demanda compartida deja sin presión el extremo.
- Usa **Comprobar emisor de riego** para ver falta de agua, ausencia o insuficiencia de presión, riesgo de rotura o estado reventado.

![Línea de goteo con presión segura](../assets/images/diagram-irrigation-safe.svg){ .wp-diagram }

- **1–2** Barril y bomba con corriente: 1 m + 25 m = **26 m**.
- **3** Enrutador con **Fijar límite de presión** en 12 m, por debajo de los 15 m que revientan un gotero.
- **4** Cuatro goteros de 0,2 L/h en casillas seguidas: **12 m**. Entre los cuatro pierden menos de 0,1 m por casilla.

Un gotero reventado sigue conduciendo agua, pero deja de regar. Repáralo con Llave para tubos y 1 Cinta americana. Un umbral de rotura 0 en sandbox desactiva las roturas.

<!-- SCREENSHOT: 17-sprinkler-coverage.png — Aspersor activo mostrando toda su cobertura 3×3. -->
<!-- SCREENSHOT: 18-emitter-diagnostics.png — Resultado de Comprobar emisor para un problema de presión. -->
