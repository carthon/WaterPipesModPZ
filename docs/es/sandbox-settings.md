# Opciones de sandbox

Las [opciones de sandbox](glossary.md#opciones-de-sandbox) son las reglas que se eligen al crear una partida y se guardan con ella. Water Pipes v0.10.x añade 26, agrupadas en **Tuberías de Agua**. Algunos valores se indican en **décimas**: el juego los divide entre diez, así que `250` significa 25,0 m de [presión](glossary.md#presion).

## Líquidos y generadores

| Opción | Por defecto | Rango | Qué hace |
|---|---:|---:|---|
| Purificación de agua realista | Sí | Sí/No | El agua contaminada sigue contaminada hasta que pasa por un purificador. Con «No», los grifos vuelven a dar agua limpia como en el juego sin mods |
| Umbral de auto-repostaje del generador | 25 % | 0–100 | Por debajo de este nivel, el generador empieza a tomar combustible; con 0 no se rellena solo |
| Objetivo de auto-repostaje del generador | 100 % | 0–100 | Nivel del depósito al que deja de rellenarse |
| Ritmo de desgaste del filtro del purificador | 100 % | 0–1000 | Multiplica lo rápido que se gasta el filtro; con 0 no se gasta nunca |

## Presión y bombas

| Opción | Por defecto | Rango | Qué hace |
|---|---:|---:|---|
| Modelo de presión del agua | Realista | Realista/Simple/Desactivado | Realista: altura, distancia y bombas. Simple: solo la altura. Desactivado: comportamiento antiguo, solo gravedad |
| Presión ganada por planta de altura | 30 | 0–200 décimas | 3,0 m por planta por defecto |
| Presión base de un contenedor | 10 | 0–200 décimas | 1,0 m en su propia planta por defecto |
| Fricción de las tuberías | 100 % | 0–500 | Multiplica la presión que se pierde con la distancia; con 0 no se pierde nada |
| Presión que deja pasar un purificador | 60 % | 0–100 | Parte de la presión de entrada que llega al lado limpio |
| Demanda compartida | 100 % | 0–100 | Cuánto se quitan presión los consumidores que funcionan a la vez en la misma línea |
| Presión que aporta una bomba | 250 | 0–1000 décimas | 25,0 m por defecto; varias bombas en la misma línea se suman |
| Límite de aspiración de la bomba | 70 | 0–500 décimas | La bomba saca agua hasta 7,0 m por debajo de ella |
| Caudal de la bomba | 20 L/min | 0–500 | Agua que saca de un pozo, río o lago |
| Las bombas pueden sacar agua de ríos y lagos | Sí | Sí/No | Permite sacar agua contaminada sin límite de ríos y lagos |

## Riego y agua municipal

| Opción | Por defecto | Rango | Qué hace |
|---|---:|---:|---|
| Presión que revienta un gotero | 150 | 0–1000 décimas | Revienta por encima de 15,0 m; con 0 no revienta nunca |
| Los aspersores hacen ruido | Sí | Sí/No | Un aspersor en marcha atrae zombis |
| El agua municipal llena la red | Sí | Sí/No | Hasta el [corte del agua](glossary.md#corte-de-suministros), los aparatos instalados meten agua de la ciudad en la red |
| Presión del agua municipal | 250 | 0–1000 décimas | 25,0 m por defecto |
| Caudal del agua municipal | 60 L/min | 0–1000 | Ritmo al que el agua de la ciudad llena la red |

## Agua estancada, lluvia y bocas de incendios

| Opción | Por defecto | Rango | Qué hace |
|---|---:|---:|---|
| El agua se estanca | Sí | Sí/No | El agua que pasa mucho tiempo quieta acaba contaminándose |
| Días hasta que el agua sellada se echa a perder | 30 | 0–180 | Para depósitos tapados y las propias tuberías; con 0 no se estropea nunca |
| Días hasta que el agua abierta se echa a perder | 10 | 0–180 | Para depósitos destapados; con 0 no se estropea por el tiempo, pero la lluvia aún puede contaminarla |
| La lluvia contamina el agua abierta | Sí | Sí/No | La lluvia que cae en un depósito destapado al aire libre contamina toda su red |
| Reserva de la boca de incendios | 1000 L | 0–20 000 | Agua que le queda después del corte |
| Presión de la boca de incendios | 400 | 0–1000 décimas | 40,0 m mientras le llega agua de la ciudad |

## Fontanería de los edificios del mapa

| Opción | Por defecto | Rango | Qué hace |
|---|---:|---:|---|
| Tuberías de metal por aparato | 1 | 0–10 | Tubos metálicos que cuesta cada aparato conectado con **Fontanear el edificio** |

## Configuraciones recomendadas para empezar

- **Fácil:** desactiva la purificación realista y el estancamiento, usa el modelo de presión Simple y pon a 0 la presión que revienta los goteros.
- **Supervivencia normal:** deja todos los valores como vienen.
- **Supervivencia difícil:** baja los caudales y las reservas, sube la fricción y el desgaste del filtro y acorta los días de estancamiento.

Cambiar estos valores modifica la simulación de la partida, pero no reconstruye nada ni cambia lo que ya está construido.

## Opciones del mod: solo en tu pantalla

Estas opciones están en **Opciones → Mods → Tuberías de Agua**. Solo afectan a lo que ves y oyes tú, no a la simulación del agua en la partida:

| Opción | Qué hace |
|---|---|
| Sonidos de las máquinas | Activa el zumbido continuo de las máquinas, como el del purificador con corriente |
| Volumen de sonido de las máquinas (%) | Ajusta ese sonido de 0 a 100 |
| Efectos de agua | Muestra el chorro animado de los aspersores en marcha y de las bocas de incendios abiertas |

<!-- SCREENSHOT: 26-sandbox-options.png — Página de opciones de sandbox con el grupo Tuberías de Agua completo. -->
