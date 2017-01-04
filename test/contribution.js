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
  const weeks = 24 * 7 * hours;
  const years = 52 * weeks;
  const ether = new BigNumber(Math.pow(10, 18));

  // Contribution constant fields
  const ETHER_CAP = 250000 * ether; // max amount raised during this contribution; targeted amount CHF 2.5MN
  const MAX_CONTRIBUTION_DURATION = 4 * weeks; // max amount in seconds of contribution period
  const BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // max iced allocation for btcs
  // Price Rates
  const PRICE_RATE_FIRST = 2000; // Four price tiers, each valid for two weeks
  const PRICE_RATE_SECOND = 1950;
  const PRICE_RATE_THIRD = 1900;
  const PRICE_RATE_FOURTH = 1850;
  const DIVISOR_PRICE = 1000; // Price rates are divided by this number
  // Addresses of Patrons
  const FOUNDER_ONE = 0xF1;
  const FOUNDER_TWO = 0xF2;
  const EXT_COMPANY_ONE = 0xC1;
  const EXT_COMPANY_TWO = 0xC2;
  const ADVISOR_ONE = 0xA1;
  const ADVISOR_TWO = 0xA2;
  // Stakes of Patrons
  const DIVISOR_STAKE = 10000; // stakes are divided by this number; results to one basis point
  const MELONPORT_COMPANY_STAKE = 1000; // 12% of all created melon voucher allocated to melonport company
  const EXT_COMPANY_STAKE_ONE = 300; // 3% of all created melon voucher allocated to external company
  const EXT_COMPANY_STAKE_TWO = 100; // 1% of all created melon voucher allocated to external company
  const FOUNDER_STAKE = 450; // 4.5% of all created melon voucher allocated to founder
  const ADVISOR_STAKE_ONE = 50; // 0.5% of all created melon voucher allocated to advisor
  const ADVISOR_STAKE_TWO = 25; // 0.25% of all created melon voucher allocated to advisor

  // Melon Voucher constant fields
  const THAWING_DURATION = 2 * years; // time needed for iced vouchers to thaw into liquid vouchers
  const MAX_TOTAL_VOUCHER_AMOUNT = 1250000; // max amount of total vouchers raised during all contributions

  // Test globals
  let multisigContract;
  let contributionContract;
  let melonContract;
  let testCases;

  // Accounts
  const multiSigOwners = accounts.slice(0, 6);
  const requiredSignatures = 4;
  let melonport; // defined as multisigContract.address
  const btcs = accounts[1];
  const signer = accounts[2];

  var initalBlockTime;
  const startDelay = 1 * weeks;
  var startTime;
  var endTime;
  const numTestCases = 8;
  var timeSpacingTestCases;

  var snapshotIds = [];
  var timeTravelTwoYearForward = 2 * years;


  describe('PREPARATIONS', () => {
    before('Check accounts', (done) => {
      assert.equal(accounts.length, 10);
      done();
    });

    beforeEach("Checkpoint, so that we can revert later", (done) => {
      send("evm_snapshot", (err, result) => {
        if (!err) {
          snapshotIds.push(result.id);
        }
        done(err);
      });
    });

    it('Set startTime as now', (done) => {
      web3.eth.getBlock('latest', function(err, result) {
        initalBlockTime = result.timestamp;
        startTime = initalBlockTime + startDelay;
        endTime = startTime + 4*weeks;
        timeSpacingTestCases = (endTime - startTime) / (numTestCases - 1);
        done();
      });
    });

    it('Set up test cases', (done) => {
      testCases = [];
      for (i = 0; i < numTestCases; i++) {
        const blockTime = Math.round(startTime + i * timeSpacingTestCases);
        let expectedPrice;
        if (blockTime>=startTime && blockTime<startTime + 1*weeks) {
          expectedPrice = 2000;
        } else if (blockTime>=startTime + 1*weeks && blockTime < startTime + 2*weeks) {
          expectedPrice = 1950;
        } else if (blockTime>=startTime + 2*weeks && blockTime < startTime + 3*weeks) {
          expectedPrice = 1900;
        } else if (blockTime>=startTime + 3*weeks && blockTime < endTime) {
          expectedPrice = 1850;
        } else {
          expectedPrice = 0;
        }
        const accountNum = Math.max(1, Math.min(i + 1, accounts.length-1));
        const account = accounts[accountNum];
        expectedPrice = Math.round(expectedPrice);
        testCases.push(
          {
            accountNum: accountNum,
            blockTime: blockTime,
            expectedPrice: expectedPrice,
            account: account,
          }
        );
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
  });

  describe('CONTRACT DEPLOYMENT', () => {
    it('Deploy Multisig wallet', (done) => {
      MultiSigWallet.new(multiSigOwners, requiredSignatures).then((result) => {
        multisigContract = result;
        melonport = multisigContract.address;
        return multisigContract.requiredSignatures();
      }).then((result) => {
        assert.equal(result, requiredSignatures);
        done();
      });
    });

    it('Deploy Contribution contracts', (done) => {
      Contribution.new(melonport, btcs, signer, startTime).then((result) => {
        contributionContract = result;
        return contributionContract.melonVoucher();
      }).then((result) => {
        melonContract = MelonVoucher.at(result);
        done();
      });
    });

    it('Check Melon Voucher initialisation', (done) => {
      melonContract.MAX_TOTAL_VOUCHER_AMOUNT().then((result) => {
        assert.equal(result, MAX_TOTAL_VOUCHER_AMOUNT);
        return melonContract.minter();
      }).then((result) => {
        assert.equal(result, contributionContract.address);
        return melonContract.melonport();
      }).then((result) => {
        assert.equal(result, melonport);
        return melonContract.startTime();
      }).then((result) => {
        assert.equal(result, startTime);
        return melonContract.endTime();
      }).then((result) => {
        assert.equal(result, endTime)
        done();
      });
    });

    it('Check premined allocation', (done) => {
      melonContract.balanceOf(melonport).then((result) => {
        assert.equal(result.toNumber(), MELONPORT_COMPANY_STAKE * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        return melonContract.lockedBalanceOf(FOUNDER_ONE);
      }).then((result) => {
        assert.equal(result.toNumber(), FOUNDER_STAKE * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        return melonContract.lockedBalanceOf(FOUNDER_TWO);
      }).then((result) => {
        assert.equal(result.toNumber(), FOUNDER_STAKE * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        return melonContract.lockedBalanceOf(EXT_COMPANY_ONE);
      }).then((result) => {
        assert.equal(result.toNumber(), EXT_COMPANY_STAKE_ONE * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        return melonContract.lockedBalanceOf(EXT_COMPANY_TWO);
      }).then((result) => {
        assert.equal(result.toNumber(), EXT_COMPANY_STAKE_TWO * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        return melonContract.lockedBalanceOf(ADVISOR_ONE);
      }).then((result) => {
        assert.equal(result.toNumber(), ADVISOR_STAKE_ONE * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        return melonContract.lockedBalanceOf(ADVISOR_TWO);
      }).then((result) => {
        assert.equal(result.toNumber(), ADVISOR_STAKE_TWO * MAX_TOTAL_VOUCHER_AMOUNT / DIVISOR_STAKE);
        done();
      })
    });
  });

  describe('CONTRIBUTION', () => {

    it('Test changing Melonport address', (done) => {
      done();
    });

    it('Test BTCS access', (done) => {
      done();
    });

  });

  describe('SETTING OF NEW MINTER', () => {
    it('Time travel two years forward', (done) => {
      // Adjust time
      send("evm_increaseTime", [timeTravelTwoYearForward], (err, result) => {
        if (err) return done(err);

        // Mine a block so new time is recorded.
        send("evm_mine", (err, result) => {
          if (err) return done(err);

          web3.eth.getBlock('latest', (err, block) => {
            if(err) return done(err)
            var secondsJumped = block.timestamp - initalBlockTime;

            // Somehow it jumps an extra 18 seconds, ish, when run inside the whole
            // test suite. It might have something to do with when the before block
            // runs and when the test runs. Likely the last block didn't occur for
            // awhile.
            assert(secondsJumped >= timeTravelTwoYearForward)
            done()
          })
        })
      })
    });
  });
});
