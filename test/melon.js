var async = require('async');
var assert = require('assert');
var BigNumber = require('bignumber.js');
var sha256 = require('js-sha256').sha256;

//Config
var startBlock = 2377200; //11-01-2016 midnight UTC assuming 14 second blocks
var endBlock = 2384400; //11-29-2016 midnight UTC assuming 14 second blocks


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

contract('MelonToken', (accounts) => {
  //globals
  let contract;
  let contractAddress;
  var accounts;
  let testCases;
  const ETHER = new BigNumber(Math.pow(10,18));
  const mMLN = new BigNumber(Math.pow(10,15)); // 1 MLN == 1000 mMLN
  const founder = accounts[0];
  const signer = accounts[1];
  const FOUNDER_LOCKUP = 2252571;
  const TRANSFER_LOCKUP = 370285;

  before('Check accounts', (done) => {
    assert.equal(accounts.length, 10);
    done();
  });

  it('Deploy smart contract', (done) => {
    MelonToken_test.new(founder, signer, startBlock, endBlock).then((result) => {
      contract = result;
      contractAddress = contract.address;
      done();
    });
  });

  it('Set up test cases', (done) => {
    testCases = [];
    const numBlocks = 8;
    for (i=0; i<numBlocks; i++) {
      const blockNumber = Math.round(startBlock + (endBlock-startBlock)*i/(numBlocks-1));
      let expectedPrice;
      if (blockNumber>=startBlock && blockNumber<startBlock+250) {
        expectedPrice = 1100;
      } else if (blockNumber>endBlock || blockNumber<startBlock) {
        expectedPrice = 1000;
      } else {
        //must use Math.floor to simulate Solidity's integer division
        expectedPrice = 1000 + Math.floor(Math.floor(4*(endBlock - blockNumber)/(endBlock - startBlock + 1)) * 100 / 4);
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
        var hash = sha256(new Buffer(testCase.account.slice(2),'hex'));
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
    web3.eth.getBalance(founder, (err, result) => {
      var initialBalance = result;
      async.eachSeries(testCases,
        (testCase, callbackEach) => {
          contract.setBlockNumber(testCase.blockNumber, {from: testCase.account, value: 0}).then((result) => {
            return contract.buy(testCase.v, testCase.r, testCase.s, {from: testCase.account, value: web3.toWei(amountToBuy, "ether")});
          }).then((result) => {
            amountBought += amountToBuy;
            return contract.balanceOf(testCase.account);
          }).then((result) => {
            // console.log(
            //   '\nFounder Balance: ' + initialBalance +
            //   '\nstartBlock: ' + startBlock +
            //   '\nbalanceOf: ' + result +
            //   '\nendBlock: ' + endBlock +
            //   '\nv: ' + testCase.v +
            //   '\nr: ' + testCase.r +
            //   '\ns: ' + testCase.s +
            //   '\nbalance: ' + result +
            //   '\namountToBuy: ' + amountToBuy +
            //   '\nexpectedPrice: ' + testCase.expectedPrice +
            //   '\nexpectedResult: ' + mMLN.times(
            //     new BigNumber(testCase.expectedPrice)).times(
            //     new BigNumber(amountToBuy)));
            assert.equal(result.toNumber(), mMLN.times(
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

  it('Test buying on behalf of a recipient', (done) => {
    var amountToBuy = web3.toWei(1, "ether");
    var initialBalance;
    var price;
    contract.setBlockNumber(endBlock-10, {from: accounts[0], value: 0}).then((result) => {
      return contract.balanceOf(accounts[2]);
    }).then((result) => {
      initialBalance = result;
      var hash = sha256(new Buffer(accounts[1].slice(2),'hex'));
      sign(web3, signer, hash, (err, sig) => {
        contract.buyRecipient(accounts[2], sig.v, sig.r, sig.s, {from: accounts[1], value: amountToBuy}).then((result) => {
          return contract.price();
        }).then((result) => {
          price = result / 1000;
          return contract.balanceOf(accounts[2]);
        }).then((result) => {
          var finalBalance = result;
          // console.log(
          //   '\nfinalBalance: ' + finalBalance +
          //   '\ninitalBalance: ' + initialBalance +
          //   '\namountToBuy: ' + amountToBuy +
          //   '\nprice: ' + price
          // );
          assert.equal(finalBalance.sub(initialBalance).toNumber(), new BigNumber(amountToBuy).times(price));
          done();
        });
      });
    });
  });

  it('Test halting, buying, and failing', (done) => {
    var amountToBuy = web3.toWei(1, "ether");
    var initialBalance;
    contract.balanceOf(accounts[1]).then((result) => {
      initialBalance = result;
      return contract.halt({from: founder, value: 0});
    }).then((result) => {
      var hash = sha256(new Buffer(accounts[1].slice(2),'hex'));
      sign(web3, signer, hash, (err, sig) => {
        if (!err) {
          contract.buy(sig.v, sig.r, sig.s, {from: accounts[1], value: amountToBuy
          }).then((result) => {
            assert.fail();
          }).catch((err) => {
            assert.notEqual(err.name, 'AssertionError');
            contract.balanceOf(accounts[1]).then((result) => {
              var finalBalance = result;
              assert.equal(finalBalance.sub(initialBalance).toNumber(), 0);
              done();
            });
          });
        } else {
          callback(err, undefined);
        }
      });
    });
  });

  it('Test unhalting, buying, and succeeding', (done) => {
    var amountToBuy = web3.toWei(1, "ether");
    var initialBalance;
    contract.balanceOf(accounts[1]).then((result) => {
      initialBalance = result;
      return contract.unhalt({from: founder, value: 0});
    }).then((result) => {
      var hash = sha256(new Buffer(accounts[1].slice(2),'hex'));
      sign(web3, signer, hash, (err, sig) => {
        if (!err) {
          contract.buy(sig.v, sig.r, sig.s, {from: accounts[1], value: amountToBuy
          }).then((result) => {
            return contract.balanceOf(accounts[1]);
          }).then((result) => {
            var finalBalance = result;
            assert.equal(finalBalance.sub(initialBalance).toNumber(), amountToBuy);
            done();
          });
        } else {
          callback(err, undefined);
        }
      });
    });
  });

  it('Test buying after the sale ends', (done) => {
    contract.setBlockNumber(endBlock+1, {from: accounts[0], value: 0}).then((result) => {
      var hash = sha256(new Buffer(accounts[1].slice(2),'hex'));
      sign(web3, signer, hash, (err, sig) => {
        if (!err) {
          contract.buy(sig.v, sig.r, sig.s, {from: accounts[1], value: web3.toWei(1, "ether")
          }).then((result) => {
            assert.fail();
          }).catch((err) => {
            assert.notEqual(err.name, 'AssertionError');
            done();
          });
        } else {
          callback(err, undefined);
        }
      });
    });
  });

  it('Test contract balance is zero', (done) => {
    web3.eth.getBalance(contractAddress, (err, result) => {
      assert.equal(result.equals(new BigNumber(0)), true);
      done();
    });
  });

  it('Test melonport allocation', (done) => {
    var expectedChange;
    var blockNumber;
    var initialFounderBalance;
    var finalFounderBalance;
    contract.totalSupply().then((result) => {
      var totalSupply = result;
      expectedChange = new BigNumber(totalSupply).div(5);
      blockNumber = endBlock + 1;
      return contract.balanceOf(founder);
    }).then((result) => {
      initialFounderBalance = result;
      return contract.setBlockNumber(blockNumber, {from: founder, value: 0});
    }).then((result) => {
      return contract.allocateMelonportTokens({from: founder, value: 0});
    }).then((result) => {
      return contract.balanceOf(founder);
    }).then((result) => {
      finalFounderBalance = result;
      // console.log(
      //   '\nfinalFounderBalance: ' + finalFounderBalance +
      //   '\ninitalFounderBalance: ' + initialFounderBalance +
      //   '\nexpectedChange: ' + expectedChange
      // );
      assert.equal(finalFounderBalance.minus(initialFounderBalance).toNumber(), new BigNumber(expectedChange));
      done();
    });
  });

  it('Test melonport allocation twice', (done) => {
    contract.allocateMelonportTokens({from: founder, value: 0
    }).then((result) => {
      assert.fail();
    }).catch((err) => {
      assert.notEqual(err.name, 'AssertionError');
      done();
    });
  });

  it('Test founder token allocation too early', (done) => {
    var blockNumber = endBlock + FOUNDER_LOCKUP;
    contract.setBlockNumber(blockNumber, {from: founder, value: 0}).then((result) => {
      return contract.allocateFounderTokens({from: founder, value: 0});
    }).then((result) => {
      assert.fail();
    }).catch((err) => {
      assert.notEqual(err.name, 'AssertionError');
      done();
    });
  });

  it('Test founder token allocation on time', (done) => {
    var expectedChange;
    var blockNumber;
    var initialFounderBalance;
    var finalFounderBalance;
    contract.presaleTokenSupply().then((result) => {
      var totalSupply = result;
      expectedChange = new BigNumber(totalSupply).div(5);
      blockNumber = endBlock + FOUNDER_LOCKUP + 1;
      return contract.balanceOf(founder);
    }).then((result) => {
      initialFounderBalance = result;
      return contract.setBlockNumber(blockNumber, {from: founder, value: 0});
    }).then((result) => {
      return contract.allocateFounderTokens({from: founder, value: 0});
    }).then((result) => {
      return contract.balanceOf(founder);
    }).then((result) => {
      var finalFounderBalance = result;
      // console.log(
      //   '\nfinalFounderBalance: ' + finalFounderBalance +
      //   '\ninitalFounderBalance: ' + initialFounderBalance +
      //   '\nexpectedChange: ' + expectedChange
      // );
      assert.equal(finalFounderBalance.minus(initialFounderBalance).toNumber(), new BigNumber(expectedChange));
      done();
    });
  });

  it('Test founder token allocation twice', (done) => {
    contract.allocateFounderTokens({from: founder, value: 0
    }).then((result) => {
      assert.fail();
    }).catch((err) => {
      assert.notEqual(err.name, 'AssertionError');
      done();
    });
  });


  it('Test founder change by hacker', (done) => {
    var newFounder = accounts[1];
    var hacker = accounts[1];
    contract.changeFounder(newFounder, {from: hacker, value: 0
    }).then((result) => {
      assert.fail();
    }).catch((err) => {
      assert.notEqual(err.name, 'AssertionError');
      done();
    });
  });

  it('Test founder change', (done) => {
    var newFounder = accounts[1];
    contract.changeFounder(newFounder, {from: founder, value: 0
    }).then((result) => {
      return contract.founder();
    }).then((result) => {
      assert.equal(result, newFounder);
      done();
    });
  });

  it('Test restricted early transfer', (done) => {
    var account3 = accounts[3];
    var account4 = accounts[4];
    var amount = web3.toWei(1, "ether");
    var blockNumber = endBlock + 100;
    contract.setBlockNumber(blockNumber, {from: founder, value: 0
    }).then((result) => {
      return contract.transfer(account3, amount, {from: account4, value: 0});
    }).then((result) => {
      assert.fail();
    }).catch((err) => {
      assert.notEqual(err.name, 'AssertionError');
      done();
    });
  });

  it('Test transfer after restricted period', (done) => {
    var account3 = accounts[3];
    var account4 = accounts[4];
    var blockNumber = Math.round(endBlock + TRANSFER_LOCKUP + 1);
    var initalBalance3;
    var initalBalance4;
    var transferAmount = web3.toWei(1, "ether");
    contract.setBlockNumber(blockNumber, {from: founder, value: 0
    }).then((result) => {
      return contract.balanceOf(account3);
    }).then((result) => {
      initalBalance3 = result;
      return contract.balanceOf(account4);
    }).then((result) => {
      initalBalance4 = result;
      return contract.transfer(account3, transferAmount, {from: account4, value: 0});
    }).then((result) => {
      return contract.balanceOf(account3);
    }).then((result) => {
      assert.equal(result.toNumber(), initalBalance3.plus(transferAmount).toNumber());
      return contract.balanceOf(account4);
    }).then((result) => {
      assert.equal(result.toNumber(), initalBalance4.minus(transferAmount).toNumber());
      done();
    });
  });

});
