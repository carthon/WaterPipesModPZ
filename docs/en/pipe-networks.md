# Pipe networks

## Pipe recipes

| Build entry | Requirements | Consumed |
|---|---|---|
| Fluid Pipe | Pipe Wrench | 1 Metal Pipe **or** 1 fired Clay Pipe Segment |
| Vertical Fluid Pipe | Pipe Wrench | 1 Metal Pipe **or** 1 fired Clay Pipe Segment |
| Concealed Fluid Pipe | Pipe Wrench | 1 pipe plus 1 full supported bucket of prepared clay cement or concrete |
| Concealed Vertical Fluid Pipe | Pipe Wrench | 1 pipe plus 1 full supported bucket of prepared clay cement or concrete |

The wrench is kept. Ordinary builds have no skill requirement. A Metal Pipe can also be forged from charcoal plus half and quarter iron-bar stock using a hammer, tongs or pliers, and a suitable punch at a primitive forge.

!!! note "Cement consumption"
    Each concealed pipe consumes one complete prepared bucket, so one bucket builds one pipe tile. The accepted variants are Clay Cement and Concrete in standard or carved buckets.

## Placement and connection

Floor pipes auto-tile into ends, straights, corners, T-junctions, and crosses. Only one floor pipe can occupy a tile. Rotate fixed-axis devices with **R** before placement. Vertical pipes mount on north or west walls and link floor pipes across levels; a tile may hold a floor pipe and both wall-edge risers.

Concealed variants have the same network behavior but become invisible after construction. Use **Show pipe network** on any visible or concealed pipe to reveal the connected network temporarily; use **Hide pipe network** to clear it early.

<!-- SCREENSHOT: 03-pipe-shapes.png — Ends, straight, corner, T-junction and cross produced by automatic connections. -->
<!-- SCREENSHOT: 04-vertical-pipe-floors.png — Vertical pipe linking two floors on a north or west wall. -->
<!-- SCREENSHOT: 05-concealed-pipes-overlay.png — Concealed run hidden normally and revealed by Show pipe network. -->

## Dismantling and recovery

Use the game's **Disassemble** action rather than the moveable-object tool.

- A hand-built metal pipe has a 90% chance to return one Metal Pipe.
- A clay pipe returns nothing: the fired segment is spent when laid.
- Concealed pipe revealed by **Plumb this building** returns nothing because that inspection is priced per fixture.
- Destroying a pipe with a sledgehammer, fire, or damage returns nothing.
- A valve or gauge removed with its underlying pipe returns each of its ingredients independently at 90%.

Removing the pipe from a plumbed fixture or generator's own tile disconnects it automatically.
