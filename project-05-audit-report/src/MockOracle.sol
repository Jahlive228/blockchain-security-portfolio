// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MockOracle
 * @notice Oracle de prix contrôlable — utilisé dans les tests
 *         Simule un oracle légitime ET un oracle malicieux
 */
contract MockOracle {
    uint256 public price;
    address public owner;

    constructor(uint256 _initialPrice) {
        price = _initialPrice;
        owner = msg.sender;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }

    // En production, seul un multisig devrait pouvoir changer le prix
    function setPrice(uint256 _price) external {
        price = _price;
    }
}