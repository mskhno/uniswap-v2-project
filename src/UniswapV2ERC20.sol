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
    //@Vlad Здесь могут иногда сделать ошибку, например неправильные переменные напишут
    // Пример уязвимостей:
    // 1) https://github.com/code-423n4/2023-10-brahma-findings/issues/23
    // 2) https://github.com/code-423n4/2023-12-revolutionprotocol-findings/issues/77
    // 3) https://solodit.xyz/issues/improper-domain-separator-hash-in-_domainseparatorv4-function-codehawks-beanstalk-the-finale-git
    // Более подробно на Solodit по поиску "EIP712"
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /////////////////
    // FUNCTIONS
    /////////////////
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)), //@Vlad Вот здесь молодец, некоторые разрабы не знают как правильно кодировать string, массивы в EIP712
                keccak256(bytes(VERSION)), //@Vlad Пример: https://github.com/sherlock-audit/2024-04-titles-judging/issues/74

                //@Vlad Подход записать DOMAIN_SEPARATOR используя нынешний chainId имеет место быть, но не безупречен
                // А всё потому, что в случае хард форка chainId в сети поменяется. И тогда одна и та же подпись будет действительна на 2 разных сетях
                // Вот пример: https://github.com/code-423n4/2022-07-golom-findings/issues/391
                // Насколько я знаю, ни одна подобная атака ни разу не была запущена за 8 лет. Но в качестве best practice лучше так не делать
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
    //@Vlad Здесь всё хорошо написано
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
