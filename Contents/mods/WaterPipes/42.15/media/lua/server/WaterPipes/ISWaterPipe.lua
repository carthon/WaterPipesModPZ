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
    }
end

function ISWaterPipe:getPlacementMode()
    if self.nSprite == 2 then
        return {
            surface = Constants.PIPE_SURFACE_FLOOR,
            axis = Constants.PIPE_AXIS_NS,
            north = true,
            sprite = Constants.PIPE_FLOOR_NORTH_SPRITE,
        }
    end

    if self.nSprite == 3 then
        return {
            surface = Constants.PIPE_SURFACE_WALL,
            axis = Constants.PIPE_AXIS_EW,
            north = false,
            sprite = Constants.PIPE_WALL_WEST_SPRITE,
        }
    end

    if self.nSprite == 4 then
        return {
            surface = Constants.PIPE_SURFACE_WALL,
            axis = Constants.PIPE_AXIS_NS,
            north = true,
            sprite = Constants.PIPE_WALL_NORTH_SPRITE,
        }
    end

    return {
        surface = Constants.PIPE_SURFACE_FLOOR,
        axis = Constants.PIPE_AXIS_EW,
        north = false,
        sprite = Constants.PIPE_FLOOR_WEST_SPRITE,
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
    self.isWallLike = placement.surface == Constants.PIPE_SURFACE_WALL
    self.buildLow = not self.isWallLike
    self.modData[Constants.PIPE_MODDATA_KEY] = true
    self.modData[Constants.PIPE_SURFACE_MODDATA_KEY] = placement.surface
    self.modData[Constants.PIPE_AXIS_MODDATA_KEY] = placement.axis

    return placement
end

function ISWaterPipe:getSprite()
    local placement = self:applyPlacementMode()
    return placement.sprite
end

function ISWaterPipe:canPlaceOnSquare(square)
    local placement = self:applyPlacementMode()
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
