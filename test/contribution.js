const async = require('async');
const assert = require('assert');
const BigNumber = require('bignumber.js');
const sha256 = require('js-sha256').sha256;

function sign(web3, address, value, callback) {
  web3.eth.sign(address, value, (err, sig) => {
    if (!err) {
      try {
        let r = sig.slice(0, 66);
        let s = `0x${sig.slice(66, 130)}`;
        let v = parseInt(`0x${sig.slice(130, 132)}`, 16);
        if (sig.length < 132) {
          // web3.eth.sign shouldn't return a signature of length<132, but if it does...
          sig = sig.slice(2);
          r = `0x${sig.slice(0, 64)}`;
          s = `0x00${sig.slice(64, 126)}`;
          v = parseInt(`0x${sig.slice(126, 128)}`, 16);
        }
        if (v !== 27 && v !== 28) v += 27;
        callback(undefined, { r, s, v });
      } catch (tryErr) {
        callback(tryErr, undefined);
      }
    } else {
      callback(err, undefined);
    }
  });
}

function send(method, params, callback) {
  if (typeof params === 'function') {
    callback = params;
    params = [];
  }

  web3.currentProvider.sendAsync({
    jsonrpc: '2.0',
    method,
    params: params || [],
    id: new Date().getTime(),
  }, callback);
}

