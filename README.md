<img src = "https://github.com/melonproject/branding/blob/master/facebook/Facebook%20cover%20blue%20on%20white.png" width = "100%">

# melon

Token contracts of the Melon contribution.

[![Gitter][gitter-badge]][gitter-url]

## Installation

1. Clone this repository
    ```
    git clone git@github.com:melonproject/melon.git
    cd melon
    ```

2. Install dependencies, such as [Truffle](https://github.com/ConsenSys/truffle) (requires NodeJS 5.0+) and [Testrpc](https://github.com/ethereumjs/testrpc):
    ```
    npm install
    ```

## Getting started

After installation is complete, go to the above `melon` directory, open a terminal and:

1. Launch a testrpc client:
    ```
    node_modules/.bin/testrpc
    ```

2. Open a second terminal and run the test framework:
    ```
    node_modules/.bin/truffle test
    ```

## Deployment

After installation is complete, go to the above `melon` directory, open a terminal and:

1. Launch a ethereum client. For example something similar to this:
    ```
    parity --chain ropsten --author <some address> --unlock <some address> --password <some password file> --geth
    ```

2. Open a second terminal and deploy contracts using truffle
    ```
    truffle migrate
    ```

## Mainnet deployed contracts

See [release v1.0](https://github.com/melonproject/melon/releases/tag/1.0) for contract ABI and addresses of contracts deployed to the Ethereum mainnet.

## Acknowledgements

These token contracts have been influenced by the work of [FirstBlood](https://github.com/Firstbloodio/token).

[gitter-badge]: https://img.shields.io/gitter/room/melonproject/general.js.svg?style=flat-square
[gitter-url]: https://gitter.im/melonproject/general?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge
