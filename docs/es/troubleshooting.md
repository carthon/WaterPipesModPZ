# Resolución de problemas

Esta página sirve para averiguar qué falla en una red que ya está construida. Para dudas generales, empieza por las [Preguntas frecuentes](faq.md) o los [Ejemplos prácticos](practical-examples.md).

## Revisión general, paso a paso

1. Comprueba que usas Project Zomboid 42.15 o posterior, Water Pipes v0.11.x y, en multijugador, la misma versión del mod en el servidor y en los jugadores.
2. Elige **Mostrar red de tuberías** y sigue todo el recorrido.
3. Comprueba que hay una tubería en la propia casilla de cada depósito, aparato o generador, y una Tubería vertical de fluidos en cada cambio de planta.
4. Revisa las válvulas cerradas, hacia dónde mira cada Enrutador de fluidos y los límites de presión que tengan.
5. Comprueba que los depósitos conectados no están vacíos y tienen el líquido que necesita el consumidor.
6. Mide la presión con **Ver estado de la bomba**, un Manómetro o **Comprobar emisor de riego**.
7. Revisa que las bombas y los purificadores tengan electricidad y estén encendidos.
8. Revisa las opciones de sandbox de **Water Pipes** de esa partida.
9. En multijugador, vuelve a conectarte, repite la acción una vez y confirma que todos tenéis la misma versión.
10. Si sigue sin funcionar, haz una captura de la red resaltada o de la ventana de estado y guarda las líneas importantes del archivo `console.txt` (el registro del juego).

## La red no conecta

**Síntoma:** un depósito o un aparato no aparece al resaltar la red, o funciona como si fuera de otra red.  
**Causas posibles:** la tubería está al lado y no en su misma casilla; falta una tubería vertical en un cambio de planta; hay una válvula cerrada; falta una casilla de tubería.  
**Qué revisar:** resalta la red y repasa todo el recorrido, incluidas las tuberías verticales de las paredes.  
**Solución:** pon la tubería que falta o la tubería vertical, o abre la válvula.  
**Más información:** [Redes de tuberías](pipe-networks.md)

## Un aparato no recibe agua

**Síntoma:** un aparato instalado está vacío.  
**Causas posibles:** no hay ningún depósito conectado; el depósito está vacío, tiene otro líquido o está más bajo que el aparato sin presión suficiente; un corte en algún punto lejano de la tubería lo ha dejado aislado.  
**Qué revisar:** los depósitos, la red resaltada, las válvulas y la presión en ese punto.  
**Solución:** rehaz el recorrido y conéctalo a un depósito con agua. Si hay líquidos incompatibles, el mod no los mezcla: simplemente rechaza el trasvase.  
**Más información:** [Fuentes y almacenamiento](sources-and-storage.md), [Aparatos y fontanería](fixtures-and-plumbing.md)

## La bomba no mueve agua

**Síntoma:** los depósitos no se llenan o no hay presión.  
**Causas posibles:** bomba apagada; sin electricidad; la bomba está en diagonal respecto a la fuente (solo mira al norte, sur, este y oeste); el pozo es decorativo y no da agua; la fuente está demasiado abajo; el depósito de destino está lleno; no hay ningún pozo, río ni lago válido cerca.  
**Qué revisar:** usa **Ver estado de la bomba**, que muestra la corriente, la fuente, la presión de entrada y de salida y lo que aporta.  
**Solución:** corrige lo que indique. Sin fuente, una bomba puede dar presión al agua que ya está guardada, pero no puede crear agua.  
**Más información:** [Bombas y presión](pumps-and-pressure.md)

## La presión es baja o desigual

**Síntoma:** los consumidores cercanos funcionan, pero los lejanos o los de plantas superiores no.  
**Causas posibles:** la distancia, la altura, demasiados consumidores en la misma línea, el límite de un enrutador o la presión que se pierde al pasar por un purificador.  
**Qué revisar:** compara lo que marcan varios manómetros a lo largo del recorrido y revisa si has cambiado alguna opción de sandbox.  
**Solución:** reduce el consumo o la distancia, divide la instalación en ramales separados por enrutadores o añade una bomba con corriente donde se pueda.  
**Más información:** [Bombas y presión](pumps-and-pressure.md), [Enrutadores y válvulas](routers-and-valves.md)

## No me deja colocar el purificador