contract('Contribution', (accounts) => {
  // Solidity constants
  const hours = 3600;
  const weeks = 24 * 7 * hours;
  const years = 52 * weeks;
  const ether = new BigNumber(Math.pow(10, 18));

  // Contribution constant fields
  const ETHER_CAP = 250000 * ether; // max amount raised during this contribution; targeted amount CHF 2.5MN
  const MAX_CONTRIBUTION_DURATION = 4 * weeks; // max amount in seconds of contribution period
  const BTCS_ETHER_CAP = ETHER_CAP * (25 / 100); // max iced allocation for btcs
  // Price Rates
  const PRICE_RATE_FIRST = 2000; // Four price tiers, each valid for two weeks
  const PRICE_RATE_SECOND = 1950;
  const PRICE_RATE_THIRD = 1900;
  const PRICE_RATE_FOURTH = 1850;
  const DIVISOR_PRICE = 1000; // Price rates are divided by this number
  // Addresses of Patrons
  const FOUNDER_ONE = '0x8cb08267c381d6339cab49b7bafacc9ce5a503a0';
  const FOUNDER_TWO = 0xF2;
  const EXT_COMPANY_ONE = '0x00779e0e4c6083cfd26dE77B4dbc107A7EbB99d2';
  const EXT_COMPANY_TWO = 0xC2;
  const EXT_COMPANY_THREE = 0xC3;
  const ADVISOR_ONE = 0xA1;
  const ADVISOR_TWO = '0x715a70a7c7d76acc8d5874862e381c1940c19cce';
  const ADVISOR_THREE = 0xA3;
  const AMBASSADOR_ONE = 0xE1;
  const AMBASSADOR_TWO = 0xE2;
  const AMBASSADOR_THREE = 0xE3;
  const AMBASSADOR_FOUR = 0xE4;
  const AMBASSADOR_FIVE = 0xE5;
  const AMBASSADOR_SIX = 0xE6;
  const AMBASSADOR_SEVEN = 0xE7;
  // Stakes of Patrons
  const MELONPORT_COMPANY_STAKE = 1000; // 10% of all created melon token allocated to melonport company
  const FOUNDER_STAKE = 465; // 4.65% of all created melon token allocated to founder
  const EXT_COMPANY_STAKE_ONE = 300; // 3% of all created melon token allocated to external company
  const EXT_COMPANY_STAKE_TWO = 100; // 1% of all created melon token allocated to external company
  const EXT_COMPANY_STAKE_THREE = 50; // 0.5% of all created melon token allocated to external company
  const ADVISOR_STAKE_ONE = 50; // 0.5% of all created melon token allocated to advisor
  const ADVISOR_STAKE_TWO = 25; // 0.25% of all created melon token allocated to advisor
  const ADVISOR_STAKE_THREE = 10; // 0.1% of all created melon token allocated to advisor
  const AMBASSADOR_STAKE = 5; // 0.05% of all created melon token allocated to ambassadors
  const DIVISOR_STAKE = 10000; // Stakes are divided by this number; Results to one basis point

  // Melon Token constant fields
  const name = 'Melon Token';
  const symbol = 'MLN';
  const decimals = 18;
  const THAWING_DURATION = 2 * years; // Time needed for iced tokens to thaw into liquid tokens
  const MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC = new BigNumber(1000000).times(new BigNumber(Math.pow(10, decimals))); // Max amount of tokens offered to the public
  const MAX_TOTAL_TOKEN_AMOUNT = new BigNumber(1250000).times((new BigNumber(Math.pow(10, decimals)))); // Max amount of total tokens raised during all contributions (includes stakes of patrons)

  // Test globals
  let contributionContract;
  let melonContract;
  let testCases;

  // Accounts
  const melonport = accounts[0];
  const btcs = accounts[1];
  const signer = accounts[2];

  let initalBlockTime;
  const startDelay = 1 * weeks;
  let startTime;
  let endTime;
  const numTestCases = 8;

  const snapshotIds = [];
  const timeTravelTwoYearForward = 2 * years;

  describe('PREPARATIONS', () => {
    before('Check accounts', (done) => {
      assert.equal(accounts.length, 10);
      done();
    });

    beforeEach('Checkpoint, so that we can revert later', (done) => {
      send('evm_snapshot', (err, result) => {
        if (!err) {
          snapshotIds.push(result.id);
        }
        done(err);
      });
    });

    it('Set startTime as now', (done) => {
      web3.eth.getBlock('latest', (err, result) => {
        initalBlockTime = result.timestamp;
        startTime = initalBlockTime + startDelay;
        endTime = startTime + (4 * weeks);
        done();
      });
    });

    it('Set up test cases', (done) => {
      testCases = [];
      for (i = 0; i < numTestCases; i += 1) {
        const timeSpacing = (endTime - startTime) / numTestCases;
        const blockTime = Math.round(startTime + (i * timeSpacing));
        let expectedPrice;
        if (blockTime >= startTime && blockTime < startTime + (1 * weeks)) {
          expectedPrice = 2000;
        } else if (blockTime >= startTime + (1 * weeks) && blockTime < startTime + (2 * weeks)) {
          expectedPrice = 1950;
        } else if (blockTime >= startTime + (2 * weeks) && blockTime < startTime + (3 * weeks)) {
          expectedPrice = 1900;
        } else if (blockTime >= startTime + (3 * weeks) && blockTime < endTime) {
          expectedPrice = 1850;
        } else {
          expectedPrice = 0;
        }
        const accountNum = Math.max(1, Math.min(i + 1, accounts.length - 1));
        const account = accounts[accountNum];
        expectedPrice = Math.round(expectedPrice);
        testCases.push({
          accountNum,
          blockTime,
          timeSpacing,
          expectedPrice,
          account,
        });
      }
      done();
    });

    it('Sign test cases', (done) => {
      async.mapSeries(testCases,
        (testCase, callbackMap) => {
          const hash = `0x${sha256(new Buffer(testCase.account.slice(2), 'hex'))}`;
          sign(web3, signer, hash, (err, sig) => {
            testCase.v = sig.v;
            testCase.r = sig.r;
            testCase.s = sig.s;
            callbackMap(null, testCase);
          });
        },
        (err, newTestCases) => {
          testCases = newTestCases;
          done();
        });
    });
  });

  describe('CONTRACT DEPLOYMENT', () => {
    it('Deploy Contribution contracts', (done) => {
      Contribution.new(melonport, btcs, signer, startTime).then((result) => {
        contributionContract = result;
        return contributionContract.melonToken();
      }).then((result) => {
        melonContract = MelonToken.at(result);
        done();
      });
    });

    it('Check Melon Token initialisation', (done) => {
      melonContract.MAX_TOTAL_TOKEN_AMOUNT().then((result) => {
        assert.equal(result, MAX_TOTAL_TOKEN_AMOUNT.toNumber());
        return melonContract.minter();
      })
      .then((result) => {
        assert.equal(result, contributionContract.address);
        return melonContract.melonport();
      })
      .then((result) => {
        assert.equal(result, melonport);
        return melonContract.startTime();
      })
      .then((result) => {
        assert.equal(result, startTime);
        return melonContract.endTime();
      })
      .then((result) => {
        assert.equal(result, endTime);
        done();
      });
    });

    it('Check premined allocation', (done) => {
      melonContract.balanceOf(melonport).then((result) => {
        console.log(`Melonport Balance ${result.toNumber()}`);
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(MELONPORT_COMPANY_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(FOUNDER_ONE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(FOUNDER_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(FOUNDER_TWO);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(FOUNDER_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(EXT_COMPANY_ONE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(EXT_COMPANY_STAKE_ONE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(EXT_COMPANY_TWO);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(EXT_COMPANY_STAKE_TWO).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(EXT_COMPANY_THREE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(EXT_COMPANY_STAKE_THREE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(ADVISOR_ONE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(ADVISOR_STAKE_ONE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(ADVISOR_TWO);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(ADVISOR_STAKE_TWO).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(ADVISOR_THREE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(ADVISOR_STAKE_THREE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_ONE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_TWO);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_THREE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_FOUR);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_FIVE);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_SIX);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(AMBASSADOR_SEVEN);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(AMBASSADOR_STAKE).div(DIVISOR_STAKE));
        return melonContract.totalSupply();
      })
      .then((result) => {
        console.log(`Melon Total Supply ${result.toNumber()}`);
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT.sub(MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC).toNumber());
        done();
      });
    });
  });

  describe('CONTRIBUTION', () => {
    it('Test BTCS access in time', (done) => {
      const testCase = {
        buyer: btcs,
        buy_for_how_much_ether: web3.toWei(2.1, 'ether'),
        recipient_of_melon: accounts[9],
        expected_price: PRICE_RATE_FIRST / DIVISOR_PRICE,
        expected_melon_amount: web3.toWei(2.1, 'ether') * (PRICE_RATE_FIRST / DIVISOR_PRICE),
      };

      // Balance Melonport
      web3.eth.getBalance(melonport, (err, initialBalance) => {
        contributionContract.btcsBuyRecipient(
          testCase.recipient_of_melon,
          { from: testCase.buyer, value: testCase.buy_for_how_much_ether })
        .then(() => melonContract.balanceOf(testCase.recipient_of_melon))
        .then((result) => {
          assert.equal(
            result.toNumber(),
            testCase.expected_melon_amount);
          web3.eth.getBalance(melonport, (errFinal, finalBalance) => {
            assert.equal(
              finalBalance.minus(initialBalance),
              testCase.buy_for_how_much_ether);
            done();
          });
        });
      });
    });

    it('Test buy too early', (done) => {
      const testCase = testCases[0];
      const amountToBuy = web3.toWei(2.1, 'ether');

      contributionContract.buy(
        testCase.v, testCase.r, testCase.s,
        { from: testCase.account, value: amountToBuy })
      // Gets executed if contract throws exception
      .catch(() => {
        melonContract.balanceOf(testCase.account)
        .then((result) => {
          assert.equal(
            result.toNumber(),
            0);
          done();
        });
      });
    });

    it('Test buying on behalf of a recipient', (done) => {
      done();
    });

    it('Test changing Melonport address', (done) => {
      done();
    });
  });
});
