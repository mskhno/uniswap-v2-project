## About 
This project is a simple recreation of Uniswap V2 core contracts. There is no peripheral contracts such as UniswapV2Router, so those contracts have to include necessary checks.

## Libs
1. Openzeppelin-contracts@v5.0.2

## Structure
1. UniswapV2Factory
   Deploys UniswapV2Pair contracts and holds info about their addresses
2. UniswapV2Pair
   Holds balances of 2 tokens and logic to handle reserves, issues its tokens to represent holdings of token reserves(pro-rata)
3. UniswapV2ERC20
   This contract will be inherited by UniswapV2Pair. 
   ERC20 which also handles gasless approvals

## Todo
All of those todo's are maybe's. I can't say for sure i will make those changes.

1. As of now(first commit), there is a lot of comments in code. I will probably clean them later.
2. Users don't have information on which amountIn to provide, or how much tokens they will get if they burn their lp tokens.
   This means that it's probably good to change some private function to be public and enable users to see the inputs or outputs of functions before calling them. 
3. The test suite check 100% of contracts, however it is probably good to do some invariant testing.
