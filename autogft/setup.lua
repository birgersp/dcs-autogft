---
-- AI units which can be set to automatically capture target zones, advance through captured zones and be reinforced when taking casualties.
-- @module Setup

---
-- @type Setup
-- @extends class#Class
-- @field taskforce#TaskForce taskForce
-- @field #number coalition
-- @field #number speed
-- @field #number maxDistanceKM
-- @field #boolean useRoads
-- @field #string skill
-- @field #number reinforcementTimerId
-- @field #number stopReinforcementTimerId
-- @field #number advancementTimerId
-- @field group#Group lastAddedGroup
autogft_Setup = autogft_Class:create()

---
-- Creates a new task force instance.
-- @param #Setup self
-- @return #Setup This instance (self)
function autogft_Setup:new()

  self = self:createInstance()
  self.taskForce = autogft_TaskForce:new()
  self.coalition = nil
  self.speed = 9999
  self.maxDistanceKM = 10
  self.useRoads = false
  self.reinforcementTimerId = nil
  self.advancementTimerId = nil
  self.lastAddedGroup = nil

  local function autoInitialize()
    self:autoInitialize()
  end
  autogft.scheduleFunction(autoInitialize, 2)

  return self
end

---
-- Specifies the task force to stop using roads when advancing through the next tasks that are added.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:stopUsingRoads()
  self.useRoads = false
  return self
end

---
-- Specifies the task force to use roads when advancing through the next tasks that are added.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:startUsingRoads()
  self.useRoads = true
  return self
end

---
-- Sets the maximum time reinforcements will keep coming.
-- @param #Setup self
-- @param #number time Time [seconds] until reinforcements will stop coming
-- @return #Setup
function autogft_Setup:setReinforceTimerMax(time)

  if self.stopReinforcementTimerId then
    timer.removeFunction(self.stopReinforcementTimerId)
  end

  local function killTimer()
    self:stopReinforcing()
  end
  self.stopReinforcementTimerId = autogft.scheduleFunction(killTimer, time)

  return self
end

