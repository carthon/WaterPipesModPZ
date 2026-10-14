# Inspeccionar la fontanería de un edificio

Los edificios generados por el mundo se tratan como si su instalación de fontanería ya existiera. Para no generar redes en todos los edificios del mapa, Water Pipes solo materializa esa instalación oculta cuando eliges **Fontanear el edificio**. Para el jugador, la acción **inspecciona y revela la fontanería existente del edificio**; no es una herramienta para instalar tuberías automáticamente en una construcción hecha por el jugador.

Al inspeccionarla, el mod crea un árbol de tubería oculta y sin anillos desde la casilla elegida hasta cada aparato sin conectar que pueda alcanzar en el mismo edificio. Reutiliza las tuberías compatibles que ya haya, solo cambia de planta donde una pared norte u oeste admite un montante y nunca coloca un tramo oculto encima de otra tubería.

!!! warning "Solo edificios del mundo"
    **Fontanear el edificio no instala automáticamente una red en edificios construidos por jugadores.** En ellos debes tender a mano tuberías de suelo, ocultas y verticales, y después conectar cada aparato de la forma habitual.

## Procedimiento

1. Sitúate dentro del edificio con una Llave para tubos utilizable.
2. Lleva las Tuberías de metal necesarias: por defecto, una por aparato conectado, sin importar la longitud del recorrido.
3. Haz clic derecho en una casilla con suelo adecuada y elige **Fontanear el edificio**.
4. Revisa la descripción y comienza la acción. Se planifican primero los aparatos más cercanos.
5. Al terminar, conecta el árbol revelado a un depósito o fuente y revísalo con **Mostrar red de tuberías**.

Una inspección puede revelar como máximo 200 casillas nuevas y examina hasta 8000 casillas del edificio. Si el resultado es parcial, repite desde otro lugar. Cobra los aparatos planificados al empezar y devuelve el coste de los que no alcance. La fontanería ya revelada permanece si se interrumpe. La tubería oculta revelada no devuelve material al desmontarla.

![Casa generada por el mundo antes de inspeccionar su fontanería existente](../assets/images/21-building-before-cropped.png){ .wp-screenshot loading=lazy }

![Acción Fontanear el edificio y descripción de su coste](../assets/images/22-building-plumb-action-cropped.png){ .wp-screenshot loading=lazy }

![Fontanería antes oculta visible después de inspeccionarla](../assets/images/23-building-after-overlay-cropped.png){ .wp-screenshot loading=lazy }

## Mensajes de resultado

| Mensaje o motivo | Significado y respuesta |
|---|---|
| No estás dentro de un edificio | Elige una casilla con suelo reconocida como parte de un `IsoBuilding` |
| Aquí no hay nada que fontanear | No se encontró ningún aparato compatible sin conectar |
| Ya está fontaneado | Todos los aparatos detectados están conectados |
| Edificio demasiado grande | Solo se inspeccionó la zona examinada más cercana; repite en otra parte |
| No hay ruta | La distribución sólida o la red existente impiden un camino seguro |
| No hay pared para llegar a su planta | Añade o elige una ruta con montante en pared norte/oeste |
| Cerraría un anillo | Se omite deliberadamente para no crear un bucle |
| Supera el límite | Se alcanzaron las 200 casillas nuevas; repite desde otro punto |
| El servidor detuvo el trabajo | En multijugador rechazó trabajo obsoleto, inválido o sin materiales |

En multijugador la inspección es autoritativa en el servidor. El cliente espera aprobación antes de conectar aparatos y se reembolsa el coste de las conexiones que no puedan completarse al cerrar la pasada.

