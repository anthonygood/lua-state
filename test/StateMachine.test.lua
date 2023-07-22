local lust = require 'lib/lust'
local describe, it, expect = lust.describe, lust.it, lust.expect

local StateMachine = require 'src/state/StateMachine'

describe('StateMachine', function()
  it('can be instantiated', function ()
    local machine = StateMachine('<starting-state>')

    expect(machine.currentState()).to.equal('<starting-state>')
  end)

  it('updates state per transition rules', function ()
    local machine = StateMachine('<starting-state>')
      .transitionTo('<end-state>')
      .when(function (data) return data and data.val == 'finish' end)

    machine.process()
    expect(machine.currentState()).to.equal('<starting-state>')

    machine.process({ val = 'foo' })
    expect(machine.currentState()).to.equal('<starting-state>')

    machine.process({ val = 'finish' })
    expect(machine.currentState()).to.equal('<end-state>')
  end)
end)
