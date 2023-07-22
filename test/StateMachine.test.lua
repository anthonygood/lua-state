local lust = require 'lib/lust'
local describe, it, expect = lust.describe, lust.it, lust.expect

local StateMachine = require 'src/state/StateMachine'

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

      machine.process({ walk = false });
      machine.process({ walk = false });

      expect(#tick1).to.equal(2)
      expect(#tick2).to.equal(0)

      machine.process({ walk = true });
      -- neither idle nor walk state should tick on transition
      expect(#tick1).to.equal(2)
      expect(#tick2).to.equal(0)

      machine.process({})
      -- now walk should tick once
      expect(#tick1).to.equal(2)
      expect(#tick2).to.equal(1)
    end)
  end)
end)
