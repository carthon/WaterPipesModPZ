# Arquitectura Inicial

## Alcance de la primera version

La primera version busca resolver un problema concreto: redistribuir agua entre recipientes conectados por una red de pipes sin modelar todavia presion, altura, bombas ni valvulas.

## Modelo

La red se representa como un grafo persistente en `ModData`:

- Nodo `pipe`: una casilla que contiene un tramo de tuberia.
- Nodo `container`: un contenedor del mundo detectado en una casilla conectable.
- Arista `pipe-pipe`: dos pipes ortogonalmente adyacentes.
- Arista `pipe-container`: un recipiente en la misma casilla o casilla cardinal adyacente a una pipe.

## Flujo servidor

1. Cargar o crear el estado persistente del mod.
2. Reconstruir el grafo a partir de las pipes registradas.
3. Escanear las casillas cercanas a cada pipe para detectar recipientes candidatos.
4. Calcular componentes conectados.
5. Para cada componente, sumar agua total y capacidad total.
6. Repartir el agua segun una proporcion comun para toda la red.

## Supuestos

- La casilla es la unidad de conexion.
- La conectividad es solo cardinal.
- Un contenedor conectado puede redistribuir agua aunque sea de un tipo vanilla distinto, siempre que exponga una API compatible.
- Esta version prioriza compatibilidad y simplicidad sobre realismo.

## Riesgos tecnicos

- La API Lua exacta de algunos objetos contenedor puede variar entre variantes vanilla.
- Algunos objetos del mundo almacenan agua en estructuras distintas y requeriran adaptadores especificos.
- La colocacion de tiles y sprites necesita una segunda pasada con assets definitivos.

## Evolucion prevista

1. Pipe construible con sprite y contexto de construccion.
2. Registro automatico al colocar o desmontar pipes.
3. Adaptadores especificos para rain collector, barriles, fregaderos y muebles con agua.
4. Reglas opcionales: fugas, gravedad, bombas, filtros, valvulas.
