# Fontanería de edificios

**Fontanear el edificio** genera un árbol de tubería oculta y sin anillos desde la casilla elegida hasta cada aparato sin conectar que pueda alcanzar dentro del mismo edificio. Reutiliza tuberías existentes, solo cambia de planta donde una pared norte u oeste admite un montante y nunca construye encima de otra tubería.

## Procedimiento

1. Sitúate dentro del edificio con una Llave para tubos utilizable.
2. Lleva las Tuberías de metal necesarias: por defecto, una por aparato conectado, sin importar la longitud del recorrido.
3. Haz clic derecho en una casilla con suelo adecuada y elige **Fontanear el edificio**.
4. Revisa la descripción y comienza la acción. Se planifican primero los aparatos más cercanos.
5. Al terminar, conecta el árbol generado a un depósito o fuente y revísalo con **Mostrar red de tuberías**.

Una pasada coloca como máximo 200 casillas nuevas y examina hasta 8000 casillas del edificio. Si el resultado es parcial, repite desde otro lugar. Cobra los aparatos planificados al empezar y devuelve el coste de los que no alcance. El trabajo ya colocado permanece si se interrumpe. La tubería generada no devuelve material al desmontarla.

<!-- SCREENSHOT: 21-building-before.png — Casa de varias estancias sin fontanear antes de ejecutar la acción. -->
<!-- SCREENSHOT: 22-building-plumb-action.png — Acción Fontanear el edificio y descripción de su coste. -->
<!-- SCREENSHOT: 23-building-after-overlay.png — Árbol oculto generado, revelado después de completar. -->

## Mensajes de resultado

| Mensaje o motivo | Significado y respuesta |
|---|---|
| No estás dentro de un edificio | Elige una casilla con suelo reconocida como parte de un `IsoBuilding` |
| Aquí no hay nada que fontanear | No se encontró ningún aparato compatible sin conectar |
| Ya está fontaneado | Todos los aparatos detectados están conectados |
| Edificio demasiado grande | Solo se planificó la zona examinada más cercana; repite en otra parte |
| No hay ruta | La distribución sólida o la red existente impiden un camino seguro |
| No hay pared para llegar a su planta | Añade o elige una ruta con montante en pared norte/oeste |
| Cerraría un anillo | Se omite deliberadamente para no crear un bucle |
| Supera el límite | Se alcanzaron las 200 casillas nuevas; repite desde otro punto |
| El servidor detuvo el trabajo | En multijugador rechazó trabajo obsoleto, inválido o sin materiales |

En multijugador la construcción es autoritativa en el servidor. El cliente espera aprobación antes de conectar aparatos y se reembolsa lo cobrado por los que no se coloquen al cerrar la pasada.

<!-- TODO: Verificar casas construidas por jugadores y bañeras de varias casillas en una partida real de Build 42. -->

