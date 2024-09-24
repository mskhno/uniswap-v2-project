// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {console} from "forge-std/console.sol";

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

contract UniswapV2ERC20 is ERC20, Nonces {
    /////////////////
    // ERRORS
    /////////////////
    error UniswapV2ERC20__SignatureExpired();
    error UniswapV2ERC20__InvalidSigner();

    /////////////////
    // STATE VARIABLES
    /////////////////
    string public constant VERSION = "V2";
    bytes32 public immutable DOMAIN_SEPARATOR;
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /////////////////
    // FUNCTIONS
    /////////////////
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(VERSION)),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Sets "value" as the allowance of "spender" over the "owner"s tokens, given "owner" has signed the approval.
     * @param owner The owner of tokens
     * @param spender Address allowed for spending tokens
     * @param value Allowance value
     * @param deadline Timestamp in the future until which the signature is valid
     */
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public // Reentrancy?
    {
        // check deadline
        if (block.timestamp > deadline) {
            revert UniswapV2ERC20__SignatureExpired();
        }
        // construct digest
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)); // MessageHashUtils.toTypedDataHash(DOMAIN_SEPARATOR, structHash);
        // check signer
        address signer = ECDSA.recover(digest, v, r, s);
        if (signer != owner) {
            revert UniswapV2ERC20__InvalidSigner();
        }
        // approve
        _approve(owner, spender, value);
    }
}
