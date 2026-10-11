# Conceptos básicos

## Un componente conectado, un suministro compartido

Una red incluye todas las tuberías y recipientes alcanzables sin cruzar una frontera cerrada. Los depósitos del componente comparten el resumen de fluidos; los aparatos y generadores extraen de él. Debe haber una tubería en la propia casilla del objeto para que participe.

```text
fuente/depósito ── tubería ── bomba ── consumidor
                              │
                              └── rama ── consumidor
```

La red debe contener un único tipo de fluido. Agua limpia combinada con contaminada se vuelve contaminada. Gasolina combinada con agua crea un componente mezclado que rechazan los consumidores normales.

## Fronteras

| Elemento | Estado abierto o normal | Estado de frontera |
|---|---|---|
| Hueco físico | Siempre separado | No existe conexión |
| Válvula de corte | Abierta: una red | Cerrada: dos redes; no cruzan fluido, presión ni contaminación |
| Enrutador de fluidos | Siempre separa entrada y salida | Transfiere en una dirección y puede limitar presión |
| Enrutador con recipiente/purificador | Frontera completa | Solo se intercambia a través del objeto |

Las tuberías verticales conectan plantas por bordes de pared norte u oeste. La presión decide si un consumidor alcanzable puede extraer: la altura ayuda, la distancia y demanda compartida cuestan presión, las bombas la añaden y los enrutadores solo la reducen.

![Tres fronteras de red](../assets/images/diagram-network-boundaries.svg){ .wp-diagram }

1. Hueco físico. 2. Válvula de corte cerrada. 3. Enrutador unidireccional, de entrada verde a salida roja.
