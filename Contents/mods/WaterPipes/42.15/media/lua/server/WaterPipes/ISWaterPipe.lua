require "BuildingObjects/ISBuildingObject"
require "WaterPipes/Constants"
require "WaterPipes/PipeObjectUtils"

WaterPipes = WaterPipes or {}
WaterPipes.ISWaterPipe = ISBuildingObject:derive("ISWaterPipe")

local Constants = WaterPipes.Constants
local PipeObjectUtils = WaterPipes.PipeObjectUtils

local ISWaterPipe = WaterPipes.ISWaterPipe

local function copyPlacementData(placement)
    return {
        surface = placement.surface,
        axis = placement.axis,
        north = placement.north,
        sprite = placement.sprite,
        riser = placement.riser,
        edge = placement.edge,
    }
end

-- Cursor states: 1 = floor (auto-connects), 2 = North-wall riser, 3 = West-wall riser.
-- (PZ tiles only have N and W walls; use the neighbour tile's wall for S/E.)
local RISER_MODES = {
    [2] = { edge = "N", sprite = Constants.PIPE_WALL_RISER_N_SPRITE },
    [3] = { edge = "W", sprite = Constants.PIPE_WALL_RISER_W_SPRITE },
}
local MAX_NSPRITE = 3

function ISWaterPipe:getPlacementMode()
    local riser = RISER_MODES[self.nSprite]
    if riser then
        -- Wall cover: a separate decorative vertical drawn on the wall. It does NOT replace
        -- the floor pipe; the floor pipe on the same tile extends an arm toward this edge.
        return {
            surface = Constants.PIPE_SURFACE_WALLCOVER,
            axis = Constants.PIPE_AXIS_EW,
            north = false,
            sprite = riser.sprite,
            riser = true,
            edge = riser.edge,
        }
    end

    return {
        surface = Constants.PIPE_SURFACE_FLOOR,
        axis = Constants.PIPE_AXIS_EW,
        north = false,
        sprite = Constants.PIPE_FLOOR_WEST_SPRITE,
        riser = false,
    }
end

function ISWaterPipe:applyPlacementMode()
    local placement = copyPlacementData(self:getPlacementMode())

    self.currentPlacement = placement
    self.north = placement.north
    self.south = false
    self.east = false
    self.west = not placement.north
    self.chosenSprite = placement.sprite
    self.isWallLike = placement.riser or false
    self.buildLow = not placement.riser            -- risers are tall (climb the wall)
    self.modData[Constants.PIPE_MODDATA_KEY] = true
    self.modData[Constants.PIPE_SURFACE_MODDATA_KEY] = placement.surface
    self.modData[Constants.PIPE_AXIS_MODDATA_KEY] = placement.axis
    self.modData[Constants.PIPE_RISER_MODDATA_KEY] = placement.riser and true or nil
    self.modData[Constants.PIPE_RISER_EDGE_MODDATA_KEY] = placement.edge or nil

    return placement
end

-- Keyboard rotation cycles all 5 states (base class only supports 4).
function ISWaterPipe:rotateKey(key)
    if getCore():isKey("Rotate building", key) then
        self.nSprite = self.nSprite + 1
        if self.nSprite > MAX_NSPRITE then
            self.nSprite = 1
        end
    end
end

-- Pipes rotate with the keyboard only; ignore mouse-direction rotation.
function ISWaterPipe:rotateMouse(x, y)
end

function ISWaterPipe:getSprite()
    local placement = self:applyPlacementMode()
    return placement.sprite
end

function ISWaterPipe:canPlaceOnSquare(square)
    local placement = self:applyPlacementMode()

    -- Floor pipes auto-connect, so only one is allowed per square (any axis).
    if placement.surface == Constants.PIPE_SURFACE_FLOOR then
        for _, worldObject in ipairs(PipeObjectUtils.getPipeObjectsOnSquare(square)) do
            if PipeObjectUtils.getPipePlacement(worldObject).surface == Constants.PIPE_SURFACE_FLOOR then
                return false
            end
        end
        return true
    end

    return not PipeObjectUtils.findPipeOnSquare(square, placement.surface, placement.axis)
end

function ISWaterPipe:create(x, y, z, north, sprite)
    local cell = getWorld():getCell()
    local placement = self:applyPlacementMode()
    self.sq = cell:getGridSquare(x, y, z)
    self.javaObject = IsoThumpable.new(cell, self.sq, sprite or placement.sprite, placement.north, self)

    buildUtil.setInfo(self.javaObject, self)
    buildUtil.consumeMaterial(self)

    self.javaObject:setMaxHealth(self:getHealth())
    self.javaObject:setHealth(self.javaObject:getMaxHealth())
    self.javaObject:setBreakSound("BreakObject")

    self.sq:AddSpecialObject(self.javaObject)
    self.sq:RecalcAllWithNeighbours(true)
    self.javaObject:transmitCompleteItemToClients()

    if WaterPipes.System and (not isClient()) then
        WaterPipes.System.registerPipeAt(x, y, z)
    end
end

function ISWaterPipe:getHealth()
    return 40 + buildUtil.getWoodHealth(self)
end

function ISWaterPipe:hasTool()
    local playerObj = getSpecificPlayer(self.player)
    return playerObj and playerObj:getInventory():containsTypeRecurse(Constants.PIPE_TOOL_TYPE)
end

function ISWaterPipe:isValid(square)
    if not square then
        return false
    end

    if not self:haveMaterial(square) then
        return false
    end

    if not self:hasTool() then
        return false
    end

    if not self:canPlaceOnSquare(square) then
        return false
    end

    if square:isVehicleIntersecting() then
        return false
    end

    if buildUtil.stairIsBlockingPlacement(square, true) then
        return false
    end

    if square:getZ() > 0 and not square:connectedWithFloor() then
        return false
    end

    return true
end

function ISWaterPipe:render(x, y, z, square)
    self:applyPlacementMode()
    ISBuildingObject.render(self, x, y, z, square)
end

function ISWaterPipe:tryBuild(x, y, z)
    self:applyPlacementMode()
    ISBuildingObject.tryBuild(self, x, y, z)
end

function ISWaterPipe:new()
    local o = {}
    setmetatable(o, self)
    self.__index = self

    o:init()
    o:setSprite(Constants.PIPE_FLOOR_WEST_SPRITE)
    o:setNorthSprite(Constants.PIPE_FLOOR_NORTH_SPRITE)
    o:setEastSprite(Constants.PIPE_WALL_WEST_SPRITE)
    o:setSouthSprite(Constants.PIPE_WALL_NORTH_SPRITE)
    o.name = Constants.PIPE_OBJECT_NAME
    o.noNeedHammer = true
    o.canPassThrough = true
    o.canBarricade = false
    o.blockAllTheSquare = false
    o.canBeAlwaysPlaced = true
    o.dismantable = true
    o.buildLow = true
    o.isThumpable = false
    o.firstItem = Constants.PIPE_TOOL_TYPE
    o.modData["need:" .. Constants.PIPE_ITEM_TYPE] = "1"
    o.modData[Constants.PIPE_MODDATA_KEY] = true
    o.dragNilAfterPlace = false

    return o
end
