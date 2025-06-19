// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface ISweep {

    // ============================================================================================
    // Owner functions
    // ============================================================================================

    function sweep_token(
        address token
    ) external;

}
