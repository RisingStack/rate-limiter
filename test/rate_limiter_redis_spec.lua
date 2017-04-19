require 'busted';
local limit_rate = require 'lib/redis/rate_limiter';

local MODE_UNIFORM = 0;
local MODE_BINARY = 1;
local MODE_NARY = 2;

describe('Redis module', function ()
  local now = 3000;

  describe('inserting 1 for keys={`a`}, minDiff={0}, maxCounts={1}, intervals={1000} and set is empty', function ()
    local mock = function ()
      local m = {
        times = 0;
      }
      local redis = {
        call = function (...)
          m.times = m.times + 1;
          if m.times == 1 then
            assert.same('zremrangebyscore', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(0, select(3, ...));
            assert.same(2000, select(4, ...));
          elseif m.times == 2 then
            assert.same('zrange', select(1, ...));
            return { };
          elseif m.times == 3 then
            assert.same('zadd', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(now, select(3, ...));
            assert.same(now .. ' ' .. 1, select(4, ...));
          elseif m.times == 4 then
            assert.same('expire', select(1, ...));
            assert.same('a', select(2, ...));
          else
            error('Unexpected call: ' .. select(1, ...));
          end
        end
      }
      m.redis = redis;
      return m;
    end
    it('should record and limit for 1000 ms in uniform mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_UNIFORM, 1, now, { 'a' }, { { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 0, 1, 1000 }, result);
      assert.same(4, m.times);
    end);
    it('should record and limit for 1000 ms in binary mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_BINARY, 1, now, { 'a' }, { { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 0, 1, 1000 }, result);
      assert.same(4, m.times);
    end);
    it('should record and limit for 1000 ms in nary mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_NARY, 1, now, { 'a' }, { { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 0, 1, 1000 }, result);
      assert.same(4, m.times);
    end);
  end);
  describe('inserting 1 for keys={`a`}, minDiff={50}, maxCounts={2}, intervals={1000} and set is empty', function ()
    local mock = function ()
      local m = {
        times = 0;
      }
      local redis = {
        call = function (...)
          m.times = m.times + 1;
          if m.times == 1 then
            assert.same('zremrangebyscore', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(0, select(3, ...));
            assert.same(2000, select(4, ...));
          elseif m.times == 2 then
            assert.same('zrange', select(1, ...));
            return { };
          elseif m.times == 3 then
            assert.same('zadd', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(now, select(3, ...));
            assert.same(now .. ' ' .. 1, select(4, ...));
          elseif m.times == 4 then
            assert.same('expire', select(1, ...));
            assert.same('a', select(2, ...));
          else
            error('Unexpected call: ' .. select(1, ...));
          end
        end
      }
      m.redis = redis;
      return m;
    end
    it('should record and limit for 50 ms in uniform mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_UNIFORM, 1, now, { 'a' }, { { minDiff = 50, maxCount = 2, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 1, 1, 50 }, result);
      assert.same(4, m.times);
    end);
    it('should record and limit for 50 ms in binary mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_BINARY, 1, now, { 'a' }, { { minDiff = 50, maxCount = 2, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 1, 1, 50 }, result);
      assert.same(4, m.times);
    end);
    it('should record and limit for 50 ms in nary mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_NARY, 1, now, { 'a' }, { { minDiff = 50, maxCount = 2, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 1, 1, 50 }, result);
      assert.same(4, m.times);
    end);
  end);
  describe('inserting 1 keys={`a`}, minDiff={0}, maxCounts={1}, intervals={1000} and set has a fresh item', function ()
    local mock = function ()
      local m = {
        times = 0;
      }
      local redis = {
        call = function (...)
          m.times = m.times + 1;
          if m.times == 1 then
            assert.same('zremrangebyscore', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(0, select(3, ...));
            assert.same(2000, select(4, ...));
          elseif m.times == 2 then
            assert.same('zrange', select(1, ...));
            return { '2001 1', '2001' };
          elseif m.times == 3 then
            assert.same('zadd', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(now, select(3, ...));
            assert.same(now .. ' ' .. 1, select(4, ...));
          elseif m.times == 4 then
            assert.same('expire', select(1, ...));
            assert.same('a', select(2, ...));
          else
            error('Unexpected call: ' .. select(1, ...));
          end
        end
      }
      m.redis = redis;
      return m;
    end
    it('should record and limit for 1000 ms in uniform mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_UNIFORM, 1, now, { 'a' }, { { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ -1, 1, 1000 }, result);
      assert.same(4, m.times);
    end);
    it('should discard and limit for 1 ms in binary mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_BINARY, 1, now, { 'a' }, { { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 0, 0, 1 }, result);
      assert.same(2, m.times);
    end);
    it('should record and limit for 1 ms in nary mode', function ()
      local m = mock()
      local result = limit_rate(m.redis, MODE_NARY, 1, now, { 'a' }, { { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 0, 0, 1 }, result);
      assert.same(2, m.times);
    end);
  end);
  describe('inserting 1 for keys={`a`, `b`}, minDiff={0, 0}, maxCounts={1, 1}, intervals={1000, 500} and sets = { {}, { 1 fresh item } }', function ()
    local mock = function ()
      local m = {
        times = 0;
      }
      local redis = {
        call = function (...)
          m.times = m.times + 1;
          if m.times == 1 then
            assert.same('zremrangebyscore', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(0, select(3, ...));
            assert.same(2000, select(4, ...));
          elseif m.times == 2 then
            assert.same('zrange', select(1, ...));
            return { };
          elseif m.times == 3 then
            assert.same('zremrangebyscore', select(1, ...));
            assert.same('b', select(2, ...));
            assert.same(0, select(3, ...));
            assert.same(2500, select(4, ...));
          elseif m.times == 4 then
            assert.same('zrange', select(1, ...));
            return { '2501 1', '2501' };
          elseif m.times == 5 then
            assert.same('zadd', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(now, select(3, ...));
            assert.same(now .. ' ' .. 1, select(4, ...));
          elseif m.times == 6 then
            assert.same('expire', select(1, ...));
            assert.same('a', select(2, ...));
          elseif m.times == 7 then
            assert.same('zadd', select(1, ...));
            assert.same('b', select(2, ...));
            assert.same(now, select(3, ...));
            assert.same(now .. ' ' .. 1, select(4, ...));
          elseif m.times == 8 then
            assert.same('expire', select(1, ...));
            assert.same('b', select(2, ...));
          else
            error('Unexpected call: ' .. select(1, ...));
          end
        end
      }
      m.redis = redis;
      return m;
    end
    it('should record and limit for 1000 ms in uniform mode', function ()
      local m = mock();
      local result = limit_rate(m.redis, MODE_UNIFORM, 1, now, { 'a', 'b' }, {
        { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 },
        { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 500 }
      });
      assert.same({ -1, 1, 1000 }, result);
      assert.same(8, m.times);
    end);
    it('should discard and limit for 1 ms in binary mode', function ()
      local m = mock();
      local result = limit_rate(m.redis, MODE_BINARY, 1, now, { 'a', 'b' }, {
        { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 },
        { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 500 }
      });
      assert.same({ 0, 0, 1 }, result);
      assert.same(4, m.times);
    end);
    it('should discard and limit for 1 ms in nary mode', function ()
      local m = mock();
      local result = limit_rate(m.redis, MODE_NARY, 1, now, { 'a', 'b' }, {
        { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 1000 },
        { minDiff = 0, maxCount = 1, bucketInterval = 1, numberOfBuckets = 500 }
      });
      assert.same({ 0, 0, 1 }, result);
      assert.same(4, m.times);
    end);
  end);
  describe('inserting 2 in batch for keys={`a`}, minDiff={0}, maxCounts={2}, intervals={1000} and set has a fresh item', function ()
    local mock = function (howMany)
      local m = {
        times = 0;
      }
      local redis = {
        call = function (...)
          m.times = m.times + 1;
          if m.times == 1 then
            assert.same('zremrangebyscore', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(0, select(3, ...));
            assert.same(2000, select(4, ...));
          elseif m.times == 2 then
            assert.same('zrange', select(1, ...));
            return { '2001 1', '2001' };
          elseif m.times == 3 then
            assert.same('zadd', select(1, ...));
            assert.same('a', select(2, ...));
            assert.same(now, select(3, ...));
            assert.same(now .. ' ' .. howMany, select(4, ...));
          elseif m.times == 4 then
            assert.same('expire', select(1, ...));
            assert.same('a', select(2, ...));
          else
            error('Unexpected call: ' .. select(1, ...));
          end
        end
      }
      m.redis = redis;
      return m;
    end
    it('should record both and limit for 1000 ms in uniform mode', function ()
      local m = mock(2);
      local result = limit_rate(m.redis, MODE_UNIFORM, 2, now, { 'a' }, { { minDiff = 0, maxCount = 2, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ -1, 2, 1000 }, result);
      assert.same(4, m.times);
    end);
    it('should discard and limit for 1 ms in binary mode', function ()
      local m = mock(2);
      local result = limit_rate(m.redis, MODE_BINARY, 2, now, { 'a' }, { { minDiff = 0, maxCount = 2, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 1, 0, 1 }, result);
      assert.same(2, m.times);
    end);
    it('should record one and limit for 1000 ms in nary mode', function ()
      local m = mock(1);
      local result = limit_rate(m.redis, MODE_NARY, 2, now, { 'a' }, { { minDiff = 0, maxCount = 2, bucketInterval = 1, numberOfBuckets = 1000 } });
      assert.same({ 0, 1, 1000 }, result);
      assert.same(4, m.times);
    end);
  end);

end);
