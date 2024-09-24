// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

contract UniswapV2Pair is UniswapV2ERC20 {
    /////////////////
    // ERRORS
    /////////////////
    error UniswapV2Pair__AmountOfTokenInCantBeZero();
    error UniswapV2Pair__InsufficientLiquidityMinted();
    error UniswapV2Pair__CallerIsNotFactory();
    error UniswapV2Pair__NoLiquidityInPool();
    error UniswapV2Pair__NoLiquidityTokensToBurn();
    error UniswapV2Pair__AtleastOneAmountShouldBeNonZero();

    /////////////////
    // STATE VARIABLES
    /////////////////
    address public immutable i_factory;
    address public token0;
    address public token1;

    string private constant TOKEN_NAME = "UniswapV2ERC20";
    string private constant TOKEN_SYMBOL = "UNI-V2";

    uint256 private reserveAmountToken0;
    uint256 private reserveAmountToken1;

    /////////////////
    // EVENTS
    /////////////////
    // don't really know what should be indexed and how this works
    event Mint(address indexed sender, uint256 amountToken0In, uint256 amountToken1In);
    event Sync(uint256 indexed reserveToken0, uint256 indexed reserveToken1);
    event Burn(address indexed sender, uint256 amountToken0Out, uint256 amountToken1Out, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amountToken0In,
        uint256 amountToken1In,
        uint256 amountToken0Out,
        uint256 amountToken1Out,
        address indexed to
    );

    /////////////////
    // FUNCTIONS
    /////////////////
    constructor() UniswapV2ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        i_factory = msg.sender;
    }

    /////////////////
    // EXTERNAL FUNCTIONS
    /////////////////
    /**
     * @notice Function for providing liquidity to the pool
     *
     * @param to Address to mint LP tokens to
     * @param amountToken0In Amount of token0 to take from user
     * @param amountToken1In Amount of token1 to take from user
     *
     * @return lpTokenAmount Amount of LP tokens minted
     *
     * @dev Assumes that caller has already approved this contract to spend their token0 and token1 in at least
     * amount0In and amount1In respectively
     * @dev There's likelyhood of unspent allowance of token0 or token1, depending on the amounts passed, since
     * the function doesn't assume caller knows reserve proportions and therefore itself figures out the optimal
     * amounts of tokens to take from caller
     *
     * Maybe TODO:
     * -
     */
    function mint(address to, uint256 amountToken0In, uint256 amountToken1In)
        external
        returns (uint256 lpTokenAmount)
    {
        //@Vlad Ага. Без этого каждый раз код бы использовал SLOAD (warm access стоит 100 gas), чтобы получить доступ к резерву
        // А так он хранится всегда в стеке, где доступ очень дешёвый
        // Но вообще внутреннее устройство Solidity: stack, opcodes будет попозже. И изучаться будет по статьям
        (uint256 _reserveAmountToken0, uint256 _reserveAmountToken1) = getReserves(); // saves gas???

        // check amountsIn are non-zero
        if (amountToken0In == 0 || amountToken1In == 0) {
            revert UniswapV2Pair__AmountOfTokenInCantBeZero();
        }

        // calculate optimal amounts based on totalSupply and calculate amount to mint
        // if there's no liquidity, take the amounts as is
        // if there's liquidity, take the amounts in such a way that they don't change the reserve proportions
        uint256 totalSupply = totalSupply();
        uint256 optimalAmountToken0In;
        uint256 optimalAmountToken1In;
        // if total supply is zero == if reserves are zero??
        // total supply only changes when reserves change
        // so maybe checking if reserves are zero or if totalSupply is zero is the same
        if (_reserveAmountToken0 == 0 || _reserveAmountToken1 == 0) {
            optimalAmountToken0In = amountToken0In;
            optimalAmountToken1In = amountToken1In;
            // calculate amount to mint for initial liquidity
            // maybe calculate for both tokens and mint the minimal amount as in min(lpTokensByAmount0, lpTokensByAmount1)
            lpTokenAmount = Math.sqrt(optimalAmountToken0In * optimalAmountToken1In); // no minimal liquidity
        } else {
            // return amounts that don't change proportion
            // may leave some unspent allowance of some token in case user approved for amountsIn
            (optimalAmountToken0In, optimalAmountToken1In) =
                _getOptimalAmountsIn(amountToken0In, amountToken1In, _reserveAmountToken0, _reserveAmountToken1);
            // calculate amount to mint
            // maybe calculate for both tokens and mint the minimal amount as in min(lpTokensByAmount0, lpTokensByAmount1)
            //@Vlad работает норм
            lpTokenAmount = (optimalAmountToken0In * totalSupply) / _reserveAmountToken0;
        }

        //@Vlad можно без неё
        // do we really need this check?
        // if (lpTokenAmount == 0) {
        //     revert UniswapV2Pair__InsufficientLiquidityMinted();
        // }

        // transferFrom optimal amounts of token0 and token1 from caller
        IERC20(token0).transferFrom(msg.sender, address(this), optimalAmountToken0In);
        IERC20(token1).transferFrom(msg.sender, address(this), optimalAmountToken1In);
        //@Vlad Обязательно нужно. Есть токены, например USDT - он не делает returns bool - из-за этого будет ревёрт (интерфейс ожидает этот return)
        //@Vlad А также некоторые токены делают returns false вместо revert: https://github.com/d-xo/weird-erc20/#no-revert-on-failure
        // should i do bool success and check it?

        // mint lp tokens
        _mint(to, lpTokenAmount);
        _updateReserves(_reserveAmountToken0 + optimalAmountToken0In, _reserveAmountToken1 + optimalAmountToken1In);
        emit Mint(to, optimalAmountToken0In, optimalAmountToken1In);
    }

    /**
     * @notice Burns all LP tokens of caller and redeems corresponding amounts of liquidity
     *
     * @param to Address to send tokens to
     *
     * @return amountToken0Out Amount of token0 sent to "to"
     * @return amountToken1Out Amount of token1 sent to "to"
     *
     * Maybe TODO:
     * - take amountsOut from caller and figure out the optimal amounts to send and lp to burn
     * - take amount of LP to burn and figure aout the optimal amounts to send
     *
     * @dev needs approval before calling??
     */
    //@Vlad норм
    function burn(address to) external returns (uint256 amountToken0Out, uint256 amountToken1Out) {
        (uint256 _reserveAmountToken0, uint256 _reserveAmountToken1) = getReserves(); // saves gas???

        uint256 totalSupply = totalSupply();
        uint256 callerBalance = balanceOf(msg.sender);

        //// Maybe put those checks in _getAmountTokensOut and make it public
        // check liquidity
        if (totalSupply == 0) {
            revert UniswapV2Pair__NoLiquidityInPool();
        }

        // check balance
        if (callerBalance == 0) {
            revert UniswapV2Pair__NoLiquidityTokensToBurn();
        }

        // calculate amounts to send
        // amounts cant be zero??? no need to check
        (amountToken0Out, amountToken1Out) =
            _getAmountTokensOut(callerBalance, totalSupply, _reserveAmountToken0, _reserveAmountToken1);

        // burn lp tokens
        _burn(msg.sender, callerBalance);
        // send tokens
        IERC20(token0).transfer(to, amountToken0Out);
        IERC20(token1).transfer(to, amountToken1Out);

        // update reserves and emit event
        _updateReserves(_reserveAmountToken0 - amountToken0Out, _reserveAmountToken1 - amountToken1Out);

        emit Burn(msg.sender, amountToken0Out, amountToken1Out, to);
    }

    /**
     * @notice Swaps tokens for tokens
     * @param to Address to send tokens to
     * @param amountToken0Out Amount of token0 caller wants to get after swap
     * @param amountToken1Out Amount of token1 caller wants to get after swap
     *
     * @dev Assumes that caller has already approved this contract to spend their token0 and token1
     * How do they know how much to approve? They have getReserves to get spot price
     * @dev Atleast one amount should be non-zero
     *
     */
    
    //@Vlad функция работает, но если честно это не то, чего я ожидал увидеть
    // Думал ты будешь просто сделаешь swap одного токена на другой, другими словами когда одна из "out" переменных равна 0
    // Uniswap это делают, чтобы позволить flash swap. В данной реализации это бессмысленно, и может быть
    // При подсчёте amountTokenXIn будут неточности (нужно проверять)

    // Подумал снова, всё решается если добавить `require(только одна из out переменных равна 0)`. Хорошая работа!
    function swap(address to, uint256 amountToken0Out, uint256 amountToken1Out)
        external
        returns (uint256 amountToken0In, uint256 amountToken1In)
    {
        // just check if atleast one is non-zero
        if (amountToken0Out == 0 && amountToken1Out == 0) {
            revert UniswapV2Pair__AtleastOneAmountShouldBeNonZero();
        }

        // get reserves
        (uint256 _reserveAmountToken0, uint256 _reserveAmountToken1) = getReserves();

        if (_reserveAmountToken0 == 0 || _reserveAmountToken1 == 0) {
            revert UniswapV2Pair__NoLiquidityInPool();
        }

        // calculate both amountIn
        // token0 for token1
        amountToken0In = (_reserveAmountToken0 * amountToken1Out / (_reserveAmountToken1 - amountToken1Out));
        //token 1 for token0
        amountToken1In = (_reserveAmountToken1 * amountToken0Out / (_reserveAmountToken0 - amountToken0Out));

        // send tokens
        // swap token0 for token 1
        if (amountToken1Out > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amountToken0In);
            IERC20(token1).transfer(to, amountToken1Out);
        }
        // spot price change after first swap = bad second swap? prolly not

        // swap token 1 for token 0
        if (amountToken0Out > 0) {
            IERC20(token1).transferFrom(msg.sender, address(this), amountToken1In);
            IERC20(token0).transfer(to, amountToken0Out);
        }
        // update reserves
        _updateReserves(
            _reserveAmountToken0 + amountToken0In - amountToken0Out,
            _reserveAmountToken1 + amountToken1In - amountToken1Out
        );

        // emit event
        emit Swap(msg.sender, amountToken0In, amountToken1In, amountToken0Out, amountToken1Out, to);
    }

    /**
     * @notice Initializes token addresses for the pair, called by the factory during pair creation only once
     *
     * @param _token0 Address for token0
     * @param _token1 Address for token1
     *
     * @dev Addresses are checked to be non-zero at the factory
     */
    function initialize(address _token0, address _token1) external {
        if (msg.sender != i_factory) {
            revert UniswapV2Pair__CallerIsNotFactory();
        }
        token0 = _token0;
        token1 = _token1;
    }

    /////////////////
    // PUBLIC FUNCTIONS
    /////////////////
    /**
     * @notice Function for getting reserves of the pair
     */
    function getReserves() public view returns (uint256, uint256) {
        return (reserveAmountToken0, reserveAmountToken1);
    }

    /////////////////
    // PRIVATE FUNCTIONS
    /////////////////
    /**
     * @notice Function for updating reserves of the pair
     *
     * @param _balanceToken0 Amount of token0 to set reserveAmountToken0 to
     * @param _balanceToken1 Amount of token1 to set reserveAmountToken1 to
     */
    function _updateReserves(uint256 _balanceToken0, uint256 _balanceToken1) private {
        reserveAmountToken0 = _balanceToken0;
        reserveAmountToken1 = _balanceToken1;
        emit Sync(reserveAmountToken0, reserveAmountToken1);
    }

    /**
     * @notice Calculates safe amounts to take from caller
     * These amounts are calculated in such a way that they don't change the reserve proportions
     *
     * @param amount0In Amount of token0 caller wants to provide
     * @param amount1In Amount of token1 caller wants to provide
     * @param _reserveAmountToken0 Last updated amount of token0 in reserves
     * @param _reserveAmountToken1 Last updated amount of token1 in reserves
     *
     * @return optimalAmountToken0In Amount of token0 to take which doesn't change reserve proportions
     * @return optimalAmountToken1In Amount of token1 to take which doesn't change reserve proportions
     */
    //@Vlad Функция работает правильно, хотя это неочевидно. Можно попытаться упростить её, но не уверен что получится
    function _getOptimalAmountsIn(
        uint256 amount0In,
        uint256 amount1In,
        uint256 _reserveAmountToken0,
        uint256 _reserveAmountToken1
    ) private pure returns (uint256 optimalAmountToken0In, uint256 optimalAmountToken1In) {
        // calculate optimal amount of token0 in

        optimalAmountToken0In = _calculateTokenIn(amount1In, _reserveAmountToken0, _reserveAmountToken1);

        if (optimalAmountToken0In <= amount0In) {
            return (optimalAmountToken0In, amount1In);
        }

        // calculate optimal amount of token1 in
        // the case for calculating optimalAmount1In may never happen?
        // test this like this: approve for amountsIn and then check unspent allowance
        optimalAmountToken1In = _calculateTokenIn(amount0In, _reserveAmountToken1, _reserveAmountToken0);
        if (optimalAmountToken1In <= amount1In) {
            return (amount0In, optimalAmountToken1In);
        }
    }

    /**
     * @notice Calculates how much tokenY is needed to take with full amount of tokenX to not change reserve proportions
     * Basically answers the question: "How much tokenY should we take if we want to provide this amount of tokenX?"
     *
     * @param amountTokenXIn Whole amount of tokenX to take
     * @param _reserveA  Amount of tokenA in reserves
     * @param _reserveB Amount of tokenB in reserves
     */
    //@Vlad норм
    function _calculateTokenIn(uint256 amountTokenXIn, uint256 _reserveA, uint256 _reserveB)
        private
        pure
        returns (uint256 optimalAmountTokenYIn)
    {
        // // check amount != 0
        // if (amountTokenXIn == 0) {
        //     revert UniswapV2Pair__AmountOfTokenInCantBeZero();
        // }
        // // check if there is liquidity
        // if (_reserveA == 0 || _reserveB == 0) {
        //     // maybe &&, not sure, prolly doesnt matter
        //     revert UniswapV2Pair__NoLiquidity();
        // }

        // calculate tokenIn
        optimalAmountTokenYIn = (_reserveA * amountTokenXIn) / _reserveB;
    }

    /**
     * @notice Calculates amounts of tokens to send to caller when burning LP tokens
     *
     * @param amountLpTokens Amount of LP tokens to burn
     * @param totalSupply Total supply of LP tokens
     * @param _reserveAmountToken0 Amount of token0 in reserves
     * @param _reserveAmountToken1 Amount of token1 in reserves
     */
    //@Vlad норм
    function _getAmountTokensOut(
        uint256 amountLpTokens,
        uint256 totalSupply,
        uint256 _reserveAmountToken0,
        uint256 _reserveAmountToken1
    ) private pure returns (uint256 amountToken0Out, uint256 amountToken1Out) {
        // calculate amounts to send
        amountToken0Out = (amountLpTokens * _reserveAmountToken0) / totalSupply;
        amountToken1Out = (amountLpTokens * _reserveAmountToken1) / totalSupply;
    }
}
