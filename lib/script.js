'use strict';

var fs = require('fs');
var crypto = require('crypto');

function Script (str) {
  var hash = crypto.createHash('sha1');
  hash.update(str, 'utf8');
  this.str = str;
  this.sha1 = hash.digest('hex');
}

Script.fromPath = function (path, cb) {
  fs.readFile(path, {encoding: 'utf8'}, function (err, str) {
    if (err) {
      return cb(err);
    }
    var script = new Script(str);
    return cb(null, script);
  });
};

Script.prototype.eval = function (redis, args, cb) {
  var self = this;
  redis.evalsha([this.sha1].concat(args), function (err, res) {
    if (err && err.toString().indexOf('NOSCRIPT') === -1) {
      return cb(err);
    } else if (err) {
      return redis.eval([self.str].concat(args), cb);
    }
    return cb(null, res);
  });
};


module.exports = Script;
