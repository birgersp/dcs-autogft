---
-- @type autogft_TaskForce
-- @field #number country
-- @field #list<#string> stagingZones
-- @field #list<#autogft_ControlZone> controlZones
-- @field #number speed
-- @field #string formation
-- @field #list<#autogft_UnitSpec> unitSpecs
-- @field #list<DCSGroup#Group> groups
-- @field #string target
autogft_TaskForce = {}
autogft_TaskForce.__index = autogft_TaskForce

---
-- @param #autogft_TaskForce self
-- @param #number country
-- @param #list<#string> stagingZones
-- @param #list<#string> controlZones
-- @return #autogft_TaskForce
function autogft_TaskForce:new(country, stagingZones, controlZones)

  local function verifyZoneExists(name)
    assert(trigger.misc.getZone(name) ~= nil, "Zone \""..name.."\" does not exist in this mission.")
  end

  self = setmetatable({}, autogft_TaskForce)
  self.country = country
  for k,v in pairs(stagingZones) do verifyZoneExists(v) end
  self.stagingZones = stagingZones
  self.unitSpecs = {}
  self.controlZones = {}
  self.speed = 100
  self.formation = "cone"
  for i = 1, #controlZones do
    local controlZone = controlZones[i]
    verifyZoneExists(controlZone)
    self.controlZones[#self.controlZones + 1] = autogft_ControlZone:new(controlZone)
  end
  self.groups = {}
  self.target = controlZones[1]
  return self
end

---
-- @param #autogft_TaskForce self
-- @param #number count
-- @param #string type
-- @return #autogft_TaskForce
function autogft_TaskForce:addUnitSpec(count, type)
  self.unitSpecs[#self.unitSpecs + 1] = autogft_UnitSpec:new(count, type)
  return self
end

---
-- @param #autogft_TaskForce self
-- @return #autogft_TaskForce
function autogft_TaskForce:cleanGroups()
  local newGroups = {}
  for i = 1, #self.groups do
    local group = self.groups[i]
    if #group:getUnits() > 0 then newGroups[#newGroups + 1] = group end
  end
  self.groups = newGroups
  return self
end

---
-- @param #autogft_TaskForce self
-- @param #boolean spawn
-- @return #autogft_TaskForce
function autogft_TaskForce:reinforce(spawn)
  -- If not spawning, use friendly vehicles for staging
  local stagedUnits = {}
  local addedUnitIds = {}
  if not spawn then
    stagedUnits = autogft.getUnitsInZones(coalition.getCountryCoalition(self.country), self.stagingZones)
  end
  local spawnedUnitCount = 0
  self:cleanGroups()
  local desiredUnits = {}
  for unitSpecIndex = 1, #self.unitSpecs do

    -- Determine desired replacement units of this spec
    local unitSpec = self.unitSpecs[unitSpecIndex]
    if desiredUnits[unitSpec.type] == nil then
      desiredUnits[unitSpec.type] = 0
    end
    desiredUnits[unitSpec.type] = desiredUnits[unitSpec.type] + unitSpec.count
    local replacements = desiredUnits[unitSpec.type]
    for groupIndex = 1, #self.groups do
      replacements = replacements - autogft.countUnitsOfType(self.groups[groupIndex]:getUnits(), unitSpec.type)
    end

    -- Get replacements
    if replacements <= 0 then return self end

    local groupName
    local units = {}
    local function addUnit(type, name, id, x, y, heading)
      units[#units + 1] = {
        ["type"] = type,
        ["transportable"] =
        {
          ["randomTransportable"] = false,
        },
        ["x"] = x,
        ["y"] = y,
        ["heading"] = heading,
        ["name"] = name,
        ["unitId"] = id,
        ["skill"] = "High",
        ["playerCanDrive"] = true
      }
    end

    local replacedUnits = 0

    -- Assign units to group
    if spawn then
      local spawnZoneIndex = math.random(#self.stagingZones)
      local spawnZone = trigger.misc.getZone(self.stagingZones[spawnZoneIndex])

      while replacedUnits < replacements do

        local id = autogft.lastCreatedUnitId
        local name = "Unit no " .. autogft.lastCreatedUnitId
        local x = spawnZone.point.x + 15 * spawnedUnitCount
        local y = spawnZone.point.z - 15 * spawnedUnitCount
        autogft.lastCreatedUnitId = autogft.lastCreatedUnitId + 1
        addUnit(unitSpec.type, name, id, x, y, 0)

        spawnedUnitCount = spawnedUnitCount + 1
        replacedUnits = replacedUnits + 1
      end
    else
      local stagedUnitIndex = 1
      while replacedUnits < replacements and stagedUnitIndex < #stagedUnits do
        local unit = stagedUnits[stagedUnitIndex]
        if unit:isExist()
          and unit:getTypeName() == unitSpec.type
          and not self:containsUnit(unit)
          and not autogft.contains(addedUnitIds, unit:getID()) then
          local x = unit:getPosition().p.x
          local y = unit:getPosition().p.z
          -- TODO: (somehow) use heading from unit
          local heading = 0
          addUnit(unitSpec.type, unit:getName(), unit:getID(), x, y, heading)
          addedUnitIds[#addedUnitIds + 1] = unit:getID()
          replacedUnits = replacedUnits + 1
        end
        stagedUnitIndex = stagedUnitIndex + 1
      end
    end

    if #units > 0 then
      -- Create a group
      groupName = "Group #00" .. autogft.lastCreatedGroupId
      local groupData = {
        ["route"] = {},
        ["groupId"] = autogft.lastCreatedGroupId,
        ["units"] = units,
        ["name"] = groupName
      }
      coalition.addGroup(self.country, Group.Category.GROUND, groupData)
      autogft.lastCreatedGroupId = autogft.lastCreatedGroupId + 1

      -- Issue group to control zone
      self.groups[#self.groups + 1] = Group.getByName(groupName)
      if self.target ~= nil then
        autogft.issueGroupTo(groupName, self.target)
      end
    end
  end
  return self
end

---
-- @param #autogft_TaskForce self
-- @return #autogft_TaskForce
function autogft_TaskForce:updateTarget()
  local redVehicles = mist.makeUnitTable({'[red][vehicle]'})
  local blueVehicles = mist.makeUnitTable({'[blue][vehicle]'})

  local done = false
  local zoneIndex = 1
  while done == false and zoneIndex <= #self.controlZones do
    local zone = self.controlZones[zoneIndex]
    local newStatus = nil
    if #mist.getUnitsInZones(redVehicles, {zone.name}) > 0 then
      newStatus = coalition.side.RED
    end

    if #mist.getUnitsInZones(blueVehicles, {zone.name}) > 0 then
      if newStatus == coalition.side.RED then
        newStatus = coalition.side.NEUTRAL
      else
        newStatus = coalition.side.BLUE
      end
    end

    if newStatus ~= nil then
      zone.status = newStatus
    end

    if zone.status ~= coalition.getCountryCoalition(self.country) then
      self.target = zone.name
      done = true
    end
    zoneIndex = zoneIndex + 1
  end

  if self.target == nil then
    self.target = self.controlZones[#self.controlZones].name
  end
  return self
end

---
-- @param #autogft_TaskForce self
-- @param #string zone
-- @return #autogft_TaskForce
function autogft_TaskForce:issueTo(zone)
  self:cleanGroups()
  for i = 1, #self.groups do
    local hasExistingUnit = false
    -- Verify that the group has live units
    local units = self.groups[i]:getUnits()
    local unitIndex = 1
    while unitIndex < #units and not hasExistingUnit do
      if units[unitIndex]:isExist() then
        hasExistingUnit = true
      else
        unitIndex = unitIndex + 1
      end
    end
    if hasExistingUnit then
      autogft.issueGroupTo(self.groups[i]:getName(), self.target, self.speed, self.formation)
    end
  end
  return self
end

---
-- @param #autogft_TaskForce self
-- @return #autogft_TaskForce
function autogft_TaskForce:moveToTarget()
  self:issueTo(self.target)
  return self
end

---
-- @param #autogft_TaskForce self
-- @param #number timeIntervalSec
-- @return #autogft_TaskForce
function autogft_TaskForce:enableObjectiveUpdateTimer(timeIntervalSec)
  local function autoIssue()
    self:updateTarget()
    self:cleanGroups()
    self:moveToTarget()
    autogft.scheduleFunction(autoIssue, timeIntervalSec)
  end
  autogft.scheduleFunction(autoIssue, timeIntervalSec)
  return self
end

---
-- @param #autogft_TaskForce self
-- @param #number timeIntervalSec
-- @param #boolean spawn
-- @param #number maxReinforcementTime (optional)
-- @return #autogft_TaskForce
function autogft_TaskForce:enableReinforcementTimer(timeIntervalSec, spawn, maxReinforcementTime)
  local keepReinforcing = true
  local function reinforce()
    if keepReinforcing then
      self:reinforce(spawn)
      autogft.scheduleFunction(reinforce, timeIntervalSec)
    end
  end

  autogft.scheduleFunction(reinforce, timeIntervalSec)

  if maxReinforcementTime ~= nil and maxReinforcementTime > 0 then
    local function killTimer()
      keepReinforcing = false
    end
    autogft.scheduleFunction(killTimer, maxReinforcementTime)
  end
  return self
end

---
-- @param #autogft_TaskForce self
-- @return #autogft_TaskForce
function autogft_TaskForce:enableDefaultTimers()
  self:enableObjectiveUpdateTimer(autogft.DEFAULT_AUTO_ISSUE_DELAY)
  self:enableRespawnTimer(autogft.DEFAULT_AUTO_REINFORCE_DELAY)
  return self
end

---
-- @param #autogft_TaskForce self
-- @param DCSUnit#Unit unit
-- @return #boolean
function autogft_TaskForce:containsUnit(unit)
  for groupIndex = 1, #self.groups do
    local units = self.groups[groupIndex]:getUnits()
    for unitIndex = 1, #units do
      if units[unitIndex]:getID() == unit:getID() then return true end
    end
  end
  return false
end