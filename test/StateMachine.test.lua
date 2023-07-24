local lust = require 'lib/lust'
local describe, it, expect = lust.describe, lust.it, lust.expect

local StateMachine = require 'src/StateMachine'

describe('StateMachine', function()
  it('can be instantiated', function ()
    local machine = StateMachine('<starting-state>')

    expect(machine.currentState()).to.be('<starting-state>')
  end)

  it('updates state per transition rules', function ()
    local machine = StateMachine('<starting-state>')
      .transitionTo('<end-state>')
      .when(function (data) return data and data.val == 'finish' end)

    machine.process()
    expect(machine.currentState()).to.be('<starting-state>')

    machine.process({ val = 'foo' })
    expect(machine.currentState()).to.be('<starting-state>')

    machine.process({ val = 'finish' })
    expect(machine.currentState()).to.be('<end-state>')
  end)

  it('throws with invalid transition to same state', function ()
    expect(function ()
      StateMachine('foo').transitionTo('foo')
    end).to.fail()
  end)

  it('works with more complex example', function ()
    local machine = StateMachine('idle')
      .transitionTo('walk')
      .when(function (data)
        return data.key == '<walk>'
      end)
      .orWhen(function (data)
        return data.foo
      end)

      expect(machine.currentState()).to.be('idle')
      machine.process({})
      expect(machine.currentState()).to.be('idle')
      machine.process({ foo = true })
      expect(machine.currentState()).to.be('walk')
      machine.process({ key = '<walk>' })
      expect(machine.currentState()).to.be('walk')

      machine.state('walk').transitionTo('idle').when(function (data) return data.action == '<finished>' end);
      machine.process({ action = '<finished>' })

      expect(machine.currentState()).to.be('idle')
  end)

  it('works with yet more complex state graph example', function ()
    local machine = StateMachine('idle')
      .transitionTo('walking').when(function (data) return data.walk or data.key == '<walk>' end)
      .state('walking')
      .transitionTo('jumping').when(function (data) return data.jump end).orWhen(function(data) return data.jump == '<jump>' end)
      -- Can only transition to idle from jumping
      .state('jumping')
      .transitionTo('idle').when(function (data) return data.idle end).orWhen(function (data) return data.key == '<idle>' end)

    expect(machine.currentState()).to.be('idle')

    machine.process({ walk = true })
    expect(machine.currentState()).to.be('walking')

    machine.process({ key = '<idle>' })
    expect(machine.currentState()).to.be('walking')

    machine.process({ jump = true })
    expect(machine.currentState()).to.be('jumping')

    -- Can't transition to walking from jumping
    machine.process({ key = '<walk>' })
    expect(machine.currentState()).to.be('jumping')

    machine.process({ key = '<idle>' });
    expect(machine.currentState()).to.be('idle')
  end)

  describe('initialising new state', function ()
    it('invokes callback when transitioning to new state', function ()
      local mock = lust.spy(function () end)
      local machine = StateMachine('idle')
        .transitionTo('walk').when(function (data) return data.walk end).andThen(mock)

      expect(#mock).to.equal(0)

      machine.process({ walk = true })
      expect(#mock).to.equal(1)
    end)
    it('also works with the inverse construction', function ()
      local mock = lust.spy(function () end)
      local machine = StateMachine('idle')
        .transitionTo('walk').andThen(mock).when(function (data) return data.walk end)

      expect(#mock).to.equal(0)

      machine.process({ walk = true })
      expect(#mock).to.equal(1)
    end)
    it('initialises default state if needed', function ()
      local init1 = lust.spy(function () end)
      local init2 = lust.spy(function () end)
      local machine = StateMachine('idle').andThen(init1)
        .transitionTo('walk').andThen(init2).when(function (data) return data.walk end)

      expect(#init1).to.equal(0)
      expect(#init2).to.equal(0)

      machine.init()
      expect(#init1).to.equal(1)
      expect(#init2).to.equal(0)

      machine.process({ walk = true })
      expect(#init1).to.equal(1)
      expect(#init2).to.equal(1)
    end)
  end)

  describe('tick state', function ()
    it('calls tick function for each process() call where state does not change', function ()
      local tick1 = lust.spy(function () end)
      local tick2 = lust.spy(function () end)

      local machine = StateMachine('idle').tick(tick1)
        .transitionTo('walk').when(function (data) return data.walk end)
        .state('walk').tick(tick2)

      expect(#tick1).to.equal(0)
      expect(#tick2).to.equal(0)

      machine.process({ walk = false })
      machine.process({ walk = false })

      expect(#tick1).to.equal(2)
      expect(#tick2).to.equal(0)

      machine.process({ walk = true })
      -- neither idle nor walk state should tick on transition
      expect(#tick1).to.equal(2)
      expect(#tick2).to.equal(0)

      machine.process({})
      -- now walk should tick once
      expect(machine.currentState()).to.be('walk')
      expect(#tick1).to.equal(2)
      expect(#tick2).to.equal(1)
    end)
  end)

  describe('chaining state transitions', function ()
    it('can use .state() to declare different transitions', function ()
      local idleInit = lust.spy(function () end)
      local walkInit = lust.spy(function () end)
      local walkTick = lust.spy(function () end)
      local neverCall = lust.spy(function () end)
      local machine = StateMachine('idle').andThen(idleInit)
        .transitionTo('walk').when(function (data) return data.walk end)
        .transitionTo('never').when(function () return false end) -- Never transition
        .state('walk').andThen(walkInit).tick(walkTick)
        .transitionTo('idle').when(function (data) return not data.walk end)
        .state('never').andThen(neverCall)
        .init()

      expect(machine.currentState()).to.be('idle')

      machine.process({ walk = true })
      expect(machine.currentState()).to.be('walk')
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(0)

      machine.process({ walk = true })
      expect(machine.currentState()).to.be('walk')
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(1)
      expect(#neverCall).to.equal(0)

      machine.process({ walk = false })
      expect(machine.currentState()).to.be('idle')
      expect(#idleInit).to.equal(2)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(1)
      expect(#neverCall).to.equal(0)
    end)

    it('throws if you declare invalid transition', function ()
      expect(function ()
        return StateMachine('idle')
          .transitionTo('walk')
          .state('walk').when(function (data) return data.walk end).andThen(lust.spy(function() end))
      end).to.fail()
    end)
  end)

  describe('forAtLeast', function ()
    it('can declare minTicks before state can transition', function ()
      local idleInit = lust.spy(function () end)
      local walkInit = lust.spy(function () end)
      local walkTick = lust.spy(function () end)

      -- No idle tick callback, so should no-op for two ticks
      local machine = StateMachine('idle').andThen(idleInit).forAtLeast(2)
        .transitionTo('walk').when(function (data) return data.walk end).orWhen(function (data) return data.run end)
        -- Expect walkTick to be called for 4 ticks
        .andThen(walkInit).tick(walkTick).forAtLeast(4)
        .state('walk').transitionTo('idle').when(function (data) return not data.walk end)
        .init()

      expect(#idleInit).to.equal(1)
      expect(machine.currentState()).to.be('idle')

      -- First tick
      machine.process({ walk = true })
      expect(machine.currentState()).to.be('idle');
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(0)

      -- Second tick
      machine.process({ walk = true })
      expect(machine.currentState()).to.be('idle')
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(0)

      -- Third tick
      machine.process({ walk = true })
      expect(machine.currentState()).to.be('walk');
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(0)

      -- Fourth tick - conditions met to return to idle, but should tick at least 4 times
      machine.process({ walk = false })
      expect(machine.currentState()).to.be('walk');
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(1)

      -- Fifth tick
      machine.process({ walk = false })
      expect(machine.currentState()).to.be('walk')
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(2)

      -- Sixth tick
      machine.process({ walk = false })
      expect(machine.currentState()).to.be('walk')
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(3)

      -- Seventh tick
      machine.process({ walk = false })
      expect(machine.currentState()).to.be('walk')
      expect(#idleInit).to.equal(1)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(4)

      -- Eighth tick
      machine.process({ walk = false })
      expect(machine.currentState()).to.be('idle')
      expect(#idleInit).to.equal(2)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(4)

      -- Ninth tick - and checking minTicks for transition back again...
      machine.process({ walk = true })
      expect(machine.currentState()).to.be('idle')
      expect(#idleInit).to.equal(2)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(4)

      -- Tenth tick
      machine.process({ walk = true })
      expect(machine.currentState()).to.be('idle')
      expect(#idleInit).to.equal(2)
      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(4)

      -- Eleventh tick
      machine.process({ walk = true })
      expect(machine.currentState()).to.be('walk')
      expect(#idleInit).to.equal(2)
      expect(#walkInit).to.equal(2)
      expect(#walkTick).to.equal(4)
    end)

    it('accepts function to define minTicks for transition state', function ()
      local idleInit = lust.spy(function () end)
      local idleTick = lust.spy(function () end)
      local walkInit = lust.spy(function () end)
      local walkTick = lust.spy(function () end)

      -- forAtLeast value increases with each call
      local calls = 0;
      local forAtLeastFn = function () calls = calls + 1; return calls end

      -- Should call idleTick once
      local machine = StateMachine('idle').andThen(idleInit).tick(idleTick).forAtLeast(forAtLeastFn)
        .transitionTo('walk').when(function (data) return data.walk end)
        -- Should call walkTick twice
        .andThen(walkInit).tick(walkTick).forAtLeast(forAtLeastFn)
        .state('walk').transitionTo('idle').when(function (data) return not data.walk end)
        .init()

      expect(#idleInit).to.equal(1)
      expect(#idleTick).to.equal(0)

      expect(#walkInit).to.equal(0)
      expect(#walkTick).to.equal(0)

      -- Doesn't walk yet, because must tick forAtLeast 1
      machine.process({ walk = true })
      expect(#idleInit).to.equal(1)
      expect(#idleTick).to.equal(1)

      expect(#walkInit).to.equal(0)
      expect(#walkTick).to.equal(0)

      -- Now walks, because idle ticked once
      machine.process({ walk = true })
      expect(#idleInit).to.equal(1)
      expect(#idleTick).to.equal(1)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(0)

      -- Doesn't idle yet, because must tick forAtLeast 2
      machine.process({ walk = false })
      expect(#idleInit).to.equal(1)
      expect(#idleTick).to.equal(1)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(1)

      -- Doesn't idle yet, because must tick forAtLeast 2
      machine.process({ walk = false })
      expect(#idleInit).to.equal(1)
      expect(#idleTick).to.equal(1)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(2)

      -- Idles again
      machine.process({ walk = false })
      expect(#idleInit).to.equal(2)
      expect(#idleTick).to.equal(1)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(2)

      -- Should idle for 3 ticks...
      machine.process({ walk = true })

      expect(#idleInit).to.equal(2)
      expect(#idleTick).to.equal(2)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(2)

      machine.process({ walk = true })

      expect(#idleInit).to.equal(2)
      expect(#idleTick).to.equal(3)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(2)

      machine.process({ walk = true })

      expect(#idleInit).to.equal(2)
      expect(#idleTick).to.equal(4)

      expect(#walkInit).to.equal(1)
      expect(#walkTick).to.equal(2)

      -- ...and then walk
      machine.process({ walk = true })

      expect(#idleInit).to.equal(2)
      expect(#idleTick).to.equal(4)

      expect(#walkInit).to.equal(2)
      expect(#walkTick).to.equal(2)
    end)
  end)

  describe('events', function ()
    it('can subscribe to state transition events', function ()
      local onWalk = lust.spy(function () end)
      local machine = StateMachine('idle')
        .transitionTo('walk').when(function (data) return data.walk end)
        .on('walk', onWalk)

      expect(#onWalk).to.equal(0)

      machine.process({})
      expect(#onWalk).to.equal(0)

      machine.process({ walk = true})
      expect(#onWalk).to.equal(1)
      expect(onWalk[1][1].walk).to.be(true)
    end)

    it('correctly calls multiple subscribers for multiple state changes', function ()
      local onWalk = lust.spy(function () end)
      local onWalk2 = lust.spy(function () end)

      local machine = StateMachine('idle')
        .transitionTo('walk').when(function (data) return data.walk end)
        .state('walk').transitionTo('idle').when(function (data) return not data.walk end)
        .on('walk', onWalk)
        .on('walk', onWalk2)

      machine.process({})
      expect(#onWalk).to.equal(0)
      expect(#onWalk2).to.equal(0)

      machine.process({ walk = true })
      expect(#onWalk).to.equal(1)
      expect(#onWalk2).to.equal(1)

      -- Don't call again on tick
      machine.process({ walk = true })
      expect(#onWalk).to.equal(1)
      expect(#onWalk2).to.equal(1)

      -- Don't call again on transition to idle
      machine.process({ walk = false })
      expect(#onWalk).to.equal(1)
      expect(#onWalk2).to.equal(1)

      -- Call again on second transition to walk
      machine.process({ walk = true })
      expect(#onWalk).to.equal(2)
      expect(#onWalk2).to.equal(2)
    end)
  end)
end)
