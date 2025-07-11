// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IFlashZapper {

    function lever_up_trove(
        uint256 trove_id,
        uint256 flash_loan_amount,
        uint256 usdaf_amount,
        uint256 max_upfront_fee
    ) external;

    function lever_down_trove(
        uint256 trove_id,
        uint256 flash_loan_amount,
        uint256 min_usdaf_amount,
        uint256 collateral_amount
    ) external;

}
