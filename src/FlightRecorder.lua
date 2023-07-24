local Recording = function() return
  {
    time = 0,
    count = 0,
    current = 0,
    longest = 0,
  }
end

local FlightRecorder = function (machines)
  local records = {}
  local deltaKey = machines.deltaKey or 'delta'
  for _, machine in ipairs(machines) do
    local currentStateName, currentDuration = '', 0

    for stateName in pairs(machine.states) do
      assert(not records[stateName], 'Naming collision: state "' .. stateName ..'" exists in multiple state machines')

      records[stateName] = Recording()

      machine.on(stateName, function ()
        local next = records[stateName]

        next.count = next.count + 1
        currentStateName = stateName
        currentDuration = 0
      end)
    end

    machine.on('tick', function (data)
      local delta = data[deltaKey]
      assert(delta, 'No "'.. deltaKey ..'" attribute found for delta value in tick callback invocation')

      local record = records[currentStateName]

      if (record) then
        record.time = record.time + delta
        currentDuration = currentDuration + delta

        if (record.longest < currentDuration) then
          record.longest = currentDuration
        end
      end
    end)
  end

  return records
end

return FlightRecorder
