var async = require('async');
var assert = require('assert');
var BigNumber = require('bignumber.js');
var sha256 = require('js-sha256').sha256;

//Config
const EARLY_BIRD = 250;
const BLKS_PER_WEEK = 41710;

const startBlock = 2377200; //11-01-2016 midnight UTC assuming 14 second blocks
const timePeriod = 6*BLKS_PER_WEEK;
const endBlock = startBlock + timePeriod; //11-29-2016 midnight UTC assuming 14 second blocks


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

contract('Contribution', (accounts) => {
  //globals
  let contract;
  let melon_contract;
  let private_contract;
  let contractAddress;
  var accounts;
  let testCases;
  const ETHER = new BigNumber(Math.pow(10,18));
  const MILLIUNITS = new BigNumber(Math.pow(10,15));
  const founder = accounts[0];
  const signer = accounts[1];
  const FOUNDER_LOCKUP = 2252571;
  const TRANSFER_LOCKUP = 370285;

  before('Check accounts', (done) => {
    assert.equal(accounts.length, 10);
    done();
  });

  it('Deploy smart contract', (done) => {
    Contribution_test.new(founder, signer, startBlock, endBlock).then((result) => {
      contract = result;
      contractAddress = contract.address;
      console.log(contractAddress);
      return contract.melonToken();
    }).then((result) => {
      melon_contract = MelonToken.at(result);
      return melon_contract.creator()
    }).then((result) => {
      console.log('Melon creator', result);
      return contract.privateToken();
    }).then((result) => {
      // TODO replace with PrivateToken
      private_contract = MelonToken.at(result);

      done();
    });
  });

  it('Set up test cases', (done) => {
    testCases = [];
    const numBlocks = 8;
    for (i = 0; i < numBlocks; i++) {
      const blockNumber = Math.round(startBlock + (endBlock-startBlock)*i/(numBlocks-1));
      let expectedPrice;
      if (blockNumber>=startBlock && blockNumber<startBlock+EARLY_BIRD) {
        expectedPrice = 1100;
      } else if (blockNumber>=startBlock + EARLY_BIRD && blockNumber < startBlock + 2*BLKS_PER_WEEK) {
        expectedPrice = 1066;
      } else if (blockNumber>=startBlock + 2*BLKS_PER_WEEK && blockNumber < startBlock + 4*BLKS_PER_WEEK) {
        expectedPrice = 1033;
      } else if (blockNumber>=startBlock + 4*BLKS_PER_WEEK && blockNumber < startBlock + 6*BLKS_PER_WEEK) {
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
    }
    done();
  });

  it('Should sign test cases', (done) => {
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

  it('Test price', (done) => {
    async.eachSeries(testCases,
      function(testCase, callbackEach) {
        contract.setBlockNumber(testCase.blockNumber).then((result) => {
          return contract.testPrice();
        }).then((result) => {
          assert.equal(result.toNumber(), testCase.expectedPrice);
          callbackEach();
        });
      },
      function(err) {
        done();
      }
    );
  });

  it('Test buy', (done) => {
    var amountToBuy = 3;
    var amountBought = 0;
    let amountBoughtMelon = 0;
    let amountBoughtPrivate = 0;
    web3.eth.getBalance(founder, (err, result) => {
      var initialBalance = result;
      async.eachSeries(testCases,
        (testCase, callbackEach) => {
          contract.setBlockNumber(testCase.blockNumber, {from: testCase.account, value: 0}).then((result) => {
            return contract.buy(testCase.v, testCase.r, testCase.s, {from: testCase.account, value: web3.toWei(amountToBuy, "ether")});
          }).then((result) => {
            amountBought += amountToBuy;
            return melon_contract.balanceOf(testCase.account);
          }).then((result) => {
            amountBoughtMelon = result;
            return private_contract.balanceOf(testCase.account);
          }).then((result) => {
            amountBoughtPrivate = result;
            amountBoughtTotal = amountBoughtMelon.toNumber() + amountBoughtPrivate.toNumber();
            console.log(
              '\nstartBlock: ' + startBlock +
              '\nendBlock: ' + endBlock +
              '\nv: ' + testCase.v +
              '\nr: ' + testCase.r +
              '\ns: ' + testCase.s +
              '\n---------------- ' +
              '\ninitalBalance: ' + initialBalance +
              '\namountToBuy: ' + amountToBuy +
              '\nmelon balance: ' + amountBoughtMelon +
              '\nprivate balance: ' + amountBoughtPrivate +
              '\ntotal amount: ' + amountBoughtTotal +
              '\nexpectedPrice: ' + testCase.expectedPrice +
              '\n---------------- ' +
              '\nexpectedResult: ' + MILLIUNITS.times(
                new BigNumber(testCase.expectedPrice)).times(
                new BigNumber(amountToBuy)));
            assert.equal(amountBoughtTotal, MILLIUNITS.times(
              new BigNumber(testCase.expectedPrice)).times(
              new BigNumber(amountToBuy)));
            callbackEach();
          });
        },
        (err) => {
          web3.eth.getBalance(founder, (err, result) => {
            var finalBalance = result;
            assert.equal(finalBalance.minus(initialBalance).toNumber(), ETHER.times(new BigNumber(amountBought)));
            done();
          });
        }
      );
    });
  });

});