---
-- Automatically initializes the task force by starting timers (if not started) and adding groups and units (if not added).
-- Default reinforcement timer intervals is 600 seconds. Default advancement timer intervals is 300 seconds.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:autoInitialize()

  if not self.coalition then
    local unitsInBases = autogft.getUnitsInZones(coalition.side.RED, self.taskForce.reinforcer.baseZones)
    if #unitsInBases == 0 then
      unitsInBases = autogft.getUnitsInZones(coalition.side.BLUE, self.taskForce.reinforcer.baseZones)
    end
    assert(#unitsInBases > 0, "Could not determine task force coalition")
    self:setCountry(unitsInBases[1]:getCountry())
  end

  if self.taskForce.reinforcer:instanceOf(autogft_SpecificUnitReinforcer) then
    if self.taskForce.reinforcer.groupsUnitSpecs.length <= 0 then
      self:autoAddUnitLayoutFromBases()
    end
  end

  if #self.taskForce.reinforcer.baseZones > 0 then
    if not self.reinforcementTimerId then
      self:setReinforceTimer(600)
    end
  end

  if not self.advancementTimerId then
    self:setAdvancementTimer(300)
  end

  return self
end

---
-- Automatically adds groups and units.
-- Determines which groups and units that should be added to the task force by looking at a list of units and copying the layout.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:autoAddUnitLayout(units)

  if not self.country then
    self:setCountry(units[1]:getCountry())
  end

  -- Create a table of groups {group = {type = count}}
  local groupUnits = {}

  -- Iterate through own base units
  for _, unit in pairs(units) do
    local dcsGroupId = unit:getGroup():getID()

    -- Check if table has this group
    if not groupUnits[dcsGroupId] then
      groupUnits[dcsGroupId] = {}
    end

    -- Check if group has this type
    local typeName = unit:getTypeName()
    if not groupUnits[dcsGroupId][typeName] then
      groupUnits[dcsGroupId][typeName] = 0
    end

    -- Count the number of units in this group of that type
    groupUnits[dcsGroupId][typeName] = groupUnits[dcsGroupId][typeName] + 1
  end

  -- Iterate through the table of groups, add groups and units
  for _, group in pairs(groupUnits) do
    self:addGroup()
    for type, count in pairs(group) do
      self:addUnits(count, type)
    end
  end

  return self
end

---
-- Looks through base zones for units and attempts to add the same layout to the task force (by invoking ${Setup.autoAddUnitLayout})
-- @param #Setup self
-- @return #Setup
function autogft_Setup:autoAddUnitLayoutFromBases()

  -- Determine coalition based on units in base zones
  local ownUnitsInBases = autogft.getUnitsInZones(self.coalition, self.taskForce.reinforcer.baseZones)

  if #ownUnitsInBases > 0 then
    self:autoAddUnitLayout(ownUnitsInBases)
  end

  return self
end

---
-- Stops the advancement timer
-- @param #Setup self
-- @return #Setup
function autogft_Setup:stopAdvancementTimer()
  if self.advancementTimerId then
    timer.removeFunction(self.advancementTimerId)
    self.advancementTimerId = nil
  end
  return self
end

---
-- Adds an intermidiate zone task (see @{task#taskTypes.INTERMIDIATE}).
-- @param #Setup self
-- @param #string zoneName
-- @return #Setup
function autogft_Setup:addIntermidiateZone(zoneName)
  return self:addTask(autogft_CaptureTask:new(zoneName, self.coalition))
end

---
-- Adds a task to the task force
-- @param #Setup self
-- @param task#Task task
-- @return #Setup
function autogft_Setup:addTask(task)
  task.useRoads = self.useRoads
  task.speed = self.speed
  self.taskForce.taskSequence:addTask(task)
  return self
end

---
-- Adds another group specification to the task force.
-- After a group is added, use @{#Setup.addUnits} to add units.
-- See "unit-types" for a complete list of available unit types.
-- @param #Setup self
-- @return #Setup This instance (self)
function autogft_Setup:addGroup()

  self.taskForce.groups[#self.taskForce.groups + 1] = autogft_Group:new(self.taskForce.taskSequence)
  self.lastAddedGroup = self.taskForce.groups[#self.taskForce.groups]
  if self.taskForce.reinforcer:instanceOf(autogft_SpecificUnitReinforcer) then
    self.taskForce.reinforcer.groupsUnitSpecs:put(self.lastAddedGroup, {})
  end
  return self
end

---
-- Starts a timer which updates the current target zone, and issues the task force units to engage it on given time intervals.
-- Invokes @{#Setup.moveToTarget}.
-- @param #Setup self
-- @param #number timeInterval Seconds between each target update
-- @return #Setup This instance (self)
function autogft_Setup:setAdvancementTimer(timeInterval)
  self:stopAdvancementTimer()
  local function updateAndAdvance()
    self.taskForce:updateTarget()
    self.taskForce:advance()
    self.advancementTimerId = autogft.scheduleFunction(updateAndAdvance, timeInterval)
  end
  self.advancementTimerId = autogft.scheduleFunction(updateAndAdvance, timeInterval)
  return self
end

---
-- Starts a timer which reinforces the task force.
-- @param #Setup self
-- @param #number timeInterval Time [seconds] between each reinforcement
-- @param #boolean useSpawning (Optional) Specifies wether to spawn new units or use pre-existing units (default: false)
-- @return #Setup This instance (self)
function autogft_Setup:setReinforceTimer(timeInterval)
  self:stopReinforcing()

  assert(#self.taskForce.reinforcer.baseZones > 0, "Cannot set reinforcing timer for this task force, no base zones are declared.")

  local function reinforce()
    self.taskForce:reinforce()
    self.reinforcementTimerId = autogft.scheduleFunction(reinforce, timeInterval)
  end
  autogft.scheduleFunction(reinforce, 5)

  return self
end

---
-- Checks if a particular unit is present in this task force.
-- @param #Setup self
-- @param DCSUnit#Unit unit Unit in question
-- @return #boolean True if this task force contains the unit, false otherwise.
function autogft_Setup:containsUnit(unit)
  for _, group in pairs(self.taskForce.reinforcer.groupsUnitSpecs.keys) do
    if group:containsUnit(unit) then return true end
  end
  return false
end

---
-- Sets the country ID of this task force.
-- @param #Setup self
-- @param #number country Country ID
-- @return #Setup This instance (self)
function autogft_Setup:setCountry(country)
  self.coalition = coalition.getCountryCoalition(country)
  -- Update capturing tasks coalition
  for i = 1, #self.taskForce.taskSequence.tasks do
    local task = self.taskForce.taskSequence.tasks[i]
    if task:instanceOf(autogft_CaptureTask) then
      task.coalition = self.coalition
    end
  end
  -- Update reinforcer
  self.taskForce.reinforcer:setCountryID(country)
  return self
end

---
-- Adds a base zone to the task force, used for reinforcing (spawning or staging area).
-- @param #Setup self
-- @param #string zoneName Name of base zone
-- @return #Setup This instance (self)
function autogft_Setup:addBaseZone(zoneName)
  self.taskForce.reinforcer:addBaseZone(zoneName)
  return self
end

---
-- Adds a control zone task (see @{task#taskTypes.CONTROL}).
-- @param #Setup self
-- @param #string zoneName Name of target zone
-- @return #Setup This instance (self)
function autogft_Setup:addControlZone(zoneName)
  return self:addTask(autogft_ControlTask:new(zoneName, self.coalition))
end

---
-- Sets the skill of the task force reinforcement units.
-- @param #Setup self
-- @param #string skill New skill
-- @return #Setup This instance (self)
function autogft_Setup:setSkill(skill)
  self.skill = skill
  return self
end

---
-- Sets the maximum distance of unit routes (see @{#Setup.maxDistanceKM}).
-- If set, this number constrains how far groups of the task force will move between each move command (advancement).
-- When units are moving towards a target, units will stop at this distance and wait for the next movement command.
-- This prevents lag when computing routes over long distances.
-- @param #Setup self
-- @param #number maxDistanceKM Maximum distance (kilometres)
-- @return #Setup This instance (self)
function autogft_Setup:setMaxRouteDistance(maxDistanceKM)
  self.maxDistanceKM = maxDistanceKM
  return self
end

---
-- Sets the desired speed of the task force units when advancing (see @{#Setup.speed}).
-- @param #Setup self
-- @param #boolean speed New speed (in knots)
-- @return #Setup This instance (self)
function autogft_Setup:setSpeed(speed)
  self.speed = speed
  if #self.taskForce.taskSequence.tasks > 0 then self.taskForce.taskSequence.tasks[#self.taskForce.taskSequence.tasks].speed = self.speed end
  return self
end

---
-- Scans the map once for any pre-existing units to control in this task force.
-- Groups with name starting with the scan prefix will be considered.
-- A task force will only take control of units according to the task force unit specification.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:scanUnits(groupNamePrefix)

  local coalitionGroups = {
    coalition.getGroups(coalition.side.BLUE),
    coalition.getGroups(coalition.side.RED)
  }

  local availableUnits = {}

  local coalition = 1
  while coalition <= #coalitionGroups and #availableUnits == 0 do
    for _, group in pairs(coalitionGroups[coalition]) do
      if group:getName():find(groupNamePrefix) == 1 then
        local units = group:getUnits()
        for unitIndex = 1, #units do
          availableUnits[#availableUnits + 1] = units[unitIndex]
        end
      end
    end
    coalition = coalition + 1
  end

  if #availableUnits > 0 then
    if not self.country then
      self:setCountry(availableUnits[1]:getCountry())
    end
    if self.taskForce.reinforcer.groupsUnitSpecs.length <= 0 then
      self:autoAddUnitLayout(availableUnits)
    end
    self.taskForce.reinforcer:reinforceFromUnits(availableUnits)
  end

  return self
end

---
-- Stops the reinforcing/respawning timers.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:stopReinforcing()

  if self.reinforcementTimerId then
    timer.removeFunction(self.reinforcementTimerId)
    self.reinforcementTimerId = nil
  end

  if self.stopReinforcementTimerId then
    timer.removeFunction(self.stopReinforcementTimerId)
    self.stopReinforcementTimerId = nil
  end

  return self
end

---
-- Adds unit specifications to the most recently added group (see @{#Setup.addGroup}) of the task force.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:addUnits(count, type)
  assert(self.taskForce.reinforcer:instanceOf(autogft_SpecificUnitReinforcer), "Cannot add units with this function to this type of reinforcer")
  if not self.lastAddedGroup then self:addGroup() end
  local unitSpecs = self.taskForce.reinforcer.groupsUnitSpecs:get(self.lastAddedGroup)
  unitSpecs[#unitSpecs + 1] = autogft_UnitSpec:new(count, type)
  return self
end

---
-- Disables respawning of units. Sets the task force to only use pre-existing units when reinforcing. If invoked, always invoke this before units are added.
-- @param #Setup self
-- @return #Setup
function autogft_Setup:useStaging()
  local baseMessage = "Cannot change task force reinforcing policy after base zones have been added."
  assert(#self.taskForce.reinforcer.baseZones == 0, baseMessage .. " Invoke \"useStaging\" before adding base zones.")
  if self.taskForce.reinforcer:instanceOf(autogft_SpecificUnitReinforcer) then
    assert(self.taskForce.reinforcer.groupsUnitSpecs.length == 0, baseMessage .. " Invoke \"useStaging\" before add units.")
  end
  self.taskForce.reinforcer = autogft_SelectingReinforcer:new()
  return self
end
