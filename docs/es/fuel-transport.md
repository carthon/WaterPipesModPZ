# Transporte de combustible

1. Usa un recipiente dedicado con **Gasolina** y coloca una tubería de suelo en su propia casilla.
2. Construye una ruta aislada hasta el generador. Añade una bomba con corriente si la altura, distancia o demanda dejan poca presión.
3. Coloca la última tubería en la misma casilla del generador.
4. Lleva una Llave para tubos, haz clic derecho en el generador y elige **Instalar Generador**.
5. Mantén la red exclusiva de gasolina. El generador la comprueba una vez por minuto de juego.

Cuando su depósito baja del umbral configurado (25 % por defecto), extrae hasta el objetivo (100 % por defecto). Un umbral de 0 desactiva el repostaje automático. Solo extrae Gasolina: una red vacía o que ofrezca agua no suministra nada. Los líquidos incompatibles se rechazan en vez de mezclarse.

![Red aislada de gasolina](../assets/images/diagram-fuel-network.svg){ .wp-diagram }

- **1** Depósito exclusivo de gasolina.
- **2** Bomba, cuando hace falta presión.
- **3** Generador conectado.

El perímetro discontinuo indica que la línea permanece separada del agua.

![Acción Instalar Generador con una tubería en la casilla del generador](../assets/images/25-generator-connect-menu-cropped.png){ .wp-screenshot loading=lazy }

Usa **Desinstalar Generador** para desconectarlo sin retirar la tubería.

!!! danger
    Mantén separadas las rutas de gasolina y agua potable. No pueden mezclarse, pero una instalación compartida es más difícil de revisar y no permite que un generador extraiga agua ni que un aparato extraiga gasolina. Usa un hueco físico, una válvula cerrada o un enrutador bien orientado.
