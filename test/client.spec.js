'use strict'

var expect = require('chai').expect
var sinon = require('sinon');
var microtime = require('@risingstack/microtime');
var version = require('../lib/redis/version');
var rateLimiter = require('../lib/client')

describe('rateLimiter', function () {

  describe('options', function () {

    describe('single', function () {
      var options;

      beforeEach(function () {
        options = {
          redis: {defineCommand: sinon.stub()},
          interval: 10000,
          maxInInterval: 5,
          minDifference: 500,
          buckets: 10000,
          namespace: 'MyNamespace'
        };
        options.redis['rateLimiter' + version] = sinon.stub();
      });

      it('throws if redis doesn\'t expose `defineCommand`', function () {
        options.redis = {};
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if interval is missing', function () {
        delete options.interval;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if maxInInterval is missing', function () {
        delete options.maxInInterval;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if interval is non-positive', function () {
        options.interval = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if maxInInterval is non-positive', function () {
        options.maxInInterval = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if minDifference is non-positive', function () {
        options.minDifference = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if buckets is non-positive', function () {
        options.buckets = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      describe('limiter', function () {
        var limiter;
        beforeEach(function (done) {
          rateLimiter(options, function (err, lim) {
            limiter = lim;
            done(err);
          });
          sinon.stub(microtime, 'now').returns(3000);
        });
        afterEach(function () {
          microtime.now.restore();
        });
        it('throws an error when called without callback', function () {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          expect(limiter.bind(null)).to.throw();
        });
        it('throws an error when called with invalid increment', function () {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          expect(limiter.bind(null, -3, function () { })).to.throw();
        });
        it('calls redis.defineCommand with expected arguments when called without id and increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter(function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [1, 'MyNamespace', 1, 1, 3000, 500 * 1000, 5, 1000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
        it('calls redis.defineCommand with expected arguments when called with increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter(3, function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [1, 'MyNamespace', 1, 3, 3000, 500 * 1000, 5, 1000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
        it('calls redis.defineCommand with expected arguments when called with id and increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter('action', 3, function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [1, 'MyNamespace:action', 1, 3, 3000, 500 * 1000, 5, 1000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
      });
    })

    describe('multi array', function () {
      var options;

      beforeEach(function () {
        options = {
          redis: {
            defineCommand: function () {
              return 0;
            }
          },
          namespace: 'MyNamespace',
          limits: [{
            interval: 10000,
            maxInInterval: 5,
            minDifference: 500
          }, {
            interval: 100000,
            maxInInterval: 25
          }]
        };
        options.redis['rateLimiter' + version] = sinon.stub();

      });

      it('throws if array is empty', function () {
        options.limits = [];
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if interval is missing', function () {
        delete options.limits[1].interval;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if redis doesn\'t expose `defineCommand`', function () {
        options.redis = {};
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if maxInInterval is missing', function () {
        delete options.limits[1].maxInInterval;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if interval is non-positive', function () {
        options.limits[1].interval = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if maxInInterval is non-positive', function () {
        options.limits[1].maxInInterval = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if minDifference is non-positive', function () {
        options.limits[0].minDifference = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if buckets is non-positive', function () {
        options.limits[0].buckets = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      describe('limiter', function () {
        var limiter;
        beforeEach(function (done) {
          rateLimiter(options, function (err, lim) {
            limiter = lim;
            done(err);
          });
          sinon.stub(microtime, 'now').returns(3000);
        });
        afterEach(function () {
          microtime.now.restore();
        });
        it('calls redis.defineCommand with expected arguments when called without id and increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter(function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [2, 'MyNamespace', 'MyNamespace:1', 1, 1, 3000, 500 * 1000, 0 * 1000, 5, 25, 1000, 10000, 10000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
        it('calls redis.defineCommand with expected arguments when called with increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter(3, function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [2, 'MyNamespace', 'MyNamespace:1', 1, 3, 3000, 500 * 1000, 0 * 1000, 5, 25, 1000, 10000, 10000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
        it('calls redis.defineCommand with expected arguments when called with id and increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter('action', 3, function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [2, 'MyNamespace:action', 'MyNamespace:1:action', 1, 3, 3000, 500 * 1000, 0 * 1000, 5, 25, 1000, 10000, 10000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
      });
    });

    describe('multi object', function () {
      var options;

      beforeEach(function () {
        options = {
          redis: {
            defineCommand: function () {
              return 0;
            }
          },
          namespace: 'MyNamespace',
          limits: {
            a: {
              interval: 10000,
              maxInInterval: 5,
              minDifference: 500
            },
            b : {
              interval: 100000,
              maxInInterval: 25
            }
          }
        }
        options.redis['rateLimiter' + version] = sinon.stub();
      });

      it('throws if array is empty', function () {
        options.limits = [];
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if interval is missing', function () {
        delete options.limits.b.interval;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if redis doesn\'t expose `defineCommand`', function () {
        options.redis = {};
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if maxInInterval is missing', function () {
        delete options.limits.b.maxInInterval;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if interval is non-positive', function () {
        options.limits.b.interval = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if maxInInterval is non-positive', function () {
        options.limits.b.maxInInterval = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if minDifference is non-positive', function () {
        options.limits.a.minDifference = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      it('throws if buckets is non-positive', function () {
        options.limits.a.buckets = -1;
        expect(rateLimiter.bind(null, options)).to.throw();
      });

      describe('limiter', function () {
        var limiter;
        beforeEach(function (done) {
          rateLimiter(options, function (err, lim) {
            limiter = lim;
            done(err);
          });
          sinon.stub(microtime, 'now').returns(3000);
        });
        afterEach(function () {
          microtime.now.restore();
        });
        it('calls redis.defineCommand with expected arguments when called without id and increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter(function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [2, 'MyNamespace:a', 'MyNamespace:b', 1, 1, 3000, 500 * 1000, 0 * 1000, 5, 25, 1000, 10000, 10000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
        it('calls redis.defineCommand with expected arguments when called with increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter(3, function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [2, 'MyNamespace:a', 'MyNamespace:b', 1, 3, 3000, 500 * 1000, 0 * 1000, 5, 25, 1000, 10000, 10000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
        it('calls redis.defineCommand with expected arguments when called with id and increment', function (done) {
          options.redis['rateLimiter' + version].onCall(0).yields(null, [0, 1, 2000]);
          limiter('action', 3, function (err, data) {
            if (err) {
              return done(err);
            }
            try {
              expect(options.redis['rateLimiter' + version].args[0][0]).to.eql(
                [2, 'MyNamespace:a:action', 'MyNamespace:b:action', 1, 3, 3000, 500 * 1000, 0 * 1000, 5, 25, 1000, 10000, 10000, 10000]);
              expect(data).eql({
                actionsRemaining: 0,
                actionsRecorded: 1,
                wait: 2
              })
              return done();
            } catch (err) {
              return done(err);
            }
          });
        });
      });
    });
  });
});
