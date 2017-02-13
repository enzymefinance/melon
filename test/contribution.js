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
  const ETHER_CAP = 227000 * ether; // max amount raised during this contribution; targeted amount CHF 2.5MN
  const MAX_CONTRIBUTION_DURATION = 4 * weeks; // max amount in seconds of contribution period
  const BTCS_ETHER_CAP = ETHER_CAP * 25 / 100; // max iced allocation for btcs
  // Price Rates
  const PRICE_RATE_FIRST = 2200; // Four price tiers, each valid for two weeks
  const PRICE_RATE_SECOND = 2150;
  const PRICE_RATE_THIRD = 2100;
  const PRICE_RATE_FOURTH = 2050;
  const DIVISOR_PRICE = 1000; // Price rates are divided by this number
  // Addresses of Patrons
  const FOUNDER_ONE = '0x009beAE06B0c0C536ad1eA43D6f61DCCf0748B1f';
  const FOUNDER_TWO = '0xB1EFca62C555b49E67363B48aE5b8Af3C7E3e656';
  const EXT_COMPANY_ONE = '0x00779e0e4c6083cfd26dE77B4dbc107A7EbB99d2';
  const EXT_COMPANY_TWO = '0x1F06B976136e94704D328D4d23aae7259AaC12a2';
  const EXT_COMPANY_THREE = '0xDD91615Ea8De94bC48231c4ae9488891F1648dc5';
  const ADVISOR_ONE = '0x0001126FC94AE0be2B685b8dE434a99B2552AAc3';
  const ADVISOR_TWO = '0x4f2AF8d2614190Cc80c6E9772B0C367db8D9753C';
  const ADVISOR_THREE = '0x715a70a7c7d76acc8d5874862e381c1940c19cce';
  const ADVISOR_FOUR = '0x8615F13C12c24DFdca0ba32511E2861BE02b93b2';
  const AMBASSADOR_ONE = '0xd3841FB80CE408ca7d0b41D72aA91CA74652AF47';
  const AMBASSADOR_TWO = '0xDb775577538018a689E4Ad2e8eb5a7Ae7c34722B';
  const AMBASSADOR_THREE = '0xaa967e0ce6A1Ff5F9c124D15AD0412F137C99767';
  const AMBASSADOR_FOUR = '0x910B41a6568a645437bC286A5C733f3c501d8c88';
  const AMBASSADOR_FIVE = '0xb1d16BFE840E66E3c81785551832aAACB4cf69f3';
  const AMBASSADOR_SIX = '0x5F6ff16364BfEf546270325695B6e90cc89C497a';
  const AMBASSADOR_SEVEN = '0x58656e8872B0d266c2acCD276cD23F4C0B5fEfb9';
  const SPECIALIST_ONE = '0x8a815e818E617d1f93BE7477D179258aC2d25310';
  const SPECIALIST_TWO = '0x1eba6702ba21cfc1f6c87c726364b60a5e444901';
  const SPECIALIST_THREE = '0x82eae6c30ed9606e2b389ae65395648748c6a17f';
  // Stakes of Patrons
  const MELONPORT_COMPANY_STAKE = 1000; // 10% of all created melon token allocated to melonport company
  const FOUNDER_STAKE = 445; // 4.45% of all created melon token allocated to founder
  const EXT_COMPANY_STAKE_ONE = 150; // 1.5% of all created melon token allocated to external company
  const EXT_COMPANY_STAKE_TWO = 100; // 1% of all created melon token allocated to external company
  const EXT_COMPANY_STAKE_THREE = 50; // 0.5% of all created melon token allocated to external company
  const ADVISOR_STAKE_ONE = 150; // 1.5% of all created melon token allocated to advisor
  const ADVISOR_STAKE_TWO = 50; // 0.5% of all created melon token allocated to advisor
  const ADVISOR_STAKE_THREE = 25; // 0.25% of all created melon token allocated to advisor
  const ADVISOR_STAKE_FOUR = 10; // 0.1% of all created melon token allocated to advisor
  const AMBASSADOR_STAKE = 5; // 0.05% of all created melon token allocated to ambassadors
  const SPECIALIST_STAKE_ONE = 25; // 0.25% of all created melon token allocated to specialist
  const SPECIALIST_STAKE_TWO = 10; // 0.1% of all created melon token allocated to specialist
  const SPECIALIST_STAKE_THREE = 5; // 0.05% of all created melon token allocated to specialist
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
  const twoYearsTime = 2 * years;

  describe('PREPARATIONS', () => {
    before('Check accounts', (done) => {
      assert.equal(accounts.length, 10);
      done();
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
          expectedPrice = PRICE_RATE_FIRST;
        } else if (blockTime >= startTime + (1 * weeks) && blockTime < startTime + (2 * weeks)) {
          expectedPrice = PRICE_RATE_SECOND;
        } else if (blockTime >= startTime + (2 * weeks) && blockTime < startTime + (3 * weeks)) {
          expectedPrice = PRICE_RATE_THIRD;
        } else if (blockTime >= startTime + (3 * weeks) && blockTime < endTime) {
          expectedPrice = PRICE_RATE_FOURTH
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
          amountToBuy: web3.toWei(2.1, 'ether'),
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
        return melonContract.lockedBalanceOf(ADVISOR_FOUR);
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(ADVISOR_STAKE_FOUR).div(DIVISOR_STAKE));
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
        return melonContract.lockedBalanceOf(SPECIALIST_ONE);
        })
        .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(SPECIALIST_STAKE_ONE).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(SPECIALIST_TWO);
        })
        .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(SPECIALIST_STAKE_TWO).div(DIVISOR_STAKE));
        return melonContract.lockedBalanceOf(SPECIALIST_THREE);
        })
        .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(SPECIALIST_STAKE_THREE).div(DIVISOR_STAKE));
        return melonContract.totalSupply();
      })
      .then((result) => {
        assert.equal(
          result.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT.sub(MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC).toNumber());
        done();
      });
    });
  });

  describe('BEFORE PUBLIC CONTRIBUTION', () => {
    it('Test BTCS access in time', (done) => {
      // TODO cleanup
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

    it('Test buying too early', (done) => {
      const testCase = testCases[0];
      contributionContract.buy(
        testCase.v, testCase.r, testCase.s,
        { from: testCase.account, value: testCase.amountToBuy })
      .catch(() => {
        // Gets executed if contract throws exception
        melonContract.balanceOf(testCase.account)
        .then((result) => {
          assert.equal(
            result.toNumber(),
            0);
          done();
        });
      });
    });
  });

  describe('START OF PUBLIC CONTRIBUTION', () => {
    before('Time travel to startTime', (done) => {
      web3.eth.getBlock('latest', (err, result) => {
        send('evm_increaseTime', [startTime - result.timestamp], (err, result) => {
          assert.equal(err, null);
          send('evm_mine', [], (err, result) => {
            assert.equal(err, null);
            done();
          });
        });
      });
    });

    it('Test BTCS access too late', (done) => {
      const testCase = {
        buyer: btcs,
        buy_for_how_much_ether: web3.toWei(2.1, 'ether'),
        recipient_of_melon: accounts[8],
        expected_price: PRICE_RATE_FIRST / DIVISOR_PRICE,
        expected_melon_amount: 0, // Too late
      };
      contributionContract.btcsBuyRecipient(
        testCase.recipient_of_melon,
        { from: testCase.buyer, value: testCase.buy_for_how_much_ether })
      .catch(() => {
        // Gets executed if contract throws exception
        melonContract.balanceOf(testCase.recipient_of_melon)
        .then((result) => {
          assert.equal(
            result.toNumber(),
            testCase.expected_melon_amount);
          done();
        });
      });
    });

    it('Test buying and buyingRecipient in time', (done) => {
      let amountBought = new BigNumber(0);
      web3.eth.getBalance(melonport, (err, initialBalance) => {
        async.eachSeries(testCases,
          (testCase, callbackEach) => {
            web3.eth.getBlock('latest', (err, result) => {
              send('evm_increaseTime', [testCase.blockTime - result.timestamp], (err, result) => {
                assert.equal(err, null);
                send('evm_mine', [], (err, result) => {
                  assert.equal(err, null);
                  contributionContract.buy(
                    testCase.v, testCase.r, testCase.s,
                    { from: testCase.account, value: testCase.amountToBuy })
                  .then(() => {
                    amountBought = amountBought.add(testCase.amountToBuy);
                    return melonContract.balanceOf(testCase.account);
                  }).then((result) => {
                    // console.log(`Melon amount expected: ${web3.fromWei((new BigNumber(testCase.amountToBuy)).times(testCase.expectedPrice / DIVISOR_PRICE), 'ether')}`);
                    // console.log(`Melon amount actual:   ${web3.fromWei(result.toNumber(), 'ether')}`);
                    assert.equal(
                      result.toNumber(),
                      (new BigNumber(testCase.amountToBuy)).times(testCase.expectedPrice / DIVISOR_PRICE));
                    callbackEach();
                  });
                });
              });
            });
          },
          (err) => {
            web3.eth.getBalance(melonport, (err, finalBalance) => {
              // console.log(`ETH received: ${web3.fromWei(finalBalance.minus(initialBalance).toNumber(), 'ether')}`);
              assert.equal(
                finalBalance.minus(initialBalance).toNumber(),
                amountBought.toNumber()
              );
              done();
            });
          }
        );
      });
    });

    it('Test buying with raw transaction', (done) => {
      const sender = testCases[7];
      const amount = web3.toWei(1.2, 'ether');

      const sha3Hash = web3.sha3('buy(uint8,bytes32,bytes32)');
      const methodId = `${sha3Hash.slice(2, 10)}`;
      // Big-endian encoding of uint, padded on the higher-order (left) side with zero-bytes such that the length is a multiple of 32 bytes
      const vHex = web3.fromDecimal(sender.v).slice(2);
      const v = `${'0'.repeat(64 - vHex.length)}${vHex}`;
      const r = `${sender.r.slice(2)}`;
      const s = `${sender.s.slice(2)}`;
      const data = `${methodId}${v}${r}${s}`;

      let initialBalance;
      melonContract.balanceOf(sender.account).then((result) => {
        initialBalance = result;
        web3.eth.sendTransaction(
          { from: sender.account, to: contributionContract.address, data, value: amount }, (err) => {
            if (!err) {
              melonContract.balanceOf(sender.account)
              .then((finalBalance) => {
                assert.equal(
                  finalBalance.toNumber(),
                  initialBalance.plus((sender.expectedPrice / DIVISOR_PRICE) * amount).toNumber());
                done();
              });
            } else {
              done(err);
            }
          });
      });
    });

    it('Test buying with raw transaction - eth balance', (done) => {
      const sender = testCases[7];
      const amount = web3.toWei(1.2, 'ether');

      const sha3Hash = web3.sha3('buy(uint8,bytes32,bytes32)');
      const methodId = `${sha3Hash.slice(2, 10)}`;
      // Big-endian encoding of uint, padded on the higher-order (left) side with zero-bytes such that the length is a multiple of 32 bytes
      const vHex = web3.fromDecimal(sender.v).slice(2);
      const v = `${'0'.repeat(64 - vHex.length)}${vHex}`;
      const r = `${sender.r.slice(2)}`;
      const s = `${sender.s.slice(2)}`;
      const data = `${methodId}${v}${r}${s}`;

      // Balance Melonport
      const gasEstimate = web3.eth.estimateGas(
        { from: sender.account, to: contributionContract.address, data, value: amount });
      web3.eth.getBalance(sender.account, (err, initialBalance) => {
        if (err) done(err);
        web3.eth.sendTransaction(
          { from: sender.account, to: contributionContract.address, data, value: amount },
          (err) => {
            if (!err) {
              web3.eth.getBalance(sender.account, (errFinal, finalBalance) => {
                assert.equal(
                  finalBalance.toNumber(),
                  initialBalance.minus(amount).minus(gasEstimate).plus(100000));
                done();
              });
            } else {
              done(err);
            }
          });
      });
    });


    it('Test changing Melonport and Minter address in Melon Token', (done) => {
      melonContract.changeMelonportAddress(accounts[1], { from: melonport })
      .then(() => melonContract.melonport())
      .then((result) => {
        assert.equal(
          result,
          accounts[1]);
        return melonContract.changeMintingAddress(accounts[2], { from: accounts[1] });
      })
      .then(() => melonContract.minter())
      .then((result) => {
        assert.equal(
          result,
          accounts[2]);
        done();
      });
    });

    it('Test changing Melonport and Minter address in Contribution Contract', (done) => {
      contributionContract.changeMelonportAddress(accounts[1], { from: melonport })
      .then(() => melonContract.melonport())
      .then((result) => {
        assert.equal(
          result,
          accounts[1]);
        done();
      });
    });

    it('Test token transfer too early', (done) => {
      const sender = testCases[0];
      const recipient = testCases[1];
      const amount = web3.toWei(1.2, 'ether');

      let initialBalanceSender;
      let initialBalanceRecipient;
      melonContract.balanceOf(sender.account).then((result) => {
        initialBalanceSender = result;
        return melonContract.balanceOf(recipient.account);
      })
      .then((result) => {
        initialBalanceRecipient = result;
        melonContract.transfer(recipient.account, amount,
          { from: sender.account })
        .catch(() => {
          melonContract.balanceOf(sender.account)
          .then((finalBalanceSender) => {
            assert.equal(
              finalBalanceSender.toNumber(),
              initialBalanceSender.toNumber());
            return melonContract.balanceOf(recipient.account);
          })
          .then((finalBalanceRecipient) => {
            assert.equal(
              finalBalanceRecipient.toNumber(),
              initialBalanceRecipient.toNumber());
            done();
          });
        });
      });
    });
  });

  describe('PAST END OF PUBLIC CONTRIBUTION', () => {
    before('Time travel to endTime', (done) => {
      web3.eth.getBlock('latest', (err, result) => {
        send('evm_increaseTime', [(endTime - result.timestamp) + 1], (err, result) => {
          assert.equal(err, null);
          send('evm_mine', [], (err, result) => {
            assert.equal(err, null);
            done();
          });
        });
      });
    });

    it('Test buying too late', (done) => {
      const sender = testCases[0];
      let initialBalance;
      melonContract.balanceOf(sender.account)
      .then((result) => {
        initialBalance = result.toNumber();
        return contributionContract.buy(
          sender.v, sender.r, sender.s,
          { from: sender.account, value: sender.amountToBuy });
      })
      .catch(() => {
        melonContract.balanceOf(sender.account)
        .then((result) => {
          assert.equal(
            result.toNumber(),
            initialBalance);
          done();
        });
      });
    });

    it('Test token transfer in time', (done) => {
      const sender = testCases[0];
      const recipient = testCases[1];
      const amount = web3.toWei(1.2, 'ether');

      let initialBalanceSender;
      let initialBalanceRecipient;
      melonContract.balanceOf(sender.account).then((result) => {
        initialBalanceSender = result;
        return melonContract.balanceOf(recipient.account);
      })
      .then((result) => {
        initialBalanceRecipient = result;
        return melonContract.transfer(recipient.account, amount,
          { from: sender.account });
      })
      .then(() => melonContract.balanceOf(sender.account))
      .then((finalBalanceSender) => {
        assert.equal(
          finalBalanceSender.toNumber(),
          initialBalanceSender.minus(amount).toNumber());
        return melonContract.balanceOf(recipient.account);
      })
      .then((finalBalanceRecipient) => {
        assert.equal(
          finalBalanceRecipient.toNumber(),
          initialBalanceRecipient.plus(amount).toNumber());
        done();
      });
    });
  });

  describe('TWO YEARS AFTER CONTRIBUTION', () => {
    before('Time travel to endTime', (done) => {
      web3.eth.getBlock('latest', (err, result) => {
        send('evm_increaseTime', [(endTime + (twoYearsTime * 1.01)) - result.timestamp], (err, result) => {
          assert.equal(err, null);
          send('evm_mine', [], (err, result) => {
            assert.equal(err, null);
            done();
          });
        });
      });
    });

    it('Test unthawing tokens of patrons', (done) => {
      const sender = EXT_COMPANY_ONE;
      let lockedBalanceOfSender;
      melonContract.lockedBalanceOf(sender).then((result) => {
        lockedBalanceOfSender = result;
        assert.equal(
          lockedBalanceOfSender.toNumber(),
          MAX_TOTAL_TOKEN_AMOUNT_OFFERED_TO_PUBLIC.times(EXT_COMPANY_STAKE_ONE).div(DIVISOR_STAKE));
        return melonContract.unlockBalance(sender, { from: melonport });
      })
      .then(() => melonContract.balanceOf(sender))
      .then((finalBalanceSender) => {
        assert.equal(
          finalBalanceSender.toNumber(),
          lockedBalanceOfSender);
        done();
      });
    });
  });
});
