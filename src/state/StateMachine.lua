local ticker = function (callback)
  local count = 0
  local tick = function (data)
    if callback then callback(data) end
    count = count + 1
  end
  local tickCount = function () return count end
  return tick, tickCount
end

local find = function (table, fn)
  for _, value in pairs(table) do
    if (fn(value)) then return value end
  end
  return nil
end

local State = function (name, minTicks, onTick)
  assert(name, 'State must be assigned a name')
  local tick, tickCount = ticker(onTick)

  return {
    name = name,
    minTicks = minTicks or 0,
    tick = tick,
    tickCount = tickCount,
    transitions = {},
    subscriptions = {},
    init = function () return end,
    exit = function (any) return end,
  }
end

local StateMachine = function (initialState)
  local states = {
    [initialState] = State(initialState),
  }

  -- Subscriptions
  local onTicks = {}

  -- states used by the monad when building state graph
  local homeState = states[initialState];
  local destState = homeState;
  local currentStateName = initialState;

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
    destState.init = fn
    return machine
  end
  machine.tick = function (fn)
    destState.tick = fn
    return machine
  end
  machine.exit = function (fn)
    destState.exit = fn
    return machine
  end
  machine.forAtLeast = function (tickCount)
    destState.minTicks = tickCount
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
    return machine
  end

  machine.process = function (data)
    local currentState = states[currentStateName]
    local tickCount, minTicks, transitions = currentState.tickCount, currentState.minTicks, currentState.transitions

    local transition = find(transitions, function (transition)
      return transition.predicate(data)
    end)


    if (transition and tickCount() >= minTicks) then
      currentState.exit(data)
      local nextState = states[transition.state]
      assert(nextState, 'No state found with name ' .. transition.state);

      nextState.init()
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