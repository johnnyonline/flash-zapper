// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {ICurvePool} from "./interfaces/ICurvePool.sol";

import "../script/Deploy.s.sol";

import "forge-std/Test.sol";

abstract contract Base is Deploy, Test {

    address public user = address(420);

    uint256 public LTV;
    uint256 public BRANCH_INDEX;
    address public PRICE_ORACLE;
    address public TROVE_MANAGER;
    address public BORROWER_OPERATIONS;
    address public SORTED_TROVES;
    string public EXCHANGE_NAME;

    IERC20 public COLLATERAL_TOKEN;
    IERC20 public WRAPPED_COLLATERAL_TOKEN;
    IExchange public EXCHANGE;
    IFlashZapper public FLASH_ZAPPER;

    address public constant CRVUSD_FLASH_LENDER = 0x26dE7861e213A5351F6ED767d00e0839930e9eE1;

    IERC20 public constant USDAF = IERC20(0x9Cf12ccd6020b6888e4D4C4e4c7AcA33c1eB91f8);
    IERC20 public constant CRVUSD = IERC20(0xf939E0A03FB07F59A73314E73794Be0E57ac1b4E);
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    uint256 public MIN_FUZZ;
    uint256 public MAX_FUZZ;
    uint256 public MIN_LEVERAGE;
    uint256 public MAX_LEVERAGE;

    uint256 public MIN_FUZZ_BTC = 0.03 ether;
    uint256 public MAX_FUZZ_BTC = 0.08 ether;
    uint256 public MIN_LEVERAGE_BTC = 3 ether; // 3x leverage
    uint256 public MAX_LEVERAGE_BTC = 4 ether; // 4x

    uint256 public MIN_FUZZ_USD = 3000 ether;
    uint256 public MAX_FUZZ_USD = 10_000 ether;
    uint256 public MIN_LEVERAGE_USD = 3 ether; // 3x
    uint256 public MAX_LEVERAGE_USD = 7 ether; // 7x

    function setUp() public virtual {
        // notify deplyment script that this is a test
        isTest = true;

        // create fork
        uint256 _blockNumber = 22_991_354; // cache state for faster tests
        vm.selectFork(vm.createFork(vm.envString("MAINNET_RPC_URL"), _blockNumber));

        // deploy and initialize contracts
        run();

        // Airdrop some WBTC to WBTC18
        airdrop(WBTC, wbtc18_collateralToken, 100_000 * 1e8); // 100k WBTC

        // Make sure there's enough liquidity in the Curve Pool
        addLiquidity_scrvusdusdaf();
    }

    function airdrop(address _token, address _to, uint256 _amount) public {
        _token == address(0) ? vm.deal(_to, _amount) : deal({token: _token, to: _to, give: _amount});
    }

    function _setParams(
        uint256 _index
    ) internal {
        Params memory p = params[_index];
        COLLATERAL_TOKEN = IERC20(p.collateralToken);
        WRAPPED_COLLATERAL_TOKEN = COLLATERAL_TOKEN;
        EXCHANGE = IExchange(p.exchange);
        FLASH_ZAPPER = IFlashZapper(p.flashZapper);
        LTV = p.ltv;
        PRICE_ORACLE = p.priceOracle;
        TROVE_MANAGER = p.troveManager;
        BORROWER_OPERATIONS = p.borrowerOperations;
        SORTED_TROVES = p.sortedTroves;
        BRANCH_INDEX = p.branchIndex;
        EXCHANGE_NAME = p.exchangeName;

        if (LTV == USD_LTV) {
            MIN_FUZZ = MIN_FUZZ_USD;
            MAX_FUZZ = MAX_FUZZ_USD;
            MIN_LEVERAGE = MIN_LEVERAGE_USD;
            MAX_LEVERAGE = MAX_LEVERAGE_USD;
        } else {
            MIN_FUZZ = MIN_FUZZ_BTC;
            MAX_FUZZ = MAX_FUZZ_BTC;
            MIN_LEVERAGE = MIN_LEVERAGE_BTC;
            MAX_LEVERAGE = MAX_LEVERAGE_BTC;
        }

        // Override for WBTC
        if (BRANCH_INDEX == wbtc18_branchIndex) {
            COLLATERAL_TOKEN = IERC20(WBTC);
            WRAPPED_COLLATERAL_TOKEN = IERC20(p.collateralToken);
        }
    }

    function addLiquidity_scrvusdusdaf() public {
        address seeder = address(69);
        uint256 amount = 10_000_000 * 1e18;
        ICurvePool curvePool = ICurvePool(0x3bE454C4391690ab4DDae3Fb987c8147b8Ecc08A); // scrvUSD/USDaf Curve StableNG Pool
        IERC20 scrvusd = IERC20(curvePool.coins(0)); // scrvUSD
        IERC20 usdaf = IERC20(curvePool.coins(1)); // USDaf
        airdrop(address(scrvusd), seeder, amount);
        airdrop(address(usdaf), seeder, amount);
        vm.startPrank(seeder);
        scrvusd.approve(address(curvePool), amount);
        usdaf.approve(address(curvePool), amount);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount;
        amounts[1] = amount;
        curvePool.add_liquidity(amounts, 0);
        vm.stopPrank();
    }

}
