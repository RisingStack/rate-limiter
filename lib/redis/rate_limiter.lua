local MODE_UNIFORM = 0;
local MODE_BINARY = 1;
local MODE_NARY = 2;

local parseAndCount = function (zrangewithscores)
  local count = 0;
  local last = zrangewithscores[#zrangewithscores];
  for i = #zrangewithscores, 1, -1 do
    if (i % 2 == 1) then
        local iter = string.gmatch(zrangewithscores[i], '%S+');
        iter();
        local increment = tonumber(iter());
        count = count + increment;
        zrangewithscores[i] = increment;
    end
  end
  return count
end

local limit_rate = function (redis, mode, increment, now, keys, specs)
  local data = {};
  -- 1
  for i = 1, #keys do
    data[i] = {};
    local spec = specs[i];
    -- 1.1
    redis.call('zremrangebyscore', keys[i], 0, now - (spec.numberOfBuckets * spec.bucketInterval + math.floor(spec.bucketInterval / 2)));
    local set = redis.call('zrange', keys[i], 0, -1, 'withscores');
    -- 1.2
    data[i].count = parseAndCount(set);
    data[i].set = set;
  end

  -- 2
  local actionsRemaining = math.huge;
  for i = 1, #keys do
    actionsRemaining = math.min(actionsRemaining, specs[i].maxCount - data[i].count);
  end

  -- 3
  local acknowledged = 0;
  local minDiffWait = 0;
  if mode == MODE_UNIFORM or mode == MODE_BINARY and actionsRemaining - increment >= 0 or mode == MODE_NARY and actionsRemaining - 1 >= 0 then
    -- 3.1
    -- 3.1.1
    for i = 1, #keys do
      minDiffWait = math.max(minDiffWait, specs[i].minDiff);
    end

    -- 3.1.2
    if mode == MODE_NARY then
      acknowledged = math.min(increment, actionsRemaining);
    else
      acknowledged = increment;
    end

  else
    -- 3.2
    for i = 1, #keys do
      local set = data[i].set
      if (set[#set] ~= nil) then
        minDiffWait = math.max(minDiffWait, set[#set] - now + specs[i].minDiff);
      end
    end
  end

  -- 4
  local intervalWait = {};
  for i = 1, #keys do
    -- 4.1
    local datum = data[i];
    local set = datum.set;
    local spec = specs[i];
    if acknowledged > 0 then
      local startTime = math.ceil((spec.numberOfBuckets * spec.bucketInterval + math.floor(spec.bucketInterval / 2)) / 1000000);
      -- 4.1.1
      if (set[#set] ~= nil and set[#set] + spec.bucketInterval >= now) then
        redis.call('zrem', keys[i], set[#set], set[#set] .. ' ' .. set[#set - 1]);
        redis.call('zadd', keys[i], set[#set], set[#set] .. ' ' .. set[#set - 1] + acknowledged);
        redis.call('expire', keys[i], startTime);
        -- update in-memory representation as well
        set[#set - 1] = set[#set - 1] + acknowledged;
      else
        local new = now;
        if (set[#set] ~= nil) then
          new = math.floor((now - set[#set]) / spec.bucketInterval) * spec.bucketInterval + set[#set];
        end
        redis.call('zadd', keys[i], new, new .. ' ' .. acknowledged);
        redis.call('expire', keys[i], startTime);
        -- update in-memory representation as well
        local size = #set;
        set[size + 1] = acknowledged;
        set[size + 2] = new;
      end
      datum.count = datum.count + acknowledged;
    end
    local j = 1;
    -- 4.2
    local sum = datum.count;
    local limit = -math.huge;
    while sum + increment > spec.maxCount and j <= #set / 2 do
      sum = sum - set[j * 2 - 1];
      limit = tonumber(set[j * 2]);
      j = j + 1;
    end
    intervalWait[i] = limit + spec.bucketInterval * spec.numberOfBuckets - now
  end
  local wait = minDiffWait;
  for i = 1, #keys do
    wait = math.max(wait, intervalWait[i]);
  end
  return {
    actionsRemaining - acknowledged,
    acknowledged,
    wait
  }
end

if KEYS ~= nil then
  local specs = {};
  for i = 1, #KEYS do
    specs[i] = {};
    specs[i].minDiff = tonumber(ARGV[3 + i]);
    specs[i].maxCount = tonumber(ARGV[3 + #KEYS + i]);
    specs[i].bucketInterval = tonumber(ARGV[3 + 2 * #KEYS + i]);
    specs[i].numberOfBuckets = tonumber(ARGV[3 + 3 * #KEYS + i]);
  end
  return limit_rate(redis, tonumber(ARGV[1]), tonumber(ARGV[2]), tonumber(ARGV[3]), KEYS, specs);
else
  return limit_rate;
end
