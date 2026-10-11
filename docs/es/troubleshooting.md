# Resolución de problemas

Usa esta página para diagnosticar una red ya construida. Para dudas generales, empieza por [Preguntas frecuentes](faq.md) o [Ejemplos prácticos](practical-examples.md).

## Diagnóstico general paso a paso

1. Confirma Project Zomboid 42.15+, Water Pipes v0.10.0 y la misma versión en servidor/clientes.
2. Usa **Mostrar red de tuberías** y sigue toda la ruta.
3. Comprueba una tubería en la propia casilla de cada extremo y una vertical en cada cambio de planta.
4. Revisa válvulas cerradas, orientación del Enrutador y límites de presión.
5. Comprueba que los depósitos contengan un solo líquido correcto y no estén vacíos ni mezclados.
6. Lee la presión con **Ver estado de la bomba**, un Manómetro o **Comprobar emisor de riego**.
7. Revisa electricidad e interruptor manual de bombas y purificadores.
8. Revisa las opciones de Sandbox de Water Pipes en esa partida.
9. En multijugador, reconecta, repite una vez y confirma versiones idénticas.
10. Si continúa, guarda una captura de la red/estado y las líneas relevantes de `console.txt`.

## La red no conecta

**Síntoma:** El extremo no aparece en la superposición o se comporta como otra red.  
**Posibles causas:** Tubería adyacente, falta una vertical, válvula cerrada o hueco.  
**Comprobaciones:** Revela toda la ruta y revisa las piezas verticales de pared.  
**Solución:** Corrige la casilla o transición ausente, o abre la válvula aislante.  
**Relacionado:** [Redes de tuberías](pipe-networks.md)

## Un aparato no tiene suministro

**Síntoma:** Un aparato instalado aparece vacío.  
**Posibles causas:** No hay almacenamiento conectado; está vacío o debajo sin presión; líquidos mezclados; rotura lejana.  
**Comprobaciones:** Revisa recipientes, superposición, válvulas y presión local.  
**Solución:** Restaura una ruta y suministro válidos. Si hay una mezcla, aísla los líquidos; el procedimiento completo de recuperación sigue pendiente de verificación.  
**Relacionado:** [Fuentes y almacenamiento](sources-and-storage.md), [Aparatos](fixtures-and-plumbing.md)

## La bomba no mueve agua

**Síntoma:** No llena recipientes o no hay presión.  
**Posibles causas:** Apagada; sin electricidad; fuente fuera del límite de aspiración; destino lleno; fuente natural no válida.  
**Comprobaciones:** Usa **Ver estado de la bomba**.  
**Solución:** Corrige la condición indicada. Sin fuente, una bomba puede dar presión al agua almacenada, pero no crear agua.  
**Relacionado:** [Bombas y presión](pumps-and-pressure.md)

## La presión es baja o irregular

**Síntoma:** Funcionan consumidores cercanos, pero no lejanos o superiores.  
**Posibles causas:** Distancia, altura, demanda compartida, límite del enrutador o pérdida del purificador.  
**Comprobaciones:** Compara manómetros y revisa las opciones de Sandbox.  
**Solución:** Reduce demanda o distancia, divide ramales con enrutadores o añade una bomba correctamente alimentada donde lo permita el diseño.  
**Relacionado:** [Bombas y presión](pumps-and-pressure.md), [Enrutadores y válvulas](routers-and-valves.md)

## El purificador no procesa agua

**Síntoma:** No llega agua limpia a la salida.  
**Posibles causas:** Sin corriente; filtro saturado; entrada limpia o mezclada; salida llena; orientación incorrecta.  
**Comprobaciones:** Abre su ventana y revisa la entrada verde y salida roja.  
**Solución:** Restaura corriente o capacidad, repara el filtro o corrige la red de entrada.  
**Relacionado:** [Purificación](purification.md)

## El aspersor o gotero no riega

**Síntoma:** Los cultivos siguen secos.  
**Posibles causas:** Red vacía; poca presión para el aspersor; gotero reventado; ningún cultivo vivo necesita agua.  
**Comprobaciones:** Usa **Comprobar emisor de riego**.  
**Solución:** Sigue la condición indicada; repara el gotero y limita la presión anterior.  
**Relacionado:** [Riego](irrigation.md)

## Se han mezclado agua y gasolina

**Síntoma:** Los aparatos aparecen vacíos y el generador deja de repostar.  
**Posible causa:** Las redes de agua y gasolina se han unido.  
**Comprobaciones:** Revela la red y localiza la unión involuntaria.  
**Solución:** Cierra una válvula o separa las rutas de inmediato y sigue la recuperación de [Fuentes y almacenamiento](sources-and-storage.md). La acción exacta para vaciar depende del tipo de recipiente afectado.  
**Relacionado:** [Transporte de combustible](fuel-transport.md), [Fuentes y almacenamiento](sources-and-storage.md)

## El estado difiere entre jugadores

**Síntoma:** Una acción tarda, se rechaza o parece incoherente.  
**Posibles causas:** Rechazo del servidor, desconexión durante el fontanado o versiones distintas.  
**Comprobaciones:** Confirma versiones idénticas y revisa la respuesta visible del servidor.  
**Solución:** Reconecta y repite tras corregir la condición. El servidor liquida un fontanado interrumpido en la siguiente pasada.  
**Relacionado:** [Compatibilidad](compatibility.md), [Fontanear un edificio](building-plumbing.md)

Si estas comprobaciones no explican el problema, notifícalo en [GitHub Issues](https://github.com/carthon/WaterPipesModPZ/issues) con versiones, estado multijugador, ajustes, pasos, registros y capturas.
