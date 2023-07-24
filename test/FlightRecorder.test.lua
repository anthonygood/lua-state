local lust = require 'lib/lust'
local utils = require 'test/utils'

local describe, it, expect, pluck = lust.describe, lust.it, lust.expect, utils.pluck
local StateMachine = require 'src/StateMachine'
local FlightRecorder = require 'src/FlightRecorder'

local getStateMachine = function ()
  return StateMachine('idle')
    .transitionTo('walking').when(pluck('walk'))
    .transitionTo('jumping').when(pluck('jump'))
    .state('walking')
    .transitionTo('jumping').when(pluck('jump'))
    -- Can only transition to idle from jumping
    .state('jumping')
    .transitionTo('idle').when(pluck('idle'))
end

local ticks = {
  'none', -- idle 1
  'none', --   idling +10
  'walk', -- walk 1
  'walk', --   walking +10
  'walk', --   walking +20
  'walk', --   walking +30
  'walk', --   walking +40
  'jump', -- jump 1
  'walk', --   jumping +10 (invalid transition, shouldn't count)
  'idle', -- idle 2
  'idle', --   idling +20
  'jump', -- jump 2
  'jump', --   jumping +20
  'idle', -- idle 3
  'walk', -- walk 2
}

describe('FlightRecorder', function ()
  local machine = getStateMachine()
  local recorder = FlightRecorder({ machine })

  machine.init()

  for _, key in pairs(ticks) do
    machine.process({ [key] = true, delta = 10 })
  end

  it('records state counts', function ()
    expect(recorder.idle.count).to.equal(3)
    expect(recorder.walking.count).to.equal(2)
    expect(recorder.jumping.count).to.equal(2)
  end)

  it('records state times via delta value', function ()
    expect(recorder.idle.time).to.equal(30)
    expect(recorder.walking.time).to.equal(40)
    expect(recorder.jumping.time).to.equal(20)
  end)

  it('records longest times', function ()
    expect(recorder.idle.longest).to.equal(20)
    expect(recorder.walking.longest).to.equal(40)
    expect(recorder.jumping.longest).to.equal(10)
  end)

  it('can record multiple state machines', function ()
    local a = getStateMachine()
    local b = StateMachine('right')
      .transitionTo('left').when(pluck('left'))
      .state('left').transitionTo('right').when(pluck('right'))

    local bTicks = {
      'none', --   right +11
      'none', --   right +11
      'left', -- left 1
      'right',-- right 2
      'none', --   right +11
      'none', --   right +11
      'left', -- left 2
      'right',-- right 3
      'none', --   right +11
      'left', -- left 3
      'none', --   left +11
      'right',-- right 4
      'none', --   right +11
      'none', --   right +11
      'none', --   right +11
    }

    local recorder = FlightRecorder({ a, b })
    a.init()
    b.init()

    for index, aKey in ipairs(ticks) do
      a.process({ [aKey] = true, delta = 10 })
      b.process({ [bTicks[index]] = true, delta = 10 })
    end

    expect(recorder.idle.count).to.equal(3)
    expect(recorder.walking.count).to.equal(2)
    expect(recorder.jumping.count).to.equal(2)
    expect(recorder.left.count).to.equal(3)
    expect(recorder.right.count).to.equal(4)

    expect(recorder.idle.time).to.equal(30)
    expect(recorder.walking.time).to.equal(40)
    expect(recorder.jumping.time).to.equal(20)
    expect(recorder.left.time).to.equal(10)
    expect(recorder.right.time).to.equal(80)

    expect(recorder.idle.longest).to.equal(20)
    expect(recorder.walking.longest).to.equal(40)
    expect(recorder.jumping.longest).to.equal(10)
    expect(recorder.left.longest).to.equal(10)
    expect(recorder.right.longest).to.equal(30)
  end)

  it('can specify custom delta key to read time delta from tick payload', function ()
    local deltaKey = 'custom-delta-key'
    local machine = getStateMachine()
    local recorder = FlightRecorder({ machine, deltaKey = deltaKey })

    machine.init()

    for _, key in pairs(ticks) do
      machine.process({ [key] = true, [deltaKey] = 9 })
    end

    expect(recorder.idle.time).to.equal(27)
    expect(recorder.walking.time).to.equal(36)
    expect(recorder.jumping.time).to.equal(18)

    expect(recorder.idle.longest).to.equal(18)
    expect(recorder.walking.longest).to.equal(36)
    expect(recorder.jumping.longest).to.equal(9)
  end)
end)

