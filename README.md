# melon

Token contracts of the melon protocol contribution.

[![Slack Status](http://chat.melonport.com/badge.svg)](http://chat.melonport.com) [![Gitter](https://badges.gitter.im/melonproject/general.svg)](https://gitter.im/melonproject/general?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

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

## Acknowledgements

These token contracts have been influenced by the work of [FirstBlood](https://github.com/Firstbloodio/token).
