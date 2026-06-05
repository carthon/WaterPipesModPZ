# Arquitectura

## Objetivo actual

La version actual del mod resuelve tres piezas principales:

- una red de pipes construibles que conecta contenedores placeables con fluidos,
- una redistribucion simple del volumen total dentro de cada componente,
- y una integracion con plumbing vanilla sin sustituir las acciones vanilla de consumo.

## Modelo de red

La red se representa como un grafo persistente en `ModData`:

- nodo `pipe`: una casilla que contiene un tramo de tuberia del mod;
- nodo `container`: un contenedor placeable del mundo detectado alrededor de una pipe;
- arista `pipe-pipe`: conexion cardinal o vertical (`z+1 / z-1`) entre pipes;
- arista `pipe-container`: un contenedor detectado en la misma casilla o en una casilla vecina de la red.

## Contenedores compatibles

El escaneo de almacenamiento usa la API de fluidos de B42 y detecta de forma generica objetos del mundo con `FluidContainer` finito. La red no depende de una whitelist cerrada de `rain collectors`, `amphorae` o muebles concretos.

Reglas actuales:

- solo se cuentan contenedores reales del mundo;
- el adaptador oculto de plumbing no entra en la contabilidad de almacenamiento;
- si una red contiene mas de un tipo de fluido, se omite la redistribucion para evitar mezclas implicitas.

## Redistribucion

El sistema servidor reconstruye periodicamente el estado y reparte el fluido por proporcion comun:

1. reconstruir el grafo a partir de las pipes registradas;
2. escanear contenedores cercanos a la red;
3. calcular componentes conectados;
4. sumar capacidad total y volumen total por componente;
5. si la red contiene un solo tipo de fluido, repartir segun la misma proporcion en todos los contenedores;
6. si hay mezcla de fluidos, no redistribuir.

Esto mantiene una primera version simple y predecible sin modelar presion ni direccion de flujo.

## Plumbing vanilla

La integracion con sinks y endpoints similares no reimplementa `Drink`, `Fill` o `Wash`.

El flujo actual es:

1. el jugador usa la opcion vanilla `Plumb`;
2. el mod intercepta esa accion solo si el endpoint tiene una pipe del mod en su casilla y una red valida;
3. si no se cumple esa condicion, el callback delega a vanilla sin cambios;
4. si se cumple, el endpoint queda marcado como plumbed al mod;
5. el mod crea una fuente adaptadora oculta en `z+1` para que el motor la acepte como `external water source`.

Esto permite que el endpoint siga usando las acciones vanilla de agua, pero alimentado por la red del mod.

## Adaptador oculto

El adaptador es una solucion tecnica para encajar con la resolucion interna de plumbing del motor.

Caracteristicas actuales:

- se crea como objeto fuente compatible con el motor;
- cambia su sprite visible a un tile vacio del tileset del mod;
- se marca con flags como `setNoPicking(true)` para reducir interaccion directa;
- su menu contextual propio se poda desde cliente para que no aparezcan menus de `Rain Collector` del proxy;
- si se destruye en debug, el servidor intenta recrearlo mientras el endpoint siga plumbed.

## Construccion

Las pipes ya no se colocan desde un submenu contextual. El flujo actual usa una receta buildable real en el menu de construccion vanilla:

- categoria `Piping`;
- receta `Water Pipe`;
- cursor custom basado en `ISBuildingObject`;
- cuatro modos de colocacion: suelo E/O, suelo N/S, pared E/O y pared N/S.

## Riesgos tecnicos abiertos

- El adaptador oculto sigue dependiendo de comportamiento interno del motor no expuesto del todo en Lua.
- La prioridad entre red del mod y fuentes vanilla coexistentes es un area sensible y requiere mas pruebas.
- El sistema esta pensado primero para estabilidad en singleplayer; multijugador necesita una validacion mas amplia.
- Todavia no hay modelado de bombas, valvulas, filtros ni gravedad real.

## Direccion prevista

1. ampliar las variantes visuales de pipes segun conexiones;
2. endurecer mas los casos de esquina de plumbing con multiples fuentes vanilla;
3. validar conservacion de agua y sincronizacion en escenarios mas grandes;
4. despues de eso, plantear sistemas mas complejos como bombas o valvulas.
