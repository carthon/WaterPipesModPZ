# Inspecting a building's plumbing

World-generated buildings are treated as if their plumbing already existed. To avoid generating pipe networks for every building on the map, Water Pipes materializes that hidden installation only when you choose **Plumb this building**. In practical terms, the action **inspects and reveals the building's existing plumbing**; it is not a tool for automatically installing pipes in a player-built structure.

When inspected, the mod creates a concealed, loop-free pipe tree from the tile you click to every reachable unconnected fixture in the same building. It reuses any compatible pipes already present, crosses floors only where a north or west wall can carry a riser, and never places a concealed segment over another pipe.

!!! warning "World buildings only"
    **Plumb this building does not auto-plumb player-built buildings.** Build those networks manually with floor, concealed, and vertical pipes, then connect each fixture normally.

## Walkthrough

1. Stand inside the building with a usable Pipe Wrench.
2. Carry the required Metal Pipes: by default, one per fixture to be connected, regardless of route length.
3. Right-click a suitable floored tile and choose **Plumb this building**.
4. Review the description and start the timed action. The nearest fixtures are planned first.
5. When complete, connect the revealed tree to storage or a source and inspect it with **Show pipe network**.

One inspection can reveal at most 200 new pipe tiles and scans at most 8,000 building tiles. If the result is partial, repeat from another location. The action charges for the planned fixtures at the start and refunds the cost of any fixture it fails to reach. Plumbing already revealed remains if the action is interrupted. Revealed concealed pipe gives no material back when dismantled.

<!-- SCREENSHOT: 21-building-before.png — World-generated multi-room house before its existing plumbing is inspected. -->
<!-- SCREENSHOT: 22-building-plumb-action.png — Plumb this building inspection action and its cost description. -->
<!-- SCREENSHOT: 23-building-after-overlay.png — Previously hidden plumbing visible in the network overlay after inspection. -->

## Result messages

| Message or reason | Meaning and response |
|---|---|
| Not inside a building | Click a floored tile recognized as part of an `IsoBuilding` |
| Nothing here to plumb | No compatible unconnected fixture was found |
| Already plumbed | Every detected fixture is already connected |
| Building too large | Only the nearest scanned area was inspected; repeat elsewhere |
| No route | Solid layout or existing network prevents a safe path |
| No wall to reach its floor | Add or choose a route with a north/west wall riser |
| Would close a loop | The connection would create a ring, so it is skipped deliberately |
| Over distance limit | The 200-new-tile pass limit was reached; repeat from another spot |
| Server stopped the work | In multiplayer, the server rejected stale, invalid, or underfunded work |

In multiplayer, the inspection is server-authoritative. The client waits for approval before fixtures are connected, and the cost of any connection that cannot be completed is refunded when the pass closes.

