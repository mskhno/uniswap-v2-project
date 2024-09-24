// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UniswapV2ERC20} from "src/UniswapV2ERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

contract UniswapV2ERC20Test is Test {
    UniswapV2ERC20 token;

    string public name = "UniswapV2Token";
    string public symbol = "UNI";
    string public version = "V2";

    bytes32 DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address owner;
    uint256 ownerKey;
    address spender;
    uint256 spenderKey;

    bytes32 domainSeparator;

    function setUp() public {
        token = new UniswapV2ERC20(name, symbol);
        domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes(version)), block.chainid, address(token)
            )
        );
        (owner, ownerKey) = makeAddrAndKey("owner");
        (spender, spenderKey) = makeAddrAndKey("spender");

        // vm.deal(spender, 1000 ether);
    }

    function testConstructor() public {
        assertEq(token.DOMAIN_SEPARATOR(), domainSeparator);
    }

    function testPublicVariables() public {
        assertEq(token.VERSION(), version);
        assertEq(token.DOMAIN_SEPARATOR(), domainSeparator);
    }

    function testNonces() public {
        assertEq(token.nonces(owner), 0);
    }

    function testPermitRevertsWhenSignatureExpired() public {
        uint256 value = 1000;
        uint256 nonce = token.nonces(owner) + 1;
        uint256 deadline = block.timestamp + 600;

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        vm.warp(block.timestamp + 3600);
        vm.roll(block.number + 5);

        vm.prank(spender);
        vm.expectRevert(UniswapV2ERC20.UniswapV2ERC20__SignatureExpired.selector);
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitRevertsWhenSignatureIsInvalid() public {
        uint256 value = 1000;
        uint256 nonce = token.nonces(owner);
        uint256 deadline = block.timestamp + 600;

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)); // 10x more value
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(spenderKey, digest); // not owner signed signature

        vm.prank(spender);
        vm.expectRevert(UniswapV2ERC20.UniswapV2ERC20__InvalidSigner.selector);
        token.permit(owner, spender, value, deadline, v, r, s);
    }

    function testPermitApprovesSpenderWhenSignatureIsGood() public {
        uint256 value = 1000;
        uint256 nonce = token.nonces(owner);
        uint256 deadline = block.timestamp + 600;

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 digest = MessageHashUtils.toTypedDataHash(token.DOMAIN_SEPARATOR(), structHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, digest);

        vm.prank(spender);
        token.permit(owner, spender, value, deadline, v, r, s);

        assertEq(token.allowance(owner, spender), value);
    }
}
