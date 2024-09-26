## About 
This project is a simple recreation of Uniswap V2 core contracts. There is no peripheral contracts such as UniswapV2Router, so those contracts are modified.

## Libs
1. Openzeppelin-contracts@v5.0.2

## Structure
1. UniswapV2Factory
   Deploys and initializes UniswapV2Pair contracts and holds info about their addresses, also used for getting an address for potential pairs.
2. UniswapV2Pair
   Holds balances of 2 tokens and logic to handle reserves operations, such as: 
   1. Liquidity provision and minting lp tokenso represent holdings(pro-rata)
   2. Burning of lp tokens to redeem locked liquidity
   3. Swapping tokens of the pair
3. UniswapV2ERC20
   This contract will be inherited by UniswapV2Pair. 
   ERC20 which also handles gasless approvals

## Todo
All of those todo's are maybe. I can't say for sure i will make those changes.

1. The test suite checks almost 100%, except for two branches in UniswapV2Pair(transfer functions). Maybe I will fix this later. Also a good idea to practice invariant testing.
2. In the constructor of UniswapV2ERC20 block.chainId is used to create a domain separator. There is a better practice to use.