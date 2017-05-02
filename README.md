# Rolling Rate Limiter
[![CircleCI](https://img.shields.io/circleci/project/github/RisingStack/rate-limiter.svg?style=flat-square)](https://circleci.com/gh/RisingStack/rate-limiter)

## Description
This is an implementation of a rate limiter/circuit breaker in Node.js and Redis that allows for rate limiting with a rolling window. Based on [classdojo/rolling-rate-limiter](https://github.com/classdojo/rolling-rate-limiter), but more versatile with support for
 - multiple limits,
 - batch actions,
 - sampling actions on an equidistant grid,
 - three levels of gratuitousness towards capped attempts.

## Getting started

Install with npm

`npm i @risingstack/rate-limiter`

Use

```js
  var rateLimiterFactory = require('@risingstack/rate-limiter');
  var Redis = require('ioredis');
  var redis = new Redis();

  var limiter = rateLimiterFactory({
    redis: redis,
    interval: 1000, // in milliseconds
    maxInInterval: 10,
    minDifference: 100, // optional: the minimum time (in milliseconds) between any two actions
    buckets: 1000, // optional: splits interval to 1000 equidistant buckets, samples attempts
    // to save memory and CPU usage 
    mode: 'binary' // do not record capped attempts (this is the default mode)
  });

  function attemptAction(userId) {
    // Optional first argument identifies the action to be limited.
    limiter(userId, function (err, result) {
      if (result.acknowledged <= 0) {
        // limit was exceeded, actions should not be allowed
        // binary mode only acknowledges data when there's room for it
        // so acknowledged cannot be less then 0, however in uniform mode, it can.
      } else {
        // limit was not exceeded, actions should be allowed
      }
    });
  }
```

## API 

### rateLimiterFactory

`rateLimiterFactory(options: SingleLimitOption | MultiLimitOption): rateLimiter`

Creates a rateLimiter.

#### options

```js
type Limit = {
  interval: number,
  maxInInterval: number,
  minDifference?: number = 0,
  buckets?: number = 10000
}
```
```js
type SingleLimitOption = {
  redis: Redis,
  mode?: 'nary' | 'binary' | 'uniform'  = 'binary',
  namespace?: string = "",
  interval: number,
  buckets?: number = 10000,
  maxInInterval: number,
  minDifference?: number = 0
}
```
The function also supports multiple limits:
```js
type MultiLimitOption = {
  redis: Redis,
  mode?: 'nary' | 'binary' | 'uniform'  = 'binary',
  namespace?: string = '',
  limits: {
    [index: string]: Limit 
  } | Limit[]
}
```
- **redis**: pass an instantiated redis client here.
- **interval**: length of the rate limiting window in millis.
- **minDifference**: optional minimum interval between consecutive attempts in millis.
- **buckets**: how many buckets the sampling window has. Larger buckets result in better accuracy, however with significant degradation in processing time. The default value of `10000` should suffice for most use cases, however when using `uniform` mode with frequent unit increments, you should aim for something even smaller.
- **mode**: governs how failed attempts are handled. In descending order of gratuitousness:
  - `'nary'`: Do not count attempts exceeding the limit. Batch increments can be partially accepted by filling the existing space.
  - `'binary'`: Do not count attempts exceeding the limit. When batching, either the whole request is accepted or discarded.
  Note that in case of a unit increment, `binary` and `nary` behave the same way.
  - `'uniform'`: every attempt counts, including those above the limit. This is default the behavior of [classdojo/rolling-rate-limiter](https://github.com/classdojo/rolling-rate-limiter).

On how limits are identified:
Limits are identified by a key comprising `namespace`, `index` and `id`. You can specify `namespace` and `index` when instantiating the rate limiter. The former is set with a propery. If you have a single limit,
`index` will be the empty string. If you have multiple limits in an array their index becomes `index` appended with a colon. If you use an object instead, the keys become the indices.
`id` is specified when calling the `rateLimit` function. It is optional as well, but if exists it will be appended with a colon.

### rateLimiter
```js
rateLimiter(
  id?: string = '',
  n?: number = 1, 
  cb ?: (err: ?Error, result: { acknowledged: number, actionsRemaining: number, wait: number }) => void
): void
```
- **n**: must be a positive integer
The callback arguments mean the following:
 - acknowledged: how many attempts are recorded as attempts. In uniform mode every action is acknowledged, even
   if it exceeds the limit. In binary mode it is either 0 or `n`. In N-ary mode it is between 0 and `n` inclusive.
 - actionsRemaining: how many actions are still remaining in the rolling window, after adding the acknowledged attempt. This can be negative only in uniform mode.
 - wait: a positive interval in microseconds, that the next action with the batch size of `n` can be attempted that it is fully acknowledged (in binary and N-ary mode) and actionsRemaining is non-negative (only required to check in uniform mode).

## Multiple limits
You can specify multiple limits. The benefit to composing multiple rate limiter instances is that this way the whole state will be updated in a single redis transaction atomically. `wait` is the time you have to wait for all limits to expire, `actionsRemaining` is the minimum number of actions left. E.g. to disallow a hourly rate limit to be sent in a single minute. Keep in mind though that different modes for the limits are not supported.
```javascript
  var limiter = rateLimiterFactory({
    redis: redisClient,
    namespace: "requestRateLimiter",
    limits: [{
      interval: 60 * 60 000,
      maxInInterval: 1000 // max 1000 request / hour
    }, {
      interval: 60 000,
      maxInInterval: 100 // max 100 request / minute
    }]
  });

  function attemptAction(userId) {
    limiter(userId, function(err, result) {
      if (err) {
        // redis failed or similar.
      } else if (result.acknowledged <= 0) {
        // limit was exceeded, action should not be allowed
      } else {
        // limit was not exceeded, action should be allowed
      }
    });
  }
```

## Batch actions

### Binary
Binary mode is as straightforward as any other.
```javascript
  var limiter = rateLimiterFactory({
    redis: redisClient,
    namespace: "requestRateLimiter",
    limits: [{
      interval: 60 * 60 000,
      maxInInterval: 1000 // max 1000 request / hour
    }, {
      interval: 60 000,
      maxInInterval: 100 // max 100 request / minute
    }]
  });

  function attemptBatchAction(userId) {
    limiter(userId, 5, function(err, result) {
      if (err) {
        // redis failed or similar.
      } else if (result.acknowledged <= 0) {
        // limit was exceeded, no actions should be allowed
      } else {
        // limit was not exceeded, all actions should be allowed
      }
    });
  }
```

### N-ary
N-ary mode is a bit more complicated. Actually `result.acknowledged` is not a boolean, but the actual 
number of actions saved, which happens to be 0 (falsy) if the limit has been exceeded
in all of the other modes. However, here partial saves are possible.
```javascript
  var limiter = rateLimiterFactory({
    redis: redisClient,
    namespace: "requestRateLimiter",
    limits: [{
      interval: 60 * 60 000,
      maxInInterval: 1000 // max 1000 request / hour
    }, {
      interval: 60 000,
      maxInInterval: 100 // max 100 request / minute
    }],
    mode: 'nary'
  });

  function attemptBatchAction(userId) {
    limiter(userId, 5, function(err, result) {
      if (err) {
        // redis failed or similar.
      } else if (result.acknowledged <= 0) {
        // limit was exceeded, no actions should be allowed
      } else if (result.acknowledged < 5){
        // limit was exceeded, `result.acknowledged` number of actions allowed
      } else {
        // limit was not exceeded, all actions should be allowed
      }
    });
  }
```

## Performance considerations

To remain atomic, the algorithm that gets and updates the data structures for each `limiter` invocation is
implemented with a Lua script and executed in Redis. Script evaluation is a stop-the-world process, so
this library will likely degrade the performance of your Redis installation.
I suggest trying out multiple limit configurations to find a compromise in performance and precision.

## The algorithm
Each identifier can have one or more limits associated to it. Each limit is stored in a __sorted set__ in Redis. The members are equal to the (microsecond) times at which actions were attempted, values are the batch sizes of the actions concatenated with their keys.

When a new action is attempted, all of its limits are observed.

```
# 1
for i := 1..size(sets):
  set := filter(set, action => action.time > now - (buckets[i] * intervals[i] + floor(interval[i] / 2)) # 1.1
  count[i] := reduce(set, (count, action) => action.increment + count, 0) # 1.2
  last[i] := set[size(set)].time

# 2
actionsRemaining := Infinity
for i := 1..size(sets):
  actionsRemaining := min(actionsRemaining, max[i] - count[i])

# 3
acknowledged := 0;
minDiffWait := 0;
if mode = 'uniform' or mode = 'binary' and actionsRemaining - increment >= 0 or mode = 'nary' and actionsRemaining - 1 >= 0:
  # 3.2
  # 3.1.1
  minDiffWait := max(...minDifference)
  
  # 3.1.2
  if mode = 'nary':
    acknowledged := min(increment, actionsRemaining)
  else:
    acknowledged := increment
    
else:
  # 3.2
  for i := 1..size(sets):
    if (last[i]):
      minDiffWait := max(minDiffWait, last[i] - now + minDifference[i])

# 4
wait := []
for i := 1..size(sets):
  # 4.1
  if acknowledged > 0:
    # 4.1.1
    if last[i] != nil and sets[sets[i].length].time + intervals[i] >= now):
      inc := sets[sets[i].length].increment + acknowledged
      rem(sets[i], sets[sets[i].length])
      add(sets[i], { time: last[i], increment: inc })
    else:
      new := now
      if last[i] != nil:
        new = floor((now - last[i]) / intervals[i]) * intervals[i] + last[i]
      add(sets[i], { time: now, increment: acknowledged })
      last[i] = new
    count[i] += acknowledged
  j := 1
  # 4.2
  sum := count[i]
  limit := -Infinity
  while sum + increment > max and j <= size(set):
    sum -= set[j].increment
    limit := set[j].time
    j := j + 1
  rem(sets[i], 0, limit);
  intervalWait[i] := limit + intervals[i] * buckets[i] - now

next := max(minDiffWait, ...wait)

return actionsRemaining - acknowledged, acknowledged, next
```
