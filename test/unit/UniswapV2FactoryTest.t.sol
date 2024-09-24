// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {UniswapV2Factory} from "src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/UniswapV2Pair.sol";

contract UniswapV2FactoryTest is Test {
    UniswapV2Factory factory;

    event PairCreated(address indexed token0, address indexed token1, address pair);

    UniswapV2Pair pair;

    ERC20Mock token0;
    ERC20Mock token1;

    address public user = makeAddr("user");
    uint256 public constant INITIAL_USER_BALANCE = 1000e18;

    function setUp() public {
        token0 = new ERC20Mock("Wrapped ETH", "WETH", user, INITIAL_USER_BALANCE);
        token1 = new ERC20Mock("Dai", "DAI", user, INITIAL_USER_BALANCE);

        factory = new UniswapV2Factory();
    }

    /////////////////
    // getPair
    /////////////////
    function test_getPair_ReturnsPairAddress() public {
        address pairAddress = factory.createPair(address(token0), address(token1));

        address actualPairAddress = factory.getPair(address(token0), address(token1));
        assertEq(actualPairAddress, pairAddress);

        address actualInvertedPairAddress = factory.getPair(address(token1), address(token0));
        assertEq(actualInvertedPairAddress, pairAddress);
    }

    //////////////////
    // calculatePairAddress
    //////////////////

    function test_calculatePairAddress_GivesRightAddress() public {
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt;
        if (token0 < token1) {
            salt = keccak256(abi.encodePacked(token0, token1));
        } else {
            salt = keccak256(abi.encodePacked(token1, token0));
        }

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(bytecode)));
        address expectedPairAddress = address(uint160(uint256(hash)));

        // test both orders of token0 and token1 as input
        address actualPairAddress = factory.calculatePairAddress(address(token0), address(token1));
        address actualInvertedPairAddress = factory.calculatePairAddress(address(token1), address(token0));
        assertEq(actualPairAddress, expectedPairAddress);
        assertEq(actualInvertedPairAddress, expectedPairAddress);
    }

    function test_calculatePairAddress_RevertsWhenAddressesAreEqual() public {
        address token = address(0x111);
        address sameToken = address(0x111);

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__TokenAddressesAreEqual.selector);
        factory.calculatePairAddress(token, sameToken);

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__TokenAddressesAreEqual.selector);
        factory.calculatePairAddress(sameToken, token);
    }

    function test_calculatePairAddress_RevertsWhenOneOrTwoAddressIsZero() public {
        address tokenZero = address(0x000);
        address tokenNonZero = address(0x111);

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__TokenAddressCantBeZero.selector);
        factory.calculatePairAddress(tokenZero, tokenNonZero);

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__TokenAddressCantBeZero.selector);
        factory.calculatePairAddress(tokenNonZero, tokenZero);

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__TokenAddressesAreEqual.selector);
        factory.calculatePairAddress(tokenZero, tokenZero);
    }

    /////////////////
    // createPair
    /////////////////

    function test_createPair_CreatesPairAtAddress() public {
        bytes memory bytecode = type(UniswapV2Pair).creationCode;
        bytes32 salt;
        if (token0 < token1) {
            salt = keccak256(abi.encodePacked(token0, token1));
        } else {
            salt = keccak256(abi.encodePacked(token1, token0));
        }

        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(bytecode)));
        address expectedPairAddress = address(uint160(uint256(hash)));

        address actualAddress = factory.createPair(address(token0), address(token1));

        assertEq(actualAddress, expectedPairAddress);
    }

    function test_createPair_RevertsWhenPairAlreadyExists() public {
        factory.createPair(address(token0), address(token1));

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__PairAlreadyExists.selector);
        factory.createPair(address(token0), address(token1));

        vm.expectRevert(UniswapV2Factory.UniswapV2Factory__PairAlreadyExists.selector);
        factory.createPair(address(token1), address(token0));
    }

    function test_createPair_InitializesPair() public {
        address smallerToken;
        address largerToken;
        if (token0 < token1) {
            (smallerToken, largerToken) = (address(token0), address(token1));
        } else {
            (smallerToken, largerToken) = (address(token1), address(token0));
        }
        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = UniswapV2Pair(pairAddress);

        assertEq(pair.token0(), smallerToken);
        assertEq(pair.token1(), largerToken);
    }

    function test_createPair_PopulatesGetPair() public {
        address initialPairAddress = factory.getPair(address(token0), address(token1));
        address initiaInvertedPairAddress = factory.getPair(address(token1), address(token0));
        assertEq(initialPairAddress, address(0));
        assertEq(initiaInvertedPairAddress, address(0));

        address pairAddress = factory.createPair(address(token0), address(token1));

        address actualPairAddress = factory.getPair(address(token0), address(token1));
        address actualInvertedPairAddress = factory.getPair(address(token1), address(token0));
        assertEq(actualPairAddress, pairAddress);
        assertEq(actualInvertedPairAddress, pairAddress);
    }

    function test_createPair_EmitsPairCreatedEvent() public {
        address smallerToken;
        address largerToken;
        if (token0 < token1) {
            (smallerToken, largerToken) = (address(token0), address(token1));
        } else {
            (smallerToken, largerToken) = (address(token1), address(token0));
        }

        address pairAddress = factory.calculatePairAddress(address(token0), address(token1));

        vm.expectEmit(true, true, false, true);
        emit PairCreated(smallerToken, largerToken, pairAddress);
        factory.createPair(address(token0), address(token1));
    }
}
