// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title SecureAMM
 * @notice AMM avec oracle TWAP (Time-Weighted Average Price)
 *         Le prix est une moyenne sur les derniers blocs
 *         Impossible à manipuler en une seule transaction
 */
contract SecureAMM {
    uint256 public reserveA;
    uint256 public reserveB;

    mapping(address => uint256) public balanceA;
    mapping(address => uint256) public balanceB;

    uint256 public constant FEE_BPS = 30;

    // TWAP — accumulation du prix * temps
    uint256 public priceACumulativeLast;
    uint256 public priceBCumulativeLast;
    uint256 public blockTimestampLast;

    // Fenêtre TWAP : 10 blocs minimum
    uint256 public constant TWAP_WINDOW = 10;

    // Snapshots pour calculer le TWAP
    uint256 public twapPriceA; // prix moyen sur la fenêtre
    uint256 public snapshotCumulative;
    uint256 public snapshotTimestamp;

    event Swap(address indexed user, uint256 amountIn, uint256 amountOut, bool aToB);
    event TWAPUpdated(uint256 newPrice, uint256 timestamp);

    constructor(uint256 initA, uint256 initB) {
        reserveA           = initA;
        reserveB           = initB;
        blockTimestampLast = block.timestamp;
        snapshotTimestamp  = block.timestamp;
        twapPriceA         = (initB * 1e18) / initA;
        snapshotCumulative = 0;
    }

    function deal(address user, uint256 amtA, uint256 amtB) external {
        balanceA[user] += amtA;
        balanceB[user] += amtB;
    }

    /**
     * @notice Prix spot — pour référence uniquement
     *         NE PAS utiliser comme oracle de prix
     */
    function getSpotPrice() public view returns (uint256) {
        require(reserveA > 0, "No liquidity");
        return (reserveB * 1e18) / reserveA;
    }

    /**
     * @notice Prix TWAP — résistant à la manipulation
     * @dev Moyenne pondérée par le temps sur TWAP_WINDOW blocs
     *      Un attaquant devrait maintenir le prix manipulé pendant
     *      toute la fenêtre — coûteux et détectable
     */
    function getTWAPPrice() public view returns (uint256) {
        uint256 elapsed = block.timestamp - snapshotTimestamp;
        if (elapsed == 0) return twapPriceA;

        uint256 currentSpot = getSpotPrice();
        uint256 accumulated = priceACumulativeLast +
            currentSpot * (block.timestamp - blockTimestampLast);
        uint256 totalElapsed = block.timestamp - snapshotTimestamp;

        return (accumulated - snapshotCumulative) / totalElapsed;
    }

    /**
     * @notice Met à jour l'accumulateur TWAP après chaque swap
     */
    function _updateTWAP() internal {
        uint256 timeElapsed = block.timestamp - blockTimestampLast;
        if (timeElapsed > 0 && reserveA > 0) {
            priceACumulativeLast += getSpotPrice() * timeElapsed;
            blockTimestampLast    = block.timestamp;
        }

        // Renouvelle le snapshot si la fenêtre est dépassée
        if (block.timestamp >= snapshotTimestamp + TWAP_WINDOW) {
            twapPriceA         = getTWAPPrice();
            snapshotCumulative = priceACumulativeLast;
            snapshotTimestamp  = block.timestamp;
            emit TWAPUpdated(twapPriceA, block.timestamp);
        }
    }

    function swapAtoB(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Zero amount");
        require(balanceA[msg.sender] >= amountIn, "Insufficient A");

        _updateTWAP();

        uint256 amountInWithFee = amountIn * (10000 - FEE_BPS);
        amountOut = (amountInWithFee * reserveB)
                  / (reserveA * 10000 + amountInWithFee);

        require(amountOut > 0,        "Insufficient output");
        require(amountOut < reserveB, "Insufficient liquidity");

        balanceA[msg.sender] -= amountIn;
        balanceB[msg.sender] += amountOut;
        reserveA += amountIn;
        reserveB -= amountOut;

        emit Swap(msg.sender, amountIn, amountOut, true);
    }

    function swapBtoA(uint256 amountIn) external returns (uint256 amountOut) {
        require(amountIn > 0, "Zero amount");
        require(balanceB[msg.sender] >= amountIn, "Insufficient B");

        _updateTWAP();

        uint256 amountInWithFee = amountIn * (10000 - FEE_BPS);
        amountOut = (amountInWithFee * reserveA)
                  / (reserveB * 10000 + amountInWithFee);

        require(amountOut > 0,        "Insufficient output");
        require(amountOut < reserveA, "Insufficient liquidity");

        balanceB[msg.sender] -= amountIn;
        balanceA[msg.sender] += amountOut;
        reserveB += amountIn;
        reserveA -= amountOut;

        emit Swap(msg.sender, amountIn, amountOut, false);
    }
}