// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";

contract UniswapV2Factory {
    /////////////////
    // ERRORS
    /////////////////
    error UniswapV2Factory__TokenAddressesAreEqual();
    error UniswapV2Factory__TokenAddressCantBeZero();
    error UniswapV2Factory__PairAlreadyExists();

    /////////////////
    // STATE VARIABLES
    /////////////////
    mapping(address tokenA => mapping(address tokenB => address)) public getPair;

    event PairCreated(address indexed token0, address indexed token1, address pair);

    /////////////////
    // EXTERNAL FUNCTIONS
    /////////////////
    /**
     * @notice Create new pair for two tokens at uniqie deterministic address
     * @param tokenA First token address
     * @param tokenB Second token address
     *
     * @dev Creates UniswapV2Pair contract via create2, address of the pair can be determined calculatePairAddress()
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        (address token0, address token1) = _sortAndCheckAddresses(tokenA, tokenB);

        if (getPair[token0][token1] != address(0)) {
            revert UniswapV2Factory__PairAlreadyExists();
        }

        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        UniswapV2Pair(pair).initialize(token0, token1);

        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        emit PairCreated(token0, token1, pair);
    }

    /////////////////
    // PUBLIC FUNCTIONS
    /////////////////
    /**
     * @notice Get the address of the pair for two tokens in unique and deterministic way
     * @param tokenA First token address
     * @param tokenB Second token address
     *
     * @return pair Address of the pair contract which would be deployed by createPair()
     */
    function calculatePairAddress(address tokenA, address tokenB) public view returns (address) {
        (address token0, address token1) = _sortAndCheckAddresses(tokenA, tokenB);

        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        return address(uint160(uint256(hash)));
    }

    /////////////////
    // PRIVATE FUNCTIONS
    /////////////////
    /**
     * @notice Check token addresses and sort them
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return token0 Always smaller address
     * @return token1 Always larger address
     *
     * @dev Returns sorted non-equal non-zero addresses
     */
    function _sortAndCheckAddresses(address tokenA, address tokenB)
        private
        pure
        returns (address token0, address token1)
    {
        if (tokenA == tokenB) {
            revert UniswapV2Factory__TokenAddressesAreEqual();
        }

        if (tokenA < tokenB) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        if (token0 == address(0)) {
            revert UniswapV2Factory__TokenAddressCantBeZero();
        }
    }
}
