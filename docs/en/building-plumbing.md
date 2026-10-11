# Plumbing a building

**Plumb this building** generates a concealed, loop-free pipe tree from the tile you click to every reachable unplumbed fixture in the same building. It reuses existing pipes, crosses floors only where a north or west wall can carry a riser, and never builds over an existing pipe.

## Walkthrough

1. Stand inside the building with a usable Pipe Wrench.
2. Carry the required Metal Pipes: by default, one per fixture to be connected, regardless of route length.
3. Right-click a suitable floored tile and choose **Plumb this building**.
4. Review the description and start the timed action. The nearest fixtures are planned first.
5. When complete, connect the generated tree to storage or a source and inspect it with **Show pipe network**.

One pass can lay at most 200 new pipe tiles and scans at most 8,000 building tiles. If the result is partial, repeat from another location. The action charges the planned fixtures at the start and refunds the cost of any fixture it fails to reach. Existing work remains if the action is interrupted. Generated pipe gives no material back when dismantled.

<!-- SCREENSHOT: 21-building-before.png — Unplumbed multi-room house before running the action. -->
<!-- SCREENSHOT: 22-building-plumb-action.png — Plumb this building context entry and its cost description. -->
<!-- SCREENSHOT: 23-building-after-overlay.png — Generated concealed tree revealed after completion. -->

## Result messages

| Message or reason | Meaning and response |
|---|---|
| Not inside a building | Click a floored tile recognized as part of an `IsoBuilding` |
| Nothing here to plumb | No compatible unconnected fixture was found |
| Already plumbed | Every detected fixture is already connected |
| Building too large | Only the nearest scanned area was planned; repeat elsewhere |
| No route | Solid layout or existing network prevents a safe path |
| No wall to reach its floor | Add or choose a route with a north/west wall riser |
| Would close a loop | The connection would create a ring, so it is skipped deliberately |
| Over distance limit | The 200-new-tile pass limit was reached; repeat from another spot |
| Server stopped the work | In multiplayer, the server rejected stale, invalid, or underfunded work |

Multiplayer construction is server-authoritative. The client waits for approval before connecting fixtures, and unplaced charged fixtures are refunded when the pass closes.

<!-- TODO: Verify player-built houses and multi-tile bathtubs in a live Build 42 game. -->

