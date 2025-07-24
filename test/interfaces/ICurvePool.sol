// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.25;

interface ICurvePool {

    function coins(
        uint256 index
    ) external view returns (address);
    function add_liquidity(uint256[] calldata _amounts, uint256 _min_mint_amount) external returns (uint256);

}
