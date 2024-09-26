// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UniswapV2ERC20} from "./UniswapV2ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {console} from "forge-std/console.sol";

contract UniswapV2Pair is UniswapV2ERC20 {
    /////////////////
    // ERRORS
    /////////////////
    error UniswapV2Pair__AmountOfTokenInCantBeZero();
    error UniswapV2Pair__InsufficientLiquidityMinted();
    error UniswapV2Pair__CallerIsNotFactory();
    error UniswapV2Pair__NoLiquidityInPool();
    error UniswapV2Pair__NoLiquidityTokensToBurn();
    error UniswapV2Pair__OnlyOneAmountOutShouldBeNonZero();
    error UniswapV2Pair__TransferFailed();

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
     */
    function mint(address to, uint256 amountToken0In, uint256 amountToken1In)
        external
        returns (uint256 lpTokenAmount)
    {
        (uint256 _reserveAmountToken0, uint256 _reserveAmountToken1) = getReserves();

        if (amountToken0In == 0 || amountToken1In == 0) {
            revert UniswapV2Pair__AmountOfTokenInCantBeZero();
        }

        uint256 totalSupply = totalSupply();
        uint256 optimalAmountToken0In;
        uint256 optimalAmountToken1In;

        if (_reserveAmountToken0 == 0 || _reserveAmountToken1 == 0) {
            optimalAmountToken0In = amountToken0In;
            optimalAmountToken1In = amountToken1In;

            lpTokenAmount = Math.sqrt(optimalAmountToken0In * optimalAmountToken1In);
        } else {
            (optimalAmountToken0In, optimalAmountToken1In) =
                _getOptimalAmountsIn(amountToken0In, amountToken1In, _reserveAmountToken0, _reserveAmountToken1);

            lpTokenAmount = (optimalAmountToken0In * totalSupply) / _reserveAmountToken0;
        }

        _safeTransferFrom(token0, msg.sender, optimalAmountToken0In);
        _safeTransferFrom(token1, msg.sender, optimalAmountToken1In);

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
     */
    function burn(address to) external returns (uint256 amountToken0Out, uint256 amountToken1Out) {
        (uint256 _reserveAmountToken0, uint256 _reserveAmountToken1) = getReserves();

        uint256 totalSupply = totalSupply();
        uint256 callerBalance = balanceOf(msg.sender);

        if (totalSupply == 0) {
            revert UniswapV2Pair__NoLiquidityInPool();
        }

        if (callerBalance == 0) {
            revert UniswapV2Pair__NoLiquidityTokensToBurn();
        }

        (amountToken0Out, amountToken1Out) =
            _getAmountTokensOut(callerBalance, totalSupply, _reserveAmountToken0, _reserveAmountToken1);

        _burn(msg.sender, callerBalance);

        _safeTransfer(token0, to, amountToken0Out);
        _safeTransfer(token1, to, amountToken1Out);

        _updateReserves(_reserveAmountToken0 - amountToken0Out, _reserveAmountToken1 - amountToken1Out);

        emit Burn(msg.sender, amountToken0Out, amountToken1Out, to);
    }

    /**
     * @notice Swaps one token for another
     * @param to Address to send tokens to
     * @param amountToken0Out Amount of token0 caller wants to get after swap
     * @param amountToken1Out Amount of token1 caller wants to get after swap
     *
     * @dev Assumes that caller has already approved this contract to spend their token0 and token1
     * How do they know how much to approve? They have getReserves to get spot price
     * @dev Only one amountOut should be non-zero
     */
    function swap(address to, uint256 amountToken0Out, uint256 amountToken1Out)
        external
        returns (uint256 amountToken0In, uint256 amountToken1In)
    {
        if ((amountToken0Out == 0 && amountToken1Out == 0) || (amountToken0Out > 0 && amountToken1Out > 0)) {
            revert UniswapV2Pair__OnlyOneAmountOutShouldBeNonZero();
        }

        (uint256 _reserveAmountToken0, uint256 _reserveAmountToken1) = getReserves();

        if (_reserveAmountToken0 == 0 || _reserveAmountToken1 == 0) {
            revert UniswapV2Pair__NoLiquidityInPool();
        }

        amountToken0In = (_reserveAmountToken0 * amountToken1Out / (_reserveAmountToken1 - amountToken1Out));
        amountToken1In = (_reserveAmountToken1 * amountToken0Out / (_reserveAmountToken0 - amountToken0Out));

        if (amountToken1Out > 0) {
            _safeTransferFrom(token0, msg.sender, amountToken0In);
            _safeTransfer(token1, to, amountToken1Out);
        }
        if (amountToken0Out > 0) {
            _safeTransferFrom(token1, msg.sender, amountToken1In);
            _safeTransfer(token0, to, amountToken0Out);
        }

        _updateReserves(
            _reserveAmountToken0 + amountToken0In - amountToken0Out,
            _reserveAmountToken1 + amountToken1In - amountToken1Out
        );

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
     * @notice Safe transfer tokens from this contract
     *
     * @param token Address of token to transfer
     * @param to Address to transfer to
     * @param amount Amount to transfer
     */
    function _safeTransfer(address token, address to, uint256 amount) private {
        bool success = IERC20(token).transfer(to, amount);
        if (!success) {
            revert UniswapV2Pair__TransferFailed();
        }
    }

    /**
     * @notice Safe transfer tokens from caller to this contract
     *
     * @param token Address of token to transfer
     * @param from Address to transfer from
     * @param amount Amount to transfer
     */
    function _safeTransferFrom(address token, address from, uint256 amount) private {
        bool success = IERC20(token).transferFrom(from, address(this), amount);
        if (!success) {
            revert UniswapV2Pair__TransferFailed();
        }
    }
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
    function _getOptimalAmountsIn(
        uint256 amount0In,
        uint256 amount1In,
        uint256 _reserveAmountToken0,
        uint256 _reserveAmountToken1
    ) private pure returns (uint256 optimalAmountToken0In, uint256 optimalAmountToken1In) {
        optimalAmountToken0In = _calculateTokenIn(amount1In, _reserveAmountToken0, _reserveAmountToken1);

        if (optimalAmountToken0In <= amount0In) {
            return (optimalAmountToken0In, amount1In);
        }

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
    function _calculateTokenIn(uint256 amountTokenXIn, uint256 _reserveA, uint256 _reserveB)
        private
        pure
        returns (uint256 optimalAmountTokenYIn)
    {
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
    function _getAmountTokensOut(
        uint256 amountLpTokens,
        uint256 totalSupply,
        uint256 _reserveAmountToken0,
        uint256 _reserveAmountToken1
    ) private pure returns (uint256 amountToken0Out, uint256 amountToken1Out) {
        amountToken0Out = (amountLpTokens * _reserveAmountToken0) / totalSupply;
        amountToken1Out = (amountLpTokens * _reserveAmountToken1) / totalSupply;
    }
}
