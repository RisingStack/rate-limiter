'use strict';

var assert = require('assert');
var microtime = require('@risingstack/microtime');
var path = require('path');
var Script = require('./script');

function parseOpts (options, index) {
  var config = {
    index:          index != null ? index : '',
    interval:       options.interval * 1000, // in microseconds
    buckets:        options.buckets != null ? options.buckets : 10000,
    maxInInterval:  options.maxInInterval,
    minDifference:  options.minDifference != null ? 1000 * options.minDifference : 0, // also in microseconds
  };
  assert(config.interval > 0, 'Must pass a positive integer for `options.interval`');
  assert(config.maxInInterval > 0, 'Must pass a positive integer for `options.maxInInterval`');
  assert(!(config.minDifference < 0), '`options.minDifference` cannot be negative');
  assert(config.buckets > 0, '`options.buckets` must be positive');
  return config;
}

function rateLimiter (options, cb) {
  var namespace = options.namespace || '';
  var mode = options.mode || 'binary';
  var redis = options.redis;
  var limits = [];

  assert(options.redis, '`options.redis` should be a redis client');
  assert(mode === 'uniform' ||
    mode === 'binary' ||
    mode === 'nary',
    '`options.mode` should be one of `uniform`, `binary` and `nary`');
  if (Array.isArray(options.limits)) {
    assert(options.limits.length, '`options.limits` should not be an empty array');
    Array.prototype.push.apply(limits, options.limits.map(parseOpts));
  } else if (options.limits) {
    assert.equal(typeof options.limits, 'object', '`options.limits` should be an object');
    Array.prototype.push.apply(limits, Object.keys(options.limits).map(function (key) {
      return parseOpts(options.limits[key], key);
    }));
  } else {
    limits.push(parseOpts(options));
  }

  function limiter (script) {
    return function (id, increment, cb) {
      if (!increment && !cb) {
        cb = id;
        increment = 1;
        id = '';
      } else if (!cb) {
        cb = increment;
        increment = id;
        id = '';
      }
      assert(increment > 0, '`increment` must be a positive integer');
      assert.equal(typeof id, 'string', '`id` must be a string');
      assert.equal(typeof cb, 'function', 'Callback must be a function.');
      var now = microtime.now();

      var args = [limits.length];
      limits.forEach(function (limit, i) {
        var key = [namespace, limit.index, id].filter(function (s) {
          return s !== '';
        }).join(':');
        args[1 + i] = key;
        args[4 + limits.length + i] = limit.minDifference;
        args[4 + 2 * limits.length + i] = limit.maxInInterval;
        args[4 + 3 * limits.length + i] = limit.interval / limit.buckets;
        args[4 + 4 * limits.length + i] = limit.buckets;
      });
      args[1 + limits.length] = mode === 'nary' ? 2 : mode === 'binary' ? 1 : 0;
      args[2 + limits.length] = increment;
      args[3 + limits.length] = now;

      script.eval(redis, args, function (err, result) {
        if (err) {
          return cb(err);
        }
        return cb(null, {
          actionsRemaining: result[0],
          actionsRecorded: result[1],
          wait: result[2] / 1000
        });
      });
    };
  }

  Script.fromPath(path.resolve(__dirname, 'redis', 'rate_limiter.lua'), function (err, script) {
    if (err) {
      return cb(err);
    }
    return cb(null, limiter(script));
  });
}

module.exports = rateLimiter;
