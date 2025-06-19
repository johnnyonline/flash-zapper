// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

interface ICurvePool {

    function add_liquidity(uint256[] memory amounts, uint256 min_mint_amount) external returns (uint256);

}
