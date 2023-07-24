local getMinTicks = function (minTickCountOrFn)
  return (type(minTickCountOrFn) == "function" and minTickCountOrFn() or minTickCountOrFn) or 0
end

local find = function (table, fn)
  for _, value in pairs(table) do
    if (fn(value)) then return value end
  end
  return nil
end

-- Main wrapper for individual state data, including initialiser and registering callbacks
local State = function (name, minTicksOrFn, onTick)
  assert(name, 'State must be assigned a name')

  local tickCount = 0
  local minTicks = getMinTicks(minTicksOrFn)

  local state = {
    name = name,
    minTicks = function() return minTicks end, -- wrap in function
    tickCount = function () return tickCount end,
    transitions = {},
    subscriptions = {},
    init = function () return end,
    exit = function (any) return end,
    setMinTicks = function (countOrFn)
      minTicksOrFn = countOrFn
    end
  }

  local initialiser = function(fn) return function (data)
    tickCount = 0
    minTicks = getMinTicks(minTicksOrFn)
    if (fn) then fn(data) end
    for _, callback in pairs(state.subscriptions) do
      callback(data)
    end
    end
  end

  state.init = initialiser()

  -- override initialisation callback
  state.onInit = function(onInit)
    state.init = initialiser(onInit)
  end

  state.tick = function ()
    tickCount = tickCount + 1
    if onTick then onTick() end
  end

  -- override tick callback
  state.onTick = function(fn)
    onTick = fn
  end

  return state
end

local StateMachine = function (initialState)
  local states = {
    [initialState] = State(initialState),
  }

  -- Subscriptions
  local onTicks = {}

  -- states used by the monad when building state graph
  local homeState = states[initialState]
  local destState = homeState
  local currentStateName = initialState

  local machine = {
    states = states,
    currentState = function () return currentStateName end,
  }

  local when = function (machine)
    return function (predicate)
      assert(homeState.name ~= destState.name, 'Cannot transition to same state: ' .. destState.name)

      table.insert(homeState.transitions, { predicate = predicate, state = destState.name })
      return machine
    end
  end

  machine.transitionTo = function (stateName)
    assert(homeState.name ~= stateName, 'Cannot transition to same state: ' .. stateName)
    destState = states[stateName]

    if not destState then
      destState = State(stateName)
      states[stateName] = destState
    end

    return machine
  end

  machine.when = when(machine)
  machine.orWhen = when(machine)
  machine.andThen = function (fn)
    destState.onInit(fn)
    return machine
  end
  machine.tick = function (fn)
    destState.onTick(fn)
    return machine
  end
  machine.exit = function (fn)
    destState.exit = fn
    return machine
  end
  machine.forAtLeast = function (tickCountOrFn)
    destState.setMinTicks(tickCountOrFn)
    return machine
  end
  machine.state = function (stateName)
    local nominatedState = states[stateName]
    assert(nominatedState, 'No state found with name "' .. stateName)

    homeState, destState = nominatedState, nominatedState
    return machine
  end

  machine.init = function ()
    states[initialState].init()
    machine.init = nil
    return machine
  end

  machine.process = function (data)
    -- Make machine.init() optional, if we don't care about
    -- initialising in a separate step
    if machine.init then machine.init() end

    local currentState = states[currentStateName]
    local tickCount, minTicks, transitions = currentState.tickCount, currentState.minTicks, currentState.transitions

    local transition = find(transitions, function (transition)
      return transition.predicate(data)
    end)
    if (transition and tickCount() >= minTicks()) then
      currentState.exit(data)

      local nextState = states[transition.state]
      assert(nextState, 'No state found with name ' .. transition.state)
      nextState.init(data)
      currentStateName = nextState.name
    else
      currentState.tick(data)
      for _, callback in pairs(onTicks) do
        callback(data)
      end
    end
    return machine
  end

  machine.on = function (stateName, fn)
    if (stateName == 'tick') then
      table.insert(onTicks, fn)
      return machine
    end

    local targetState = states[stateName]
    assert(targetState, 'Cannot subscribe to state "' .. stateName .. '" because no state with that name exists.')

    table.insert(targetState.subscriptions, fn)
    return machine
  end

  return machine
end

return StateMachine