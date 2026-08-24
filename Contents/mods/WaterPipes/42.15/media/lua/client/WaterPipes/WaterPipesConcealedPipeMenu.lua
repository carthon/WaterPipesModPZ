require "WaterPipes/PipeObjectUtils"
require "WaterPipes/WaterPipeContextMenu"

-- Right-clicking a CONCEALED pipe.
--
-- A concealed pipe wears a fully transparent sprite, so the engine's object picker sees nothing worth
-- picking on its tile. ISWorldObjectContextMenu.createMenu then bails on `fetch.c == 0` and returns
-- nil, and ISMenuContextWorld.createMenu answers that nil with `or ISContextMenu.get(...)`, which calls
-- context:clear() -- wiping every mod contribution, and OnFillWorldObjectContextMenu never fired at all.
--
-- ISWorldMenuElements is the one contribution point that runs AFTER that reset, so the network options
-- are re-offered from here whenever the main pass did not add them. On a tile the engine picks normally
-- the main pass wins and this element adds nothing.

ISWorldMenuElements = ISWorldMenuElements or {}

local PipeObjectUtils = WaterPipes.PipeObjectUtils

function ISWorldMenuElements.WaterPipesNetwork()
    local self = ISMenuElement.new()

    function self.init()
    end

    -- The clicked square is in _data.squares even when nothing on it could be picked: ISMenuContextWorld
    -- resolves it from the screen coordinates and collects its objects regardless.
    local function findPipe(data)
        for _, square in ipairs(data.squares or {}) do
            local pipe = PipeObjectUtils.getPipeOnSquare(square)
            if pipe then
                return pipe
            end
        end
        return nil
    end

    local function hasOption(context, onSelect)
        for _, option in ipairs(context and context.options or {}) do
            if option.onSelect == onSelect then
                return true
            end
        end
        return false
    end

    function self.createMenu(data)
        local ContextMenu = WaterPipes and WaterPipes.ContextMenu
        if not ContextMenu or not data or not data.context or not data.player then
            return
        end
        if data.player:getVehicle() then
            return
        end

        local pipe = findPipe(data)
        if not pipe then
            return
        end

        local context = data.context
        local addShow = not hasOption(context, ContextMenu.showNetwork)
        local addHide = #ContextMenu.highlightedObjects > 0
            and not hasOption(context, ContextMenu.hideNetwork)
        if not addShow and not addHide then
            return
        end
        if data.test then
            return true
        end

        if addShow then
            context:addOption(getText("ContextMenu_WaterPipesShowNetwork"), data.player,
                ContextMenu.showNetwork, pipe)
        end
        if addHide then
            context:addOption(getText("ContextMenu_WaterPipesHideNetwork"), data.player,
                ContextMenu.hideNetwork)
        end
        return true
    end

    return self
end
