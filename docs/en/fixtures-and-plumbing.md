# Fixtures and plumbing

## Supported objects

Water Pipes recognizes objects the game marks as water-pipe fixtures, objects that declare an external water source, and the three Build 42 washer classes. In practice this covers:

| Group | Examples | Network role |
|---|---|---|
| Taps and basins | Sinks and washbasins | Drink, wash, fill, and transfer from the network |
| Bathroom fixtures | Showers, bathtubs, toilets | Water consumer |
| Appliances | Washing machine, washer-dryer, stacked washer-dryer | Supplies the appliance's own water container |
| Compatible mod fixtures | For example, Take A Bath And Shower | External-water consumer when the mod exposes the expected flags |

This is capability-based rather than a fixed sprite list, so compatible modded fixtures may work without being named individually.

## Connecting one fixture

1. Build a floor pipe on the fixture's **own tile**.
2. Carry a usable Pipe Wrench.
3. Right-click the fixture and select **Plumb**.
4. Test the normal fixture action and use **Show pipe network** if it has no supply.
5. Select **Unplumb** to restore the fixture's original fluid and town-water state.

Removing its own pipe also disconnects it; a break farther along merely cuts its supply. While town water remains live and the related sandbox option is enabled, a plumbed indoor fixture can feed clean water and mains pressure back into the network.

!!! note "Washing-machine interface"
    A connected washer remains operable through its inventory window. Build 42 may hide the redundant **Turn On** entry from the tile's right-click menu once the washer's fluid container contains water.

<!-- SCREENSHOT: 19-fixture-plumb-menu.png — Pipe on a sink tile with the Plumb context action visible. -->
<!-- SCREENSHOT: 20-supported-fixtures.png — Sink, shower, toilet and washing machine connected to one network. -->

