_ = require "underscore"
DynamicScope = require "./DynamicScope"


# =============================================================================
# Computation
# =============================================================================

###

This code is responsible for keeping track of whether we are running a
computation and also memoizing functions so that they do not reexecute within
a given computation.

TODO: This section can be factored out into its own file, ComputationManager,
and tested separately.

###

isComputationRunning = false
computationCounter = 0

# Any memoized functions called within callback will never be reexecuted. They
# will instead return their cached value.
run = (callback) ->
  isComputationRunning = true
  computationCounter++
  result = callback()
  isComputationRunning = false
  return result

memoize = (fn) ->
  cachedValue = null
  lastEvaluated = -1
  return ->
    if lastEvaluated != computationCounter
      cachedValue = fn()
      lastEvaluated = computationCounter
    return cachedValue


# =============================================================================
# Spread Environment
# =============================================================================

class SpreadEnv
  constructor: (@parent, @spread, @index) ->

  lookup: (spread) ->
    if spread.origin == @spread
      return @index
    return @parent?.lookup(spread)

  # Note: Not a mutation, assign returns a new SpreadEnv where spread is
  # assigned to index.
  assign: (spread, index) ->
    return new SpreadEnv(this, spread.origin, index)

emptySpreadEnv = new SpreadEnv()


# =============================================================================
# Dynamic Scope
# =============================================================================

dynamicScope = new DynamicScope {
  # The current spread environment.
  spreadEnv: emptySpreadEnv

  # Whether or not cells should throw an UnresolvedSpreadError if they
  # encounter a spread that is not in the current spread environment.
  shouldThrow: false
}


# =============================================================================
# Creating Cells
# =============================================================================

cell = (fn) ->

  cellFn = ->
    # Ensure that a computation is running.
    unless isComputationRunning
      return run(cellFn)

    value = memoizedEvaluateFull()
    value = resolve(value)
    if value instanceof Spread and dynamicScope.context.shouldThrow
      throw new UnresolvedSpreadError(value)
    return value

  # Given a spread, resolve will recursively try to lookup an index in the
  # current spread environment and return the item in the spread at that
  # index.
  resolve = (value) ->
    currentSpreadEnv = dynamicScope.context.spreadEnv
    if value instanceof Spread
      index = currentSpreadEnv.lookup(value)
      if index?
        value = value.items[index]
        return resolve(value)
    return value

  # This returns the full value of the cell meaning as a spread (if necessary)
  # and irrespective of the current dynamic scope context.
  evaluateFull = ->
    dynamicScope.with {shouldThrow: false, spreadEnv: emptySpreadEnv}, asSpread

  memoizedEvaluateFull = memoize(evaluateFull)

  # This returns the value of the cell as a spread (if necessary) within the
  # current dynamic scope context. It evaluates fn, telling it to throw an
  # UnresolvedSpreadError if it encounters a spread which is not in the
  # current spread environment. It then catches this and evaluates fn across
  # the encountered spread.
  asSpread = ->
    try
      return dynamicScope.with {shouldThrow: true}, fn
    catch error
      if error instanceof Dataflow.UnresolvedSpreadError
        spread = error.spread
        return evaluateAcrossSpread(spread)
      else
        throw error

  evaluateAcrossSpread = (spread) ->
    currentSpreadEnv = dynamicScope.context.spreadEnv
    items = _.map spread.items, (item, index) ->
      spreadEnv = currentSpreadEnv.assign(spread, index)
      return dynamicScope.with {spreadEnv}, asSpread
    return new Spread(items, spread.origin)

  cellFn.asSpread = asSpread
  return cellFn


# =============================================================================
# Spread
# =============================================================================

class Spread
  constructor: (@items, @origin) ->
    if !@origin
      @origin = this

class UnresolvedSpreadError
  constructor: (@spread) ->


# =============================================================================
# Export
# =============================================================================

module.exports = Dataflow = {
  run
  currentSpreadEnv: -> dynamicScope.context.spreadEnv
  cell, Spread, SpreadEnv, UnresolvedSpreadError
}