# Fuel transport

1. Use a dedicated container that holds **Petrol** and put a floor pipe on its own tile.
2. Build an isolated pipe route to the generator. Add a powered pump if height, distance, or demand leaves too little pressure.
3. Put the final pipe on the generator's own tile.
4. Carry a Pipe Wrench, right-click the generator, and choose **Plumb Generator**.
5. Keep the network petrol-only. The generator checks once per in-game minute.

When its tank falls below the configured threshold (25% by default), it draws toward the target (100% by default). Setting the threshold to 0 disables automatic refuelling. It only draws Petrol: an empty network or one that offers water supplies nothing. Incompatible liquids are rejected rather than mixed.

![Isolated petrol network](../assets/images/diagram-fuel-network.svg){ .wp-diagram }

- **1** Dedicated petrol storage.
- **2** Pump, when pressure is required.
- **3** Connected generator.

The dashed perimeter means this line stays isolated from water.

<!-- SCREENSHOT: 25-generator-connect-menu.png — Plumb Generator action with a pipe on the same tile. -->

Use **Unplumb Generator** to disconnect it without removing the pipe.

!!! danger
    Keep petrol and drinking-water routes separate. They cannot mix, but a shared layout is harder to inspect and does not let a generator draw water or a fixture draw petrol. Use a physical gap, closed valve, or correctly oriented router.
