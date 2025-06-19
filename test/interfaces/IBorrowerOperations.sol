// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

interface IBorrowerOperations {

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

    function openTrove(
        address _owner,
        uint256 _ownerIndex,
        uint256 _collAmount,
        uint256 _boldAmount,
        uint256 _upperHint,
        uint256 _lowerHint,
        uint256 _annualInterestRate,
        uint256 _maxUpfrontFee,
        address _addManager,
        address _removeManager,
        address _receiver
    ) external returns (uint256);
    function setRemoveManagerWithReceiver(uint256 _troveId, address _manager, address _receiver) external;

}
