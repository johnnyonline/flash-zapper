// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IExchange} from "./interfaces/IExchange.sol";
import {IFlashZapper} from "./interfaces/IFlashZapper.sol";

import "forge-std/Script.sol";

// ---- Usage ----

// deploy:
// forge script script/Deploy.s.sol:Deploy --verify --slow --legacy --etherscan-api-key $KEY --rpc-url $RPC_URL --broadcast

// verify:
// vyper -f solc_json src/price_feed.vy > out/build-info/verify.json
// vyper -f solc_json --path src/periphery --path src src/leverage_zapper.vy > out/build-info/verify.json

// constructor args:
// cast abi-encode "constructor(address)" 0xbACBBefda6fD1FbF5a2d6A79916F4B6124eD2D49

contract Deploy is Script {

    struct Params {
        address exchange;
        address flashZapper;
        address addressesRegistry;
        address collateralToken;
        address priceOracle;
        address troveManager;
        address borrowerOperations;
        address sortedTroves;
        uint256 branchIndex;
        uint256 ltv;
        string exchangeName;
    }

    Params[] public params;

    bool public isTest;
    address public deployer;

    IExchange public USDAF_EXCHANGE;

    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    uint256 public USD_LTV = 909_090_909_090_909_090; // 90.91%
    uint256 public BTC_LTV = 833_333_333_333_333_333; // 83.33%

    // ysyBOLD
    address public ysybold_addressesRegistry = 0x3414bd84dfF0900a9046a987f4dF2e0eF08Fa1ce;
    address public ysybold_collateralToken = 0x23346B04a7f55b8760E5860AA5A77383D63491cD;
    address public ysybold_priceOracle = 0x7F575323DDEDFbad449fEf5459FaD031FE49520b;
    address public ysybold_troveManager = 0xF8a25a2E4c863bb7CEa7e4B4eeb3866BB7f11718;
    address public ysybold_borrowerOperations = 0x57bd20aE68F845b35B76FE6e0239C9929EB48469;
    address public ysybold_sortedTroves = 0x98d9b02b41cc2F8e72775Da528401A33765bC166;
    uint256 public ysybold_branchIndex = 0;
    string public ysybold_exchangeName = "ysybold";

    // scrvUSD
    address public scrvusd_addressesRegistry = 0x0C7B6C6a60ae2016199d393695667c1482719C82;
    address public scrvusd_collateralToken = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address public scrvusd_priceOracle = 0xF125C72aE447eFDF3fA3601Eda9AC0Ebec06CBB8;
    address public scrvusd_troveManager = 0x7aFf0173e3D7C5416D8cAa3433871Ef07568220d;
    address public scrvusd_borrowerOperations = 0x9e601005deaaEE8294c686e28E1AFfd04Cc13830;
    address public scrvusd_sortedTroves = 0x233817bd6970F2Ec7F6963B02ab941dEC0A87A70;
    uint256 public scrvusd_branchIndex = 1;
    string public scrvusd_exchangeName = "scrvusd";

    // sUSDS
    address public susds_addressesRegistry = 0x330A0fDfc1818Be022FEDCE96A041293E16dc6d1;
    address public susds_collateralToken = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public susds_priceOracle = 0x2113468843CF2d0FD976690F4Ec6e4213Df46911;
    address public susds_troveManager = 0x53ce82AC43660AaB1F80FEcd1D74Afe7a033D505;
    address public susds_borrowerOperations = 0x336D9C5ecb9D6ce79C8C077D35426e714969b41d;
    address public susds_sortedTroves = 0x1D9Cc5A514368E6f28EBA79B2DB8FA5C9484B058;
    uint256 public susds_branchIndex = 2;
    string public susds_exchangeName = "susds";

    // sfrxUSD
    address public sfrxusd_addressesRegistry = 0x0ad1C302203F0fbB6Ca34641BDFeF0Bf4182377c;
    address public sfrxusd_collateralToken = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    address public sfrxusd_priceOracle = 0x653DF748Bf7A692555dCdbF4c504a8c84807f7C7;
    address public sfrxusd_troveManager = 0x478E7c27193Aca052964C3306D193446027630b0;
    address public sfrxusd_borrowerOperations = 0x2538cD346429eA59902e02448BB7A7c098e4554E;
    address public sfrxusd_sortedTroves = 0x7C1765fD1Ab5afaeD4A0A0aC74b2E4c45F5A5572;
    uint256 public sfrxusd_branchIndex = 3;
    string public sfrxusd_exchangeName = "sfrxusd";

    // tBTC
    address public tbtc_addressesRegistry = 0xbd9f75471990041A3e7C22872c814A273485E999;
    address public tbtc_collateralToken = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
    address public tbtc_priceOracle = 0xeaF3b36748D89d64EF1B6B3E1d7637C3E4745094;
    address public tbtc_troveManager = 0xfb17d0402ae557e3Efa549812b95e931B2B63bCE;
    address public tbtc_borrowerOperations = 0xDA9af112eDfD837EebC1780433481426a52556e0;
    address public tbtc_sortedTroves = 0xD7a4d09680B8211940f19E1D1D25dc6568a4E0d0;
    uint256 public tbtc_branchIndex = 4;
    string public tbtc_exchangeName = "tbtc";

    // WBTC18
    address public wbtc18_addressesRegistry = 0x2C5A85a3fd181857D02baff169D1e1cB220ead6d;
    address public wbtc18_collateralToken = 0xe065Bc161b90C9C4Bba2de7F1E194b70A3267c47;
    address public wbtc18_priceOracle = 0x4B74D043336678D2F62dae6595bc42DcCabC3BB1;
    address public wbtc18_troveManager = 0x7bd47Eca45ee18609D3D64Ba683Ce488ca9320A3;
    address public wbtc18_borrowerOperations = 0x664507f1445657D36D8064663653B7810971F411;
    address public wbtc18_sortedTroves = 0x4B677B2c2bdAA64BcA08c62c4596d526e319Ea7b;
    uint256 public wbtc18_branchIndex = 5;
    string public wbtc18_exchangeName = "wbtc18";

    function run() public {
        uint256 _pk = isTest ? 42_069 : vm.envUint("DEPLOYER_PRIVATE_KEY");
        VmSafe.Wallet memory _wallet = vm.createWallet(_pk);
        deployer = _wallet.addr;

        _populateParams();

        if (!isTest) console.log("Deployer address: %s", deployer);

        vm.startBroadcast(_pk);

        USDAF_EXCHANGE = IExchange(deployCode("usdaf"));

        for (uint256 i = 0; i < params.length; i++) {
            Params memory p = params[i];
            address _collateralExchange = deployCode(p.exchangeName);
            address _flashZapper = p.branchIndex == wbtc18_branchIndex
                ? deployCode("flash_zapper", abi.encode(USDAF_EXCHANGE, _collateralExchange, p.addressesRegistry, WBTC))
                : deployCode(
                    "flash_zapper", abi.encode(USDAF_EXCHANGE, _collateralExchange, p.addressesRegistry, address(0))
                );

            params[i].exchange = _collateralExchange;
            params[i].flashZapper = _flashZapper;

            if (isTest) {
                vm.label({account: _collateralExchange, newLabel: p.exchangeName});
                vm.label({account: _flashZapper, newLabel: "flashZapper"});
            } else {
                console.log("Collateral token: ", p.exchangeName);
                console.log("Exchange address: ", _collateralExchange);
                console.log("Flash Zapper address: ", _flashZapper);
            }
        }

        vm.stopBroadcast();
    }

    function _populateParams() internal {
        // // ysyBOLD
        // params.push(
        //     Params({
        //         exchange: address(0),
        //         flashZapper: address(0),
        //         addressesRegistry: ysybold_addressesRegistry,
        //         collateralToken: ysybold_collateralToken,
        //         priceOracle: ysybold_priceOracle,
        //         troveManager: ysybold_troveManager,
        //         borrowerOperations: ysybold_borrowerOperations,
        //         sortedTroves: ysybold_sortedTroves,
        //         branchIndex: ysybold_branchIndex,
        //         ltv: USD_LTV,
        //         exchangeName: ysybold_exchangeName
        //     })
        // );

        // scrvUSD
        params.push(
            Params({
                exchange: address(0),
                flashZapper: address(0),
                addressesRegistry: scrvusd_addressesRegistry,
                collateralToken: scrvusd_collateralToken,
                priceOracle: scrvusd_priceOracle,
                troveManager: scrvusd_troveManager,
                borrowerOperations: scrvusd_borrowerOperations,
                sortedTroves: scrvusd_sortedTroves,
                branchIndex: scrvusd_branchIndex,
                ltv: USD_LTV,
                exchangeName: scrvusd_exchangeName
            })
        );

        // // sUSDS
        // params.push(
        //     Params({
        //         exchange: address(0),
        //         flashZapper: address(0),
        //         addressesRegistry: susds_addressesRegistry,
        //         collateralToken: susds_collateralToken,
        //         priceOracle: susds_priceOracle,
        //         troveManager: susds_troveManager,
        //         borrowerOperations: susds_borrowerOperations,
        //         sortedTroves: susds_sortedTroves,
        //         branchIndex: susds_branchIndex,
        //         ltv: USD_LTV,
        //         exchangeName: susds_exchangeName
        //     })
        // );

        // // sfrxUSD
        // params.push(
        //     Params({
        //         exchange: address(0),
        //         flashZapper: address(0),
        //         addressesRegistry: sfrxusd_addressesRegistry,
        //         collateralToken: sfrxusd_collateralToken,
        //         priceOracle: sfrxusd_priceOracle,
        //         troveManager: sfrxusd_troveManager,
        //         borrowerOperations: sfrxusd_borrowerOperations,
        //         sortedTroves: sfrxusd_sortedTroves,
        //         branchIndex: sfrxusd_branchIndex,
        //         ltv: USD_LTV,
        //         exchangeName: sfrxusd_exchangeName
        //     })
        // );

        // tBTC
        params.push(
            Params({
                exchange: address(0),
                flashZapper: address(0),
                addressesRegistry: tbtc_addressesRegistry,
                collateralToken: tbtc_collateralToken,
                priceOracle: tbtc_priceOracle,
                troveManager: tbtc_troveManager,
                borrowerOperations: tbtc_borrowerOperations,
                sortedTroves: tbtc_sortedTroves,
                branchIndex: tbtc_branchIndex,
                ltv: BTC_LTV,
                exchangeName: tbtc_exchangeName
            })
        );

        // WBTC18
        params.push(
            Params({
                exchange: address(0),
                flashZapper: address(0),
                addressesRegistry: wbtc18_addressesRegistry,
                collateralToken: wbtc18_collateralToken,
                priceOracle: wbtc18_priceOracle,
                troveManager: wbtc18_troveManager,
                borrowerOperations: wbtc18_borrowerOperations,
                sortedTroves: wbtc18_sortedTroves,
                branchIndex: wbtc18_branchIndex,
                ltv: BTC_LTV,
                exchangeName: wbtc18_exchangeName
            })
        );
    }

}
