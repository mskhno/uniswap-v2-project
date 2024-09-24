// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UniswapV2Pair} from "./UniswapV2Pair.sol";

// Layout of Contract:
// ablversion
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State varies
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
    // keep track of all pairs created
    // populated both for (tokenA, tokenB) and (tokenB, tokenA)
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
        // get sorted non-equal non-zero token addresses
        (address token0, address token1) = _sortAndCheckAddresses(tokenA, tokenB);

        //  -- check pair does not exist
        if (getPair[token0][token1] != address(0)) {
            revert UniswapV2Factory__PairAlreadyExists();
        }

        //  -- create pair at unique deterministic address
        //     bytecode, salt(keccak256(token0, token1))
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        //  -- initialize pair
        UniswapV2Pair(pair).initialize(token0, token1);

        //  -- populate getPair for both token orders
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;

        //  -- emit event
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

        // sort addresses
        if (tokenA < tokenB) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        // checking token0 is sufficient because token0 < token1
        if (token0 == address(0)) {
            revert UniswapV2Factory__TokenAddressCantBeZero();
        }
    }
}
