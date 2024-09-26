// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {ERC20Mock} from "test/mocks/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {UniswapV2Factory} from "src/UniswapV2Factory.sol";
import {UniswapV2Pair} from "src/UniswapV2Pair.sol";

contract UniswapV2PairTest is Test {
    UniswapV2Factory factory;

    event PairCreated(address indexed token0, address indexed token1, address pair);

    UniswapV2Pair pair;

    event Transfer(address indexed from, address indexed to, uint256 value);
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

    ERC20Mock token0;
    ERC20Mock token1;

    address public user = makeAddr("user");
    uint256 public constant INITIAL_USER_BALANCE = 1000e18;

    modifier initialLiquidity() {
        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        pair.mint(user, 300e18, 600e18);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        address someToken = address(new ERC20Mock("Wrapped ETH", "WETH", user, INITIAL_USER_BALANCE));
        address someOtherToken = address(new ERC20Mock("Dai", "DAI", user, INITIAL_USER_BALANCE));

        factory = new UniswapV2Factory();
        pair = UniswapV2Pair(factory.createPair(someToken, someOtherToken));
        token0 = ERC20Mock(pair.token0());
        token1 = ERC20Mock(pair.token1());
    }

    /////////////////
    // constructor
    /////////////////

    function test_constructor_SetsUpNameAndSymbolRight() public {
        string memory expectedName = "UniswapV2ERC20";
        string memory expectedSymbol = "UNI-V2";

        string memory actualName = pair.name();
        string memory actualSymbol = pair.symbol();

        assertEq(keccak256(abi.encodePacked(actualName)), keccak256(abi.encodePacked(expectedName)));
        assertEq(keccak256(abi.encodePacked(actualSymbol)), keccak256(abi.encodePacked(expectedSymbol)));
    }

    /////////////////
    // initialize
    /////////////////

    function test_initilize_FactoryCanInitializePair() public {
        address smallerToken = address(0x123);
        address largerToken = address(0x456);

        UniswapV2Pair newPair = UniswapV2Pair(factory.createPair(smallerToken, largerToken));

        assertEq(newPair.token0(), smallerToken);
        assertEq(newPair.token1(), largerToken);

        largerToken = address(0x789);

        vm.prank(address(factory));
        newPair.initialize(smallerToken, largerToken);

        assertEq(newPair.token0(), smallerToken);
        assertEq(newPair.token1(), largerToken);
    }

    function test_initialize_SetsUpToken0AndToken1Right() public {
        address smallerToken;
        address largerToken;
        if (token0 < token1) {
            (smallerToken, largerToken) = (address(token0), address(token1));
        } else {
            (smallerToken, largerToken) = (address(token1), address(token0));
        }

        address actualToken0 = pair.token0();
        address actualToken1 = pair.token1();

        assertEq(actualToken0, address(smallerToken));
        assertEq(actualToken1, address(largerToken));
    }

    function test_initialize_RevertsWhenCallerIsNotFactory() public {
        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__CallerIsNotFactory.selector);
        pair.initialize(address(token0), address(token1));
    }

    /////////////////
    // getReserves
    /////////////////

    function test_getReserves_ReturnsReserves() public {
        uint256 expectedReserve0 = 0;
        uint256 expectedReserve1 = 0;

        (uint256 actualReserve0, uint256 actualReserve1) = pair.getReserves();

        assertEq(actualReserve0, expectedReserve0);
        assertEq(actualReserve1, expectedReserve1);
    }

    // something else?

    /////////////////
    // mint
    /////////////////

    function test_mint_RevertsWhenUserDidntApproveTokens() public {
        uint256 token0AllowanceForPair = token0.allowance(user, address(pair));

        bytes memory expectedReason = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientAllowance.selector,
            address(pair),
            token0AllowanceForPair,
            (INITIAL_USER_BALANCE - token0AllowanceForPair)
        );

        vm.expectRevert(expectedReason);
        vm.prank(user);
        pair.mint(user, INITIAL_USER_BALANCE, INITIAL_USER_BALANCE);
    }

    function test_mint_RevertsWhenAmountInIsZero() public {
        uint256 amountToken0In = 0;
        uint256 amountToken1In = 0;

        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__AmountOfTokenInCantBeZero.selector);
        vm.prank(user);
        pair.mint(user, amountToken0In, 1 ether);

        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__AmountOfTokenInCantBeZero.selector);
        vm.prank(user);
        pair.mint(user, 1 ether, amountToken1In);

        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__AmountOfTokenInCantBeZero.selector);
        vm.prank(user);
        pair.mint(user, amountToken0In, amountToken1In);
    }

    function test_mint_TakesTokensAndMintsLpWhenReservesAreZero() public {
        (uint256 reserveAmountToken0, uint256 reserveAmountToken1) = pair.getReserves();
        assertEq(reserveAmountToken0, 0);
        assertEq(reserveAmountToken1, 0);

        uint256 amountToken0In = INITIAL_USER_BALANCE;
        uint256 amountToken1In = INITIAL_USER_BALANCE;

        uint256 expectedLpAmount = INITIAL_USER_BALANCE;

        vm.startPrank(user);
        token0.approve(address(pair), amountToken0In);
        token1.approve(address(pair), amountToken1In);
        uint256 lpMintedToUser = pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        (reserveAmountToken0, reserveAmountToken1) = pair.getReserves();

        assertEq(reserveAmountToken0, amountToken0In);
        assertEq(reserveAmountToken1, amountToken1In);

        uint256 actualTotalSupply = pair.totalSupply();
        uint256 actualUserLpBalance = pair.balanceOf(user);

        assertEq(actualTotalSupply, expectedLpAmount);
        assertEq(actualUserLpBalance, expectedLpAmount);
        assertEq(lpMintedToUser, expectedLpAmount);
    }

    function test_mint_TakesTokensAndMintsLpWhenReservesAreNonZero() public {
        uint256 amountToken0In = INITIAL_USER_BALANCE / 2; // _getOptimalAmountIn doesn't change this in second call
        uint256 amountToken1In = INITIAL_USER_BALANCE / 2; // _getOptimalAmountIn doesn't change this in second call

        uint256 expectedLpAmount = INITIAL_USER_BALANCE; // 1000e18 after two rounds of 500e18 mints

        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        uint256 lpMintedToUser = pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        (uint256 reserveAmountToken0, uint256 reserveAmountToken1) = pair.getReserves();
        assertEq(reserveAmountToken0, amountToken0In); // assert non-zero
        assertEq(reserveAmountToken1, amountToken1In); // assert non-zero

        vm.prank(user);
        lpMintedToUser += pair.mint(user, amountToken0In, amountToken1In);

        (reserveAmountToken0, reserveAmountToken1) = pair.getReserves();

        assertEq(reserveAmountToken0, amountToken0In * 2);
        assertEq(reserveAmountToken1, amountToken1In * 2);

        uint256 actualTotalSupply = pair.totalSupply();
        uint256 actualUserLpBalance = pair.balanceOf(user);

        assertEq(actualTotalSupply, expectedLpAmount);
        assertEq(actualUserLpBalance, expectedLpAmount);
    }

    // test calculating optimalAmountToken0In
    function test_mint_BadAmountsInDoNotChangeReserveProportions() public {
        uint256 amountToken0In = 100e18;
        uint256 amountToken1In = 200e18;

        console.log("first mint");
        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        (uint256 initialReserveAmountToken0, uint256 initialReserveAmountToken1) = pair.getReserves();

        // takes 200e18 token0 and 100e18 token1 ?? optimalAmounts bad calculation
        console.log("");

        uint256 diffAmountToken0In = 100e18;
        uint256 diffAmountToken1In = 400e18;

        console.log("second mint");
        vm.prank(user);
        pair.mint(user, diffAmountToken0In, diffAmountToken1In);

        (uint256 actualReserveAmountToken0, uint256 actualReserveAmountToken1) = pair.getReserves();

        console.log("");

        assertEq(actualReserveAmountToken0, initialReserveAmountToken0 + diffAmountToken0In);
        assertEq(actualReserveAmountToken1, initialReserveAmountToken1 + 200e18);
    }

    // test claculating optimalAmountToken1In
    function test_mint_BadAmountsInDoNotChangeReserveProportions2() public {
        uint256 amountToken0In = 100e18;
        uint256 amountToken1In = 200e18;

        console.log("first mint");
        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        (uint256 initialReserveAmountToken0, uint256 initialReserveAmountToken1) = pair.getReserves();

        // takes 200e18 token0 and 100e18 token1 ?? optimalAmounts bad calculation
        console.log("");

        uint256 diffAmountToken0In = 100e18;
        uint256 diffAmountToken1In = 50e18;

        console.log("second mint");
        vm.prank(user);
        pair.mint(user, diffAmountToken0In, diffAmountToken1In);

        (uint256 actualReserveAmountToken0, uint256 actualReserveAmountToken1) = pair.getReserves();

        console.log("");

        assertEq(actualReserveAmountToken0, initialReserveAmountToken0 + 25e18);
        assertEq(actualReserveAmountToken1, initialReserveAmountToken1 + diffAmountToken1In);
    }

    function test_mint_TakesTokensFromUser() public {
        uint256 amountToken0In = INITIAL_USER_BALANCE / 2;
        uint256 amountToken1In = INITIAL_USER_BALANCE / 2;

        uint256 initialUserToken0Balance = token0.balanceOf(user);
        uint256 initialUserToken1Balance = token1.balanceOf(user);

        uint256 initialPairToken0Balance = token0.balanceOf(address(pair));
        uint256 initialPairToken1Balance = token1.balanceOf(address(pair));

        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        uint256 actualUserToken0Balance = token0.balanceOf(user);
        uint256 actualUserToken1Balance = token1.balanceOf(user);

        uint256 actualPairToken0Balance = token0.balanceOf(address(pair));
        uint256 actualPairToken1Balance = token1.balanceOf(address(pair));

        assertEq(
            actualPairToken0Balance, initialPairToken0Balance + (initialUserToken0Balance - actualUserToken0Balance)
        );
        assertEq(
            actualPairToken1Balance, initialPairToken1Balance + (initialUserToken1Balance - actualUserToken1Balance)
        );
    }

    // test initial liquidity
    function test_mint_MintsRightAmountOfLp() public {
        uint256 amountToken0In = INITIAL_USER_BALANCE / 2;
        uint256 amountToken1In = INITIAL_USER_BALANCE / 2;

        uint256 initialUserLpTokenBalance = pair.balanceOf(user);
        assertEq(initialUserLpTokenBalance, 0);

        uint256 initialTotalSupply = pair.totalSupply();
        assertEq(initialTotalSupply, 0);

        uint256 expectedLpAmount = Math.sqrt(amountToken0In * amountToken1In);

        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        uint256 actualUserLpTokenBalance = pair.balanceOf(user);

        assertEq(actualUserLpTokenBalance, expectedLpAmount);
        assertEq(pair.totalSupply(), expectedLpAmount);
    }

    function test_mint_UpdatesReserves() public {
        (uint256 initialReserveAmountToken0, uint256 initialReserveAmountToken1) = pair.getReserves();

        uint256 amountToken0In = INITIAL_USER_BALANCE / 2;
        uint256 amountToken1In = INITIAL_USER_BALANCE / 2;

        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);
        pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();

        (uint256 actualReserveAmountToken0, uint256 actualReserveAmountToken1) = pair.getReserves();

        assertEq(actualReserveAmountToken0, initialReserveAmountToken0 + amountToken0In);
        assertEq(actualReserveAmountToken1, initialReserveAmountToken1 + amountToken1In);
    }

    // somehow works
    function test_mint_EmitsTranferMintAndSyncEvents() public {
        uint256 amountToken0In = INITIAL_USER_BALANCE / 2;
        uint256 amountToken1In = INITIAL_USER_BALANCE / 2;

        vm.startPrank(user);
        token0.approve(address(pair), INITIAL_USER_BALANCE);
        token1.approve(address(pair), INITIAL_USER_BALANCE);

        // trasferFrom user token0
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(pair), amountToken0In);

        // trasferFrom user token0
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(pair), amountToken1In);

        // _mint
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user, Math.sqrt(amountToken0In * amountToken1In));

        // _updateReserves
        vm.expectEmit(true, true, false, false);
        emit Sync(amountToken0In, amountToken1In);

        // Mint event
        vm.expectEmit(true, false, false, true);
        emit Mint(user, amountToken0In, amountToken1In);

        pair.mint(user, amountToken0In, amountToken1In);
        vm.stopPrank();
    }

    /////////////////
    // burn
    /////////////////

    function test_burn_RevertsWhenNoLiquidityInPool() public {
        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__NoLiquidityInPool.selector);
        vm.prank(user);
        pair.burn(user);
    }

    function test_burn_RevertsWhenCallerHasNoLpTokens() public initialLiquidity {
        address caller = makeAddr("caller");

        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__NoLiquidityTokensToBurn.selector);
        vm.prank(caller);
        pair.burn(caller);
    }

    function test_burn_BurnsLpOfCaller() public initialLiquidity {
        uint256 initialUserLpBalance = pair.balanceOf(user);
        assert(initialUserLpBalance > 0);

        uint256 expectedAmountLpBurned = initialUserLpBalance;

        vm.startPrank(user);
        pair.burn(user);

        uint256 actualUserLpBalance = pair.balanceOf(user);

        assertEq(actualUserLpBalance, 0);
        assertEq(initialUserLpBalance - actualUserLpBalance, expectedAmountLpBurned);
    }

    function test_burn_RedeemsUserAppropriateAmountOfTokens() public initialLiquidity {
        uint256 initialUserToken0Balance = token0.balanceOf(user);
        uint256 initialUserToken1Balance = token1.balanceOf(user);

        uint256 initialPairToken0Balance = token0.balanceOf(address(pair));
        uint256 initialPairToken1Balance = token1.balanceOf(address(pair));

        vm.startPrank(user);
        pair.burn(user);

        uint256 actualUserToken0Balance = token0.balanceOf(user);
        uint256 actualUserToken1Balance = token1.balanceOf(user);

        uint256 actualPairToken0Balance = token0.balanceOf(address(pair));
        uint256 actualPairToken1Balance = token1.balanceOf(address(pair));

        assertEq(actualUserToken0Balance - initialUserToken0Balance, initialPairToken0Balance - actualPairToken0Balance);
        assertEq(actualUserToken1Balance - initialUserToken1Balance, initialPairToken1Balance - actualPairToken1Balance);

        assertEq(actualPairToken0Balance, 0);
        assertEq(actualPairToken1Balance, 0);
    }

    // doesn't work somehow what the fuck
    function test_burn_SendsTokenToAddressTo() public initialLiquidity {
        address to = makeAddr("to");

        uint256 initialToToken0Balance = token0.balanceOf(to);
        uint256 initialToToken1Balance = token1.balanceOf(to);

        assertEq(initialToToken0Balance, 0);
        assertEq(initialToToken1Balance, 0);

        vm.startPrank(user);
        (uint256 amountToken0Out, uint256 amountToken1Out) = pair.burn(to);
        console.log("Test logs");
        console.log("amountToken0Out: ", amountToken0Out);
        console.log("amountToken1Out: ", amountToken1Out);

        uint256 actualToToken0Balance = token0.balanceOf(to);
        uint256 actualToToken1Balance = token1.balanceOf(to);

        assertEq(actualToToken0Balance, initialToToken0Balance + amountToken0Out);
        assertEq(actualToToken1Balance, initialToToken1Balance + amountToken1Out);
    }

    // doesn't work
    function test_burn_UpdatesReserves() public initialLiquidity {}

    // somehow works
    function test_burn_EmitsTransferSyncAndBurnEvents() public initialLiquidity {
        (uint256 initialReserveAmountToken0, uint256 initialReserveAmountToken1) = pair.getReserves();

        vm.startPrank(user);

        // _burn
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(0), pair.balanceOf(user));

        // transfer user token0
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), user, initialReserveAmountToken0);

        // transfer user token1
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), user, initialReserveAmountToken1);

        // _updateReserves
        vm.expectEmit(true, true, false, false);
        emit Sync(0, 0);

        // Burn event
        vm.expectEmit(true, true, false, true);
        emit Burn(user, initialReserveAmountToken0, initialReserveAmountToken1, user);

        pair.burn(user);
        vm.stopPrank();
    }

    /////////////////
    // swap
    /////////////////

    function test_swap_RevertWhenNoneOfAmountsOutAreNonZero() public {
        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__OnlyOneAmountOutShouldBeNonZero.selector);
        vm.prank(user);
        pair.swap(user, 0, 0);
    }

    function test_swap_RevertsWhenAllAmountsOutAreNonZero() public {
        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__OnlyOneAmountOutShouldBeNonZero.selector);
        vm.prank(user);
        pair.swap(user, 100e18, 100e18);
    }

    function test_swap_RevertsWhenNoLiquidityInPool() public {
        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__NoLiquidityInPool.selector);
        vm.prank(user);
        pair.swap(user, 100e18, 0);

        vm.expectRevert(UniswapV2Pair.UniswapV2Pair__NoLiquidityInPool.selector);
        vm.prank(user);
        pair.swap(user, 0, 100e18);
    }

    function test_swap_SwapsToken0ForToken1() public initialLiquidity {
        address to = makeAddr("to");

        uint256 wantedAmountToken1Out = 200e18;

        uint256 initialUserToken0Balance = token0.balanceOf(user);

        uint256 initialToToken1Balance = token1.balanceOf(to);

        vm.startPrank(user);
        (uint256 amountToken0In,) = pair.swap(to, 0, wantedAmountToken1Out);

        uint256 actualUserToken0Balance = token0.balanceOf(user);

        uint256 actualToToken1Balance = token1.balanceOf(to);

        assertEq(actualUserToken0Balance, initialUserToken0Balance - amountToken0In);
        assertEq(actualToToken1Balance, initialToToken1Balance + wantedAmountToken1Out);
    }

    function test_swap_SwapsToken1ForToken0() public initialLiquidity {
        address to = makeAddr("to");

        uint256 wantedAmountToken0Out = 100e18;

        uint256 initialUserToken1Balance = token1.balanceOf(user);

        uint256 initialToToken0Balance = token0.balanceOf(to);

        vm.startPrank(user);
        (, uint256 amountToken1In) = pair.swap(to, wantedAmountToken0Out, 0);

        uint256 actualUserToken1Balance = token1.balanceOf(user);

        uint256 actualToToken0Balance = token0.balanceOf(to);

        assertEq(actualUserToken1Balance, initialUserToken1Balance - amountToken1In);
        assertEq(actualToToken0Balance, initialToToken0Balance + wantedAmountToken0Out);
    }

    function test_swap_UpdatesReserves() public initialLiquidity {
        (uint256 initialReserveAmountToken0, uint256 initialReserveAmountToken1) = pair.getReserves();

        uint256 wantedAmountToken0Out = 100e18;
        uint256 wantedAmountToken1Out = 200e18;

        vm.startPrank(user);
        (uint256 amountToken0In, uint256 amountToken1In) = pair.swap(user, wantedAmountToken0Out, 0);
        (uint256 amountToken0In2, uint256 amountToken1In2) = pair.swap(user, 0, wantedAmountToken1Out);

        amountToken0In += amountToken0In2;
        amountToken1In += amountToken1In2;

        (uint256 actualReserveAmountToken0, uint256 actualReserveAmountToken1) = pair.getReserves();

        assertEq(actualReserveAmountToken0, initialReserveAmountToken0 - wantedAmountToken0Out + amountToken0In);
        assertEq(actualReserveAmountToken1, initialReserveAmountToken1 - wantedAmountToken1Out + amountToken1In);
    }

    function test_swap_EmitsTransferSyncAndSwapEvents() public initialLiquidity {
        uint256 wantedAmountToken1Out = 200e18;

        uint256 amountToken0In = 150000000000000000000;

        (uint256 reserveAmountToken0, uint256 reserveAmountToken1) = pair.getReserves();

        uint256 newReserveAmountToken0 = reserveAmountToken0 + amountToken0In;
        uint256 newReserveAmountToken1 = reserveAmountToken1 - wantedAmountToken1Out;

        vm.prank(user);

        // transferFrom user token0
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(pair), amountToken0In);

        // transfer user token1
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), user, wantedAmountToken1Out);

        // _updateReserves
        vm.expectEmit(true, true, false, false);
        emit Sync(newReserveAmountToken0, newReserveAmountToken1);

        // Swap event
        vm.expectEmit(true, true, false, true);
        emit Swap(user, amountToken0In, 0, 0, wantedAmountToken1Out, user);

        pair.swap(user, 0, wantedAmountToken1Out);
    }

    function test_swap_EmitsTransferSyncAndSwapEvents2() public initialLiquidity {
        uint256 wantedAmountToken0Out = 100e18;

        uint256 amountToken1In = 300e18;

        (uint256 reserveAmountToken0, uint256 reserveAmountToken1) = pair.getReserves();

        uint256 newReserveAmountToken0 = reserveAmountToken0 - wantedAmountToken0Out;
        uint256 newReserveAmountToken1 = reserveAmountToken1 + amountToken1In;

        vm.prank(user);

        // transferFrom user token1
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(pair), amountToken1In);

        // transfer user token0
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(pair), user, wantedAmountToken0Out);

        // _updateReserves
        vm.expectEmit(true, true, false, false);
        emit Sync(newReserveAmountToken0, newReserveAmountToken1);

        // Swap event
        vm.expectEmit(true, true, false, true);
        emit Swap(user, 0, amountToken1In, wantedAmountToken0Out, 0, user);

        pair.swap(user, wantedAmountToken0Out, 0);
    }
}
