# Opciones de sandbox

Water Pipes v0.10.0 incluye 26 opciones por partida. Los valores expresados en **décimas** se dividen entre diez dentro del juego: `250` significa 25,0 m de columna de agua.

## Líquidos y generadores

| Opción | Predeterminado | Rango | Efecto |
|---|---:|---:|---|
| Purificación de agua realista | Sí | Sí/No | El agua contaminada requiere purificador; desactivarla restaura la limpieza del grifo del juego base |
| Umbral de auto-repostaje | 25 % | 0–100 | Empieza por debajo; 0 lo desactiva |
| Objetivo de auto-repostaje | 100 % | 0–100 | Deja de repostar en ese porcentaje |
| Desgaste del filtro | 100 % | 0–1000 | Multiplica el desgaste; 0 lo desactiva |

## Presión y bombas

| Opción | Predeterminado | Rango | Efecto |
|---|---:|---:|---|
| Modelo de presión | Realista | Realista/Simple/Desactivado | Modelo completo; solo altura; o gravedad antigua |
| Presión ganada por planta | 30 | 0–200 décimas | 3,0 m por planta por defecto |
| Presión base de recipiente | 10 | 0–200 décimas | 1,0 m en su planta por defecto |
| Fricción de tuberías | 100 % | 0–500 | Escala pérdidas por distancia; 0 las elimina |
| Presión transmitida por purificador | 60 % | 0–100 | Parte de la presión que llega al lado limpio |
| Demanda compartida | 100 % | 0–100 | Cuánto se perjudican consumidores simultáneos |
| Presión de una bomba | 250 | 0–1000 décimas | 25,0 m por defecto; bombas en serie suman |
| Límite de aspiración | 70 | 0–500 décimas | 7,0 m por debajo de la bomba |
| Caudal de bomba | 20 L/min | 0–500 | Extracción desde pozo o agua abierta |
| Bombas desde ríos/lagos | Sí | Sí/No | Permite agua contaminada ilimitada desde agua abierta |

## Riego y red municipal

| Opción | Predeterminado | Rango | Efecto |
|---|---:|---:|---|
| Presión de rotura del gotero | 150 | 0–1000 décimas | Revienta sobre 15,0 m; 0 evita roturas |
| Los aspersores hacen ruido | Sí | Sí/No | En marcha atraen zombis |
| El agua municipal llena la red | Sí | Sí/No | Aparatos conectados alimentan antes del corte |
| Presión municipal | 250 | 0–1000 décimas | 25,0 m por defecto |
| Caudal municipal | 60 L/min | 0–1000 | Ritmo de llenado de la acometida |

## Edad del agua, lluvia e hidrantes

| Opción | Predeterminado | Rango | Efecto |
|---|---:|---:|---|
| Estancamiento | Sí | Sí/No | El agua quieta puede contaminarse |
| Días del agua sellada | 30 | 0–180 | 0 evita que se estropee por tiempo |
| Días del agua abierta | 10 | 0–180 | 0 quita el temporizador; la lluvia aún puede contaminar |
| La lluvia contamina | Sí | Sí/No | Un depósito abierto exterior contamina su red |
| Reserva del hidrante | 1000 L | 0–20 000 | Agua restante tras el corte municipal |
| Presión del hidrante | 400 | 0–1000 décimas | 40,0 m mientras recibe agua municipal |

## Fontanería de edificios

| Opción | Predeterminado | Rango | Efecto |
|---|---:|---:|---|
| Tuberías de metal por aparato | 1 | 0–10 | Coste de **Fontanear el edificio** por aparato conectado |

## Perfiles iniciales sugeridos

- **Accesible:** desactiva la purificación realista y el estancamiento, usa presión Simple y establece la rotura de goteros en 0.
- **Supervivencia predeterminada:** conserva todos los valores originales.
- **Supervivencia difícil:** reduce caudales y reservas, aumenta fricción/desgaste y acorta el estancamiento.

Cambiar valores modifica la simulación de la partida; no reconstruye trazados ni sustituye objetos ya construidos.

## Mod Options: presentación local

Estos ajustes están en **Opciones → Mods → Water Pipes** y afectan al cliente actual, no a la simulación hidráulica de la partida:

| Opción | Efecto |
|---|---|
| Sonidos de las máquinas | Activa el sonido en bucle de máquinas como el purificador con corriente |
| Volumen de sonido de las máquinas (%) | Ajusta ese audio entre 0 y 100 |
| Efectos de agua | Muestra el chorro animado de aspersores activos y bocas abiertas |

<!-- SCREENSHOT: 26-sandbox-options.png — Página de sandbox con el grupo completo de Water Pipes. -->
