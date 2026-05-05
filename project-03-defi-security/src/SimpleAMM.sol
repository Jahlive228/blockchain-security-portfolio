// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title SimpleAMM
 * @notice Pool AMM minimal implémentant x*y=k
 *         Deux tokens : tokenA et tokenB
 *         VULN : getPrice() retourne le prix spot instantané
 *                manipulable dans la même transaction
 */
contract SimpleAMM {
    // Réserves du pool
    uint256 public reserveA;
    uint256 public reserveB;

    // Balances simplifiées (pas d'ERC20 pour rester lisible)
    mapping(address => uint256) public balanceA;
    mapping(address => uint256) public balanceB;

    uint256 public constant FEE_BPS = 30; // 0.3% comme Uniswap V2

    event Swap(address indexed user, uint256 amountIn, uint256 amountOut, bool aToB);
    event LiquidityAdded(address indexed user, uint256 amountA, uint256 amountB);

    constructor(uint256 initA, uint256 initB) {
        reserveA = initA;
        reserveB = initB;
    }

    // Donne des tokens à une adresse (simule un mint)
    function deal(address user, uint256 amtA, uint256 amtB) external {
        balanceA[user] += amtA;
        balanceB[user] += amtB;
    }

    /**
     * @notice Prix spot — VULNÉRABLE
     * @dev Retourne reserveB / reserveA
     *      Manipulable avec un gros swap dans la même tx
     */
    function getSpotPrice() public view returns (uint256) {
        require(reserveA > 0, "No liquidity");
        // Prix de A en unités de B (scaled 1e18)
        return (reserveB * 1e18) / reserveA;
    }

    /**
     * @notice Swap tokenA → tokenB
     * @dev Formule : amountOut = (amountIn * (10000 - FEE) * reserveB)
     *                           / (reserveA * 10000 + amountIn * (10000 - FEE))
     */
    function swapAtoB(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Zero amount");
        require(balanceA[msg.sender] >= amountIn, "Insufficient A");

        uint256 amountInWithFee = amountIn * (10000 - FEE_BPS);
        amountOut = (amountInWithFee * reserveB)
                  / (reserveA * 10000 + amountInWithFee);

        require(amountOut > 0, "Insufficient output");
        require(amountOut < reserveB, "Insufficient liquidity");

        balanceA[msg.sender] -= amountIn;
        balanceB[msg.sender] += amountOut;
        reserveA += amountIn;
        reserveB -= amountOut;

        emit Swap(msg.sender, amountIn, amountOut, true);
    }

    /**
     * @notice Swap tokenB → tokenA
     */
    function swapBtoA(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Zero amount");
        require(balanceB[msg.sender] >= amountIn, "Insufficient B");

        uint256 amountInWithFee = amountIn * (10000 - FEE_BPS);
        amountOut = (amountInWithFee * reserveA)
                  / (reserveB * 10000 + amountInWithFee);

        require(amountOut > 0, "Insufficient output");
        require(amountOut < reserveA, "Insufficient liquidity");

        balanceB[msg.sender] -= amountIn;
        balanceA[msg.sender] += amountOut;
        reserveB += amountIn;
        reserveA -= amountOut;

        emit Swap(msg.sender, amountIn, amountOut, false);
    }
}