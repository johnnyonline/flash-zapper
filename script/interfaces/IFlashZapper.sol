// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IFlashZapper {

    function lever_up_trove(
        uint256 trove_id,
        uint256 flash_loan_amount,
        uint256 usdaf_amount,
        uint256 max_upfront_fee
    ) external;

}
