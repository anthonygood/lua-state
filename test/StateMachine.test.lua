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
end)