**Síntoma:** la vista previa del purificador sale en rojo.  
**Causas posibles:** la esquina de anclaje (la superior) no está sobre un Enrutador de fluidos; ese enrutador ya tiene un purificador; hay suelo en la planta de encima de esa esquina. Comprobaciones del motor del juego, en las cuatro casillas: no hay suelo firme; estorba un barril, un recolector de lluvia, un mueble o un árbol; hay un jugador, un zombi, un animal o un vehículo encima; un muro, una valla o una ventana cruza el 2×2.  
**Qué revisar:** pon la esquina sobre el enrutador y mira qué hay en las otras tres casillas y en la planta de arriba.  
**Solución:** despeja las casillas o lleva el enrutador a un sitio abierto sin nada construido encima. Las tuberías en esas casillas no estorban.  
**Más información:** [Purificación](purification.md#condiciones-para-colocarlo)

## El purificador no limpia el agua

**Síntoma:** no sale agua limpia.  
**Causas posibles:** sin corriente; filtro atascado; el agua que entra ya está limpia o no es agua; el depósito de salida está lleno; el enrutador está al revés.  
**Qué revisar:** abre la ventana del purificador y comprueba que la entrada verde da a la red contaminada y la salida roja a la limpia.  
**Solución:** dale corriente o sitio donde dejar el agua, repara el filtro o corrige la red de entrada.  
**Más información:** [Purificación](purification.md)

## El aspersor o el gotero no riega

**Síntoma:** los cultivos siguen secos.  
**Causas posibles:** red sin agua; poca presión para el aspersor; gotero reventado; ninguna planta viva necesita agua ahora mismo.  
**Qué revisar:** usa **Comprobar emisor de riego**.  
**Solución:** haz lo que indique; si el gotero ha reventado, repáralo y limita la presión antes de él con un enrutador.  
**Más información:** [Riego](irrigation.md)

## El sensor de humedad no abre su válvula

**Síntoma:** los cultivos se secan, pero la válvula vinculada sigue cerrada.  
**Causas posibles:** sin energía (luz apagada): la casilla no tiene electricidad y no hay pila con carga; no hay cultivo en la casilla del sensor; la humedad aún no ha bajado al mínimo (entre los dos extremos se mantiene como estaba); **Invertir** está activado; la válvula se cerró a mano; la válvula no está vinculada.  
**Qué revisar:** clic derecho en el sensor, **Abrir sensor**: muestra la lectura, la señal y su motivo, la energía y las válvulas vinculadas. La información de la válvula dice si se apagó a mano o si está esperando señal.  
**Solución:** dale electricidad o una pila, planta en su casilla, ajusta el rango o usa **Abrir válvula** a mano para devolver el control a los sensores.  
**Más información:** [Sensor de humedad](irrigation.md#sensor-de-humedad)

## Una misma red tiene agua y gasolina

**Síntoma:** los aparatos o generadores no reciben nada, aunque los depósitos de su líquido no están vacíos.  
**Causa posible:** hay depósitos con líquidos incompatibles conectados a la misma red. Los líquidos no se mezclan ni se contaminan entre sí, pero el mod no entrega nada mientras la red tenga a la vez más de un líquido incompatible.  
**Qué revisar:** resalta la red y busca el punto donde se unen la parte del agua y la de la gasolina.  
**Solución:** cierra una válvula o separa las tuberías. No hay que vaciar ni limpiar nada: cada líquido sigue en su depósito.  
**Más información:** [Transporte de combustible](fuel-transport.md), [Fuentes y almacenamiento](sources-and-storage.md)

## Los jugadores ven cosas distintas

**Síntoma:** una acción tarda, se rechaza o no se ve igual para todos.  
**Causas posibles:** el servidor ha rechazado la acción; un jugador se desconectó mientras se revisaba la fontanería de un edificio del mapa; no todos tenéis la misma versión del mod.  
**Qué revisar:** confirma que todos tenéis la misma versión y lee el mensaje que haya mostrado el servidor.  
**Solución:** vuelve a conectarte y repite la acción después de corregir lo que indique el mensaje. Si una revisión de edificio se interrumpió, el servidor la cierra y devuelve lo que corresponda la próxima vez que se ejecute.  
**Más información:** [Compatibilidad](compatibility.md), [Inspeccionar la fontanería de un edificio](building-plumbing.md)

Si nada de esto explica el problema, avísanos en [GitHub Issues](https://github.com/carthon/WaterPipesModPZ/issues) e incluye la versión del juego y del mod, si juegas en multijugador, las opciones que hayas cambiado, los pasos para reproducirlo, los registros y las capturas.
