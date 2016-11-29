var async = require('async');
var assert = require('assert');
var BigNumber = require('bignumber.js');
var sha256 = require('js-sha256').sha256;

function sign(web3, address, value, callback) {
  web3.eth.sign(address, value, (err, sig) => {
    if (!err) {
      try {
        var r = sig.slice(0, 66);
        var s = '0x' + sig.slice(66, 130);
        var v = parseInt('0x' + sig.slice(130, 132), 16);
        if (sig.length<132) {
          //web3.eth.sign shouldn't return a signature of length<132, but if it does...
          sig = sig.slice(2);
          r = '0x' + sig.slice(0, 64);
          s = '0x00' + sig.slice(64, 126);
          v = parseInt('0x' + sig.slice(126, 128), 16);
        }
        if (v!=27 && v!=28) v+=27;
        callback(undefined, {r: r, s: s, v: v});
      } catch (err) {
        callback(err, undefined);
      }
    } else {
      callback(err, undefined);
    }
  });
}

function send(method, params, callback) {
  if (typeof params == "function") {
    callback = params;
    params = [];
  }

  web3.currentProvider.sendAsync({
    jsonrpc: "2.0",
    method: method,
    params: params || [],
    id: new Date().getTime()
  }, callback);
};

contract('Contribution', (accounts) => {

  // Solidity constants
  const hours = 3600;
  const weeks = 3600*24*7;
  const ether = new BigNumber(Math.pow(10,18));

  // Contract constants
  const ETHER_CAP = 1800000 * ether; // max amount raised during contribution
  const MIN_CONTRIBUTION_DURATION = 1 * hours; // min amount in seconds of contribution period
  const MAX_CONTRIBUTION_DURATION = 8 * weeks; // max amount in seconds of contribution period
  const MAX_TOTAL_TOKEN_AMOUNT = 1971000; // max amount of total tokens raised during contribution
  const ICED_ETHER_CAP = ETHER_CAP * 40 / 100 ; // iced means untradeable untill genesis blk or two years
  const LIQUID_ETHER_CAP = ETHER_CAP * 60 / 100; // liquid means tradeable
  const BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // max iced allocation for btcs
  const MELONPORT_STAKE_MELON = 1200; // 12% of all created melon token allocated to melonport
  const MELONPORT_STAKE_DOT = 75; // 0.75% of all created dot token allocated to melonport
  const PARITY_STAKE_MELON = 300; // 3% of all created melon token minted to "this" contract
  const PARITY_STAKE_DOT = 1425; // 14.25% of all created dot token minted to "this" contract
  const DIVISOR_STAKE = 10000; // stakes are divided by this number
  const ICED_RATE = 1125; // One iced tier, remains constant for the duration of the contribution
  const LIQUID_RATE_FIRST = 1075; // Four liquid tiers, each valid for two weeks
  const LIQUID_RATE_SECOND = 1050;
  const LIQUID_RATE_THIRD = 1025;
  const LIQUID_RATE_FOURTH = 1000;
  const DIVISOR_RATE = 1000; // price rates are divided by this number

  //globals
  let contributionContract;
  let melonContract;
  let dotContract;
  let contributionContractAddress;
  let testCases;

  const melonport = accounts[0];
  const parity = accounts[1];
  const btcs = accounts[2];
  const signer = accounts[3];

  const FOUNDER_LOCKUP = 2252571;
  const TRANSFER_LOCKUP = 370285;
  var startTime;
  var endTime;
  var timeTravelOneYearForward = 52 * weeks;

  before('Check accounts', (done) => {
    assert.equal(accounts.length, 10);
    done();
  });

  it('Set startTime as now', (done) => {
    web3.eth.getBlock('latest', function(err, result) {
      startTime = result.timestamp;
      endTime = startTime + 8*weeks;
      done();
    });
  });

  it('Set up test cases', (done) => {
    testCases = [];
    const numBlocks = 8;
    for (i = 0; i < numBlocks; i++) {
      const blockNumber = Math.round(startTime + (endTime-startTime)*i/(numBlocks-1));
      let expectedPrice;
      if (blockNumber>=startTime && blockNumber<startTime + 2*weeks) {
        expectedPrice = 1075;
      } else if (blockNumber>=startTime + 2*weeks && blockNumber < startTime + 4*weeks) {
        expectedPrice = 1050;
      } else if (blockNumber>=startTime + 4*weeks && blockNumber < startTime + 6*weeks) {
        expectedPrice = 1025;
      } else if (blockNumber>=startTime + 6*weeks && blockNumber < startTime + 8*weeks) {
        expectedPrice = 1000;
      } else {
        expectedPrice = 0;
      }
      const accountNum = Math.max(1,Math.min(i+1, accounts.length-1));
      const account = accounts[accountNum];
      expectedPrice = Math.round(expectedPrice);
      testCases.push(
        {
          accountNum: accountNum,
          blockNumber: blockNumber,
          expectedPrice: expectedPrice,
          account: account,
        }
      );
      console.log(testCases[i])
    }
    done();
  });

  it('Sign test cases', (done) => {
    async.mapSeries(testCases,
      function(testCase, callbackMap) {
        const hash = '0x' + sha256(new Buffer(testCase.account.slice(2),'hex'));
        sign(web3, signer, hash, (err, sig) => {
          testCase.v = sig.v;
          testCase.r = sig.r;
          testCase.s = sig.s;
          callbackMap(null, testCase);
        });
      },
      function(err, newTestCases) {
        testCases = newTestCases;
        done();
      }
    );
  });

  it('Deploy smart contracts', (done) => {
    Contribution.new(melonport, parity, btcs, signer, startTime).then((result) => {
      contributionContract = result;
      contributionContractAddress = contributionContract.address;
      return contributionContract.melonToken();
    }).then((result) => {
      melonContract = MelonToken.at(result);
      return melonContract.creator()
    }).then((result) => {
      return contributionContract.dotToken();
    }).then((result) => {
      dotContract = DotToken.at(result);
      done();
    });
  });

  it('Check locked melon and dot token and allocation to companies', (done) => {
    melonContract.lockedBalanceOf(melonport).then((result) => {
      console.log(result.toNumber());
      return melonContract.lockedBalanceOf(parity);
    }).then((result) => {
      console.log(result.toNumber());
      return dotContract.lockedBalanceOf(melonport);
    }).then((result) => {
      console.log(result.toNumber());
      return dotContract.lockedBalanceOf(parity);
    }).then((result) => {
      console.log(result.toNumber());
      done();
    })
  });

  it('Time travel one year forward', function(done) {
    // Adjust time
    send("evm_increaseTime", [timeTravelOneYearForward], (err, result) => {
      if (err) return done(err);

      // Mine a block so new time is recorded.
      send("evm_mine", (err, result) => {
        if (err) return done(err);

        web3.eth.getBlock('latest', (err, block) => {
          if(err) return done(err)
          var secondsJumped = block.timestamp - startTime

          // Somehow it jumps an extra 18 seconds, ish, when run inside the whole
          // test suite. It might have something to do with when the before block
          // runs and when the test runs. Likely the last block didn't occur for
          // awhile.
          assert(secondsJumped >= timeTravelOneYearForward)
          done()
        })
      })
    })
  });

});
