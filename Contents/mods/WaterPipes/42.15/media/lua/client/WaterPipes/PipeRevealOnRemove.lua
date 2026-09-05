-- Reveal concealed pipes while a DESTROY or MOVEABLE cursor is active, so the otherwise-invisible pipe
-- shows up as a target instead of an empty-looking tile. Purely client-cosmetic: it flips the sprite
-- via PipeAutotile.revealPipe and restores it with rehidePipe. Nothing is transmitted.

require "WaterPipes/PipeObjectUtils"
require "WaterPipes/PipeAutotile"

WaterPipes = WaterPipes or {}
local PipeObjectUtils = WaterPipes.PipeObjectUtils
local PipeAutotile = WaterPipes.PipeAutotile

local REVEAL_RADIUS = 12   -- tiles around the player scanned while a removal cursor is up
local THROTTLE_TICKS = 8   -- only re-check every N ticks (the scan only runs during removal mode)

local tickCounter = 0
local revealed = {}        -- [pipeObject] = true, currently temporarily revealed

-- The mouse cursor is one of the vanilla removal tools (both derive their Type string).
local function isRemovalCursor(drag)
    if not drag then
        return false
    end
    local cursorType = drag.Type
    return cursorType == "ISDestroyCursor" or cursorType == "ISMoveableCursor"
end

-- Restore a pipe to concealed, but only if it's still a live world object.
local function safeReconceal(pipe)
    if pipe and pipe.getSquare and pipe:getSquare() then
        PipeAutotile.rehidePipe(pipe)
    end
end

local function concealAll()
    local any = false
    for pipe in pairs(revealed) do
        safeReconceal(pipe)
        any = true
    end
    if any then
        revealed = {}
    end
end

local function revealAround(playerObj)
    local cell = getCell()
    if not cell then
        return
    end

    local px = math.floor(playerObj:getX())
    local py = math.floor(playerObj:getY())
    local pz = math.floor(playerObj:getZ())
    local nowRevealed = {}

    for dx = -REVEAL_RADIUS, REVEAL_RADIUS do
        for dy = -REVEAL_RADIUS, REVEAL_RADIUS do
            local square = cell:getGridSquare(px + dx, py + dy, pz)
            if square then
                for _, pipe in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
                    if PipeAutotile.isPipeHidden(pipe) then
                        PipeAutotile.revealPipe(pipe)
                        nowRevealed[pipe] = true
                    end
                end
            end
        end
    end

    -- Re-conceal anything we had revealed that is no longer in range.
    for pipe in pairs(revealed) do
        if not nowRevealed[pipe] then
            safeReconceal(pipe)
        end
    end
    revealed = nowRevealed
end

local function onTick()
    tickCounter = tickCounter + 1
    if tickCounter < THROTTLE_TICKS then
        return
    end
    tickCounter = 0

    local playerObj = getPlayer()
    local cell = getCell()
    local drag = (playerObj and cell and cell.getDrag)
        and cell:getDrag(playerObj:getPlayerNum())
        or nil

    if playerObj and isRemovalCursor(drag) then
        revealAround(playerObj)
    else
        concealAll()
    end
end

if Events and Events.OnTick then
    Events.OnTick.Add(onTick)
end
