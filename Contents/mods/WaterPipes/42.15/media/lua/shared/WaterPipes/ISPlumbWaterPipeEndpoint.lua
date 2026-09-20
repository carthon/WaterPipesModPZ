require "TimedActions/ISBaseTimedAction"
require "WaterPipes/EndpointPlumbing"
require "WaterPipes/EndpointObjects"
require "WaterPipes/SoundOptions"

ISPlumbWaterPipeEndpoint = ISBaseTimedAction:derive("ISPlumbWaterPipeEndpoint")

function ISPlumbWaterPipeEndpoint:isValid()
    return self.character:isEquipped(self.wrench)
        and self.endpointObject
        and self.endpointObject:getSquare() ~= nil
end

function ISPlumbWaterPipeEndpoint:update()
    self.character:faceThisObject(self.endpointObject)
    self.character:setMetabolicTarget(Metabolics.MediumWork)
end

function ISPlumbWaterPipeEndpoint:start()
    self:setActionAnim("VehicleWorkOnMid")
    self.sound = WaterPipes.SoundOptions.playOnCharacter(self.character, "RepairWithWrench")
end

function ISPlumbWaterPipeEndpoint:stop()
    WaterPipes.SoundOptions.stopOnCharacter(self.character, self.sound)
    ISBaseTimedAction.stop(self)
end

function ISPlumbWaterPipeEndpoint:perform()
    WaterPipes.SoundOptions.stopOnCharacter(self.character, self.sound)

    local square = self.endpointObject and self.endpointObject.getSquare and self.endpointObject:getSquare()
    if isClient() and square then
        -- MP: the fixture must be mutated authoritatively on the server, otherwise the client
        -- diverges (sendObjectChange errors + duplicated objects). Request it from the server.
        sendClientCommand(self.character, "WaterPipes",
            self.shouldPlumb and "plumbEndpoint" or "unplumbEndpoint",
            { x = square:getX(), y = square:getY(), z = square:getZ() })
    else
        -- Per SQUARE, the same unit the server works in: a tile carrying a sink and a washer connects
        -- as one fixture, so single player cannot end up in a state multiplayer will not reproduce.
        local EndpointPlumbing = WaterPipes.EndpointPlumbing
        local endpoints = square and WaterPipes.EndpointObjects.collectOnSquare(square)
            or { self.endpointObject }
        for _, endpoint in ipairs(endpoints) do
            if EndpointPlumbing.isPlumbed(endpoint) ~= self.shouldPlumb then
                if self.shouldPlumb then
                    EndpointPlumbing.plumb(endpoint)
                else
                    EndpointPlumbing.unplumb(endpoint)
                end
            end
        end
    end

    ISBaseTimedAction.perform(self)
end

function ISPlumbWaterPipeEndpoint:new(character, endpointObject, wrench, shouldPlumb)
    local o = ISBaseTimedAction.new(self, character)
    o.character = character
    o.endpointObject = endpointObject
    o.wrench = wrench
    o.shouldPlumb = shouldPlumb ~= false
    o.maxTime = character:isTimedActionInstant() and 1 or 100
    return o
end
