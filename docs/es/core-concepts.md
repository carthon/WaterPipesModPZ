# Conceptos básicos

## Una red comparte toda su agua

Una [red](glossary.md#red) es el conjunto de tuberías y de todo lo que está conectado a ellas sin que nada lo corte. Los [depósitos](glossary.md#deposito) de una misma red funcionan como si fueran uno solo: los [aparatos](glossary.md#aparato) y los generadores sacan el agua de ese conjunto, esté donde esté. Para que un objeto forme parte de la red tiene que haber una tubería en su propia [casilla](glossary.md#casilla); al lado no basta.

```text
fuente/depósito ── tubería ── bomba ── consumidor
                              │
                              └── ramal ── consumidor
```

Los líquidos incompatibles nunca se mezclan: el mod rechaza cualquier trasvase que juntaría gasolina con agua o cualquier otra pareja incompatible. El agua limpia y la [contaminada](glossary.md#agua-contaminada) sí pueden juntarse, pero el resultado queda contaminado. Aun así, es mejor usar una red distinta para cada líquido, para que cada aparato reciba el que necesita.

## Qué divide una red en dos

| Elemento | En estado normal | Cuando separa |
|---|---|---|
| Hueco (una casilla sin tubería) | Siempre separa | No hay conexión |
| [Válvula de corte](glossary.md#valvula-de-corte) | Abierta: una sola red | Cerrada: dos redes; no pasa ni líquido, ni presión, ni contaminación |
| [Enrutador de fluidos](glossary.md#enrutador) | Siempre separa su entrada de su salida | Deja pasar el agua en un solo sentido y, si quieres, limita la presión |
| Enrutador con un depósito o un purificador encima | Separación total | Los dos lados solo intercambian a través de ese objeto |

Las [tuberías verticales](glossary.md#tuberia-vertical) unen plantas por las paredes norte u oeste. Que un consumidor esté conectado no garantiza que reciba agua: decide la [presión](glossary.md#presion). La altura la aumenta, la distancia y el consumo de otros puntos de la línea la reducen, las bombas la suman y los enrutadores solo pueden bajarla.

![Tres formas de dividir una red](../assets/images/diagram-network-boundaries.svg){ .wp-diagram }

- **1** Hueco sin tubería.
- **2** Válvula de corte cerrada.
- **3** Enrutador de fluidos: el agua solo pasa de la entrada verde a la salida roja.
