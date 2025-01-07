local ENTITY = FindMetaTable("Entity")

function ENTITY:GetRadioOn()
    return self:GetNW2Bool("CRadio.RadioState", false)
end

function ENTITY:SetRadioOn(on)
    self:SetNW2Bool("CRadio.RadioState", on)
end

function ENTITY:GetCurrentStation()
    local name = self:GetNW2Int("CRadio.Station")

    return CRadio:GetStation(name)
end

function ENTITY:SetCurrentStation(station)
    local id = (station and station:GetID()) or nil

    self:SetNW2Int("CRadio.Station", id)
end