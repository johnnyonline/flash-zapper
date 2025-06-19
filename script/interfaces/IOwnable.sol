// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IOwnable {

    // ============================================================================================
    // Storage
    // ============================================================================================

    function owner() external view returns (address);
    function pending_owner() external view returns (address);

    // ============================================================================================
    // Owner functions
    // ============================================================================================

    function transfer_ownership(
        address newOwner
    ) external;
    function accept_ownership() external;

}
