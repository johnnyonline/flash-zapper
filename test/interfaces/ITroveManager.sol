// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

interface ITroveManager {

    struct LatestTroveData {
        uint256 entireDebt;
        uint256 entireColl;
        uint256 redistBoldDebtGain;
        uint256 redistCollGain;
        uint256 accruedInterest;
        uint256 recordedDebt;
        uint256 annualInterestRate;
        uint256 weightedRecordedDebt;
        uint256 accruedBatchManagementFee;
        uint256 lastInterestRateAdjTime;
    }

    function getTroveIdsCount() external view returns (uint256);
    function getLatestTroveData(
        uint256 _troveId
    ) external view returns (LatestTroveData memory trove);
    function getCurrentICR(uint256 _troveId, uint256 _price) external view returns (uint256);

}
