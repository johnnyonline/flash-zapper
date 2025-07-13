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

    // scrvUSD
    address public scrvusd_addressesRegistry = 0x16B8111A999A9bDC3181192620A8F7b2439837Dd;
    address public scrvusd_collateralToken = 0x0655977FEb2f289A4aB78af67BAB0d17aAb84367;
    address public scrvusd_priceOracle = 0x629b6c0DcDf865584FD58a08727ABb9Db7390e28;
    address public scrvusd_troveManager = 0xa0290af48d2E43162A1a05Ab9d01a4ca3a8B60CB;
    address public scrvusd_borrowerOperations = 0xD55cB395408678cab7ebFDB69F74E461E5307780;
    address public scrvusd_sortedTroves = 0x67453E302D54f9b98C19526ab39DBD14B974d096;
    uint256 public scrvusd_branchIndex = 0;
    string public scrvusd_exchangeName = "scrvusd";

    // // sDAI
    // address public sdai_addressesRegistry = 0x65799d1368Ed24125179dd6Bf5e9b845797Ca1Ba;
    // address public sdai_collateralToken = 0x83F20F44975D03b1b09e64809B757c47f942BEeA;
    // address public sdai_priceOracle = 0xC470A1574B469A562fb237e289FDb217f8C14dc9;
    // address public sdai_troveManager = 0x7F1171686e6028c321517EdB6DD70321164b6343;
    // address public sdai_borrowerOperations = 0x7C0eaAA7749B2c703A828407adA186dfc8866E1E;
    // address public sdai_sortedTroves = 0x3eccE7bFe668A1aF0c520661ca79859d4C5605A9;
    // uint256 public sdai_branchIndex = 1;
    // string public sdai_exchangeName = "sdai";

    // // sUSDS
    // address public susds_addressesRegistry = 0x7f32320669e22380d00b28492E4479b93872d568;
    // address public susds_collateralToken = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    // address public susds_priceOracle = 0x806B2921E394b3f84A549AB89CF73e57F0C882c5;
    // address public susds_troveManager = 0x2ba8e31b6C1C9f46046315406E840dBabeA803a8;
    // address public susds_borrowerOperations = 0x05d1b7cef2D8AD38Cb867bDEEd1E9674Ad2E5b31;
    // address public susds_sortedTroves = 0xb456F5852C35505f119B60C28438bF488289ca1f;
    // uint256 public susds_branchIndex = 2;
    // string public susds_exchangeName = "susds";

    // // sfrxUSD
    // address public sfrxusd_addressesRegistry = 0x4B3eb2b1bBb0134D5ED5DAA35FeA78424B9481cd;
    // address public sfrxusd_collateralToken = 0xcf62F905562626CfcDD2261162a51fd02Fc9c5b6;
    // address public sfrxusd_priceOracle = 0xcDA8ccA990afF26fD8298e0d30304E4d01F7B387;
    // address public sfrxusd_troveManager = 0x53A5DE1b94d7409F75FFF49fd81A823fb874BF71;
    // address public sfrxusd_borrowerOperations = 0x8bf82598fB8424cA59FfbFe88543820d05b0d425;
    // address public sfrxusd_sortedTroves = 0x07ac2Ba2aa4A7223dD5A63583808A3d79d8a979e;
    // uint256 public sfrxusd_branchIndex = 3;
    // string public sfrxusd_exchangeName = "sfrxusd";

    // // sUSDe
    // address public susde_addressesRegistry = 0x20E3630D9ce22c7f3A4aee735fa007C06f4709dF;
    // address public susde_collateralToken = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    // address public susde_priceOracle = 0x0DAaFdDcf74451caec724Bcd2f0d7E4025C95B94;
    // address public susde_troveManager = 0x9dc845b500853F17E238C36Ba120400dBEa1D02A;
    // address public susde_borrowerOperations = 0x783da97a2fEb06fc3a302041bf1Ae096B8eF0019;
    // address public susde_sortedTroves = 0xfBa97F86967FeACd3e62a0FcAC5C19D7B60Fb7D4;
    // uint256 public susde_branchIndex = 4;
    // string public susde_exchangeName = "susde";

    // tBTC
    address public tbtc_addressesRegistry = 0xc693C91c855f4B51957f8ea221534538232F0f98;
    address public tbtc_collateralToken = 0x18084fbA666a33d37592fA2633fD49a74DD93a88;
    address public tbtc_priceOracle = 0xCe1Ca28e54fD3BD431F893DDFFFa1bd619C0517e;
    address public tbtc_troveManager = 0x64454C84Dc289C7CDe7E2eE2F87Ae1196bC9cD36;
    address public tbtc_borrowerOperations = 0x40785101e6BB3c546A7B07b8F883ef79763932EF;
    address public tbtc_sortedTroves = 0x2BD5a16F63480454A8302aD640323AB765A96930;
    uint256 public tbtc_branchIndex = 5;
    string public tbtc_exchangeName = "tbtc";

    // WBTC18
    address public wbtc18_addressesRegistry = 0x2AFF30744843aF04F68286Fa4818d44e93b80561;
    address public wbtc18_collateralToken = 0xF53bb90bd20c2a3Eb3eB01e8233130a69Db58324;
    address public wbtc18_priceOracle = 0x4d349971C23d6142e8dE9dEbbfdBB045B7AAbA49;
    address public wbtc18_troveManager = 0x085AbEe74F74E343647bdD2D68927e59163A0904;
    address public wbtc18_borrowerOperations = 0xfc72d7301c323A5BcfD10FfDE35908CE201B6c52;
    address public wbtc18_sortedTroves = 0x26e6307CA1F7Ba57BeDb16a80E366b01e814eD77;
    uint256 public wbtc18_branchIndex = 6;
    string public wbtc18_exchangeName = "wbtc18";

    // // cbBTC18
    // address public cbbtc18_addressesRegistry = 0x0F7Eb92d20e9624601D7dD92122AEd80Efa8ec6a;
    // address public cbbtc18_collateralToken = 0x7fd713FE57FCD0A7636C152Faba6bDC2D3B27d15;
    // address public cbbtc18_priceOracle = 0xAF99E6Cf5832222C0E22eF6bf0868C4Ed7f2953F;
    // address public cbbtc18_troveManager = 0x0291C873838F7B62D743952D268BEbe9ace1efa4;
    // address public cbbtc18_borrowerOperations = 0xD00182E777f6DA3220355965412c9605Fcd80aA5;
    // address public cbbtc18_sortedTroves = 0x2e937bbf06AD085e98D6EDdeC887589D61EDD3B7;
    // uint256 public cbbtc18_branchIndex = 7;
    // string public cbbtc18_exchangeName = "cbbtc18";

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

        //     // sDAI
        //     params.push(
        //         Params({
        //             exchange: address(0),
        //             leverageZapper: address(0),
        //             addressesRegistry: sdai_addressesRegistry,
        //             collateralToken: sdai_collateralToken,
        //             priceOracle: sdai_priceOracle,
        //             troveManager: sdai_troveManager,
        //             borrowerOperations: sdai_borrowerOperations,
        //             sortedTroves: sdai_sortedTroves,
        //             branchIndex: sdai_branchIndex,
        //             ltv: USD_LTV,
        //             exchangeName: sdai_exchangeName
        //         })
        //     );

        //     // sUSDS
        //     params.push(
        //         Params({
        //             exchange: address(0),
        //             leverageZapper: address(0),
        //             addressesRegistry: susds_addressesRegistry,
        //             collateralToken: susds_collateralToken,
        //             priceOracle: susds_priceOracle,
        //             troveManager: susds_troveManager,
        //             borrowerOperations: susds_borrowerOperations,
        //             sortedTroves: susds_sortedTroves,
        //             branchIndex: susds_branchIndex,
        //             ltv: USD_LTV,
        //             exchangeName: susds_exchangeName
        //         })
        //     );

        //     // sfrxUSD
        //     params.push(
        //         Params({
        //             exchange: address(0),
        //             leverageZapper: address(0),
        //             addressesRegistry: sfrxusd_addressesRegistry,
        //             collateralToken: sfrxusd_collateralToken,
        //             priceOracle: sfrxusd_priceOracle,
        //             troveManager: sfrxusd_troveManager,
        //             borrowerOperations: sfrxusd_borrowerOperations,
        //             sortedTroves: sfrxusd_sortedTroves,
        //             branchIndex: sfrxusd_branchIndex,
        //             ltv: USD_LTV,
        //             exchangeName: sfrxusd_exchangeName
        //         })
        //     );

        //     // sUSDe
        //     params.push(
        //         Params({
        //             exchange: address(0),
        //             leverageZapper: address(0),
        //             addressesRegistry: susde_addressesRegistry,
        //             collateralToken: susde_collateralToken,
        //             priceOracle: susde_priceOracle,
        //             troveManager: susde_troveManager,
        //             borrowerOperations: susde_borrowerOperations,
        //             sortedTroves: susde_sortedTroves,
        //             branchIndex: susde_branchIndex,
        //             ltv: USD_LTV,
        //             exchangeName: susde_exchangeName
        //         })
        //     );

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

        //     // cbBTC18
        //     params.push(
        //         Params({
        //             exchange: address(0),
        //             leverageZapper: address(0),
        //             addressesRegistry: cbbtc18_addressesRegistry,
        //             collateralToken: cbbtc18_collateralToken,
        //             priceOracle: cbbtc18_priceOracle,
        //             troveManager: cbbtc18_troveManager,
        //             borrowerOperations: cbbtc18_borrowerOperations,
        //             sortedTroves: cbbtc18_sortedTroves,
        //             branchIndex: cbbtc18_branchIndex,
        //             ltv: BTC_LTV,
        //             exchangeName: cbbtc18_exchangeName
        //         })
        //     );
        // }

        // function _deployCurvePool() internal returns (address) {
        //     address[] memory coins = new address[](2);
        //     coins[0] = address(0x85E30b8b263bC64d94b827ed450F2EdFEE8579dA); // USDaf
        //     coins[1] = sfrxusd_collateralToken;
        //     uint8[] memory assetTypes = new uint8[](2); // 0: standard
        //     bytes4[] memory methodIds = new bytes4[](2);
        //     address[] memory oracles = new address[](2);
        //     return curveStableswapFactory.deploy_plain_pool(
        //         "USDaf-sfrxUSD",
        //         "FFSPOOL",
        //         coins,
        //         100, // A
        //         1_000_000, // fee
        //         20_000_000_000, // _offpeg_fee_multiplier
        //         866, // _ma_exp_time
        //         0, // implementation id
        //         assetTypes,
        //         methodIds,
        //         oracles
        //     );
    }

}
