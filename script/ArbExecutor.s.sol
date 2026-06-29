// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ArbExecutor} from "../src/ArbExecutor.sol";

import {HuffDeployer} from "../test/HuffDeployer.sol";

contract ArbExecutorScript is Script {
    address internal constant DEFAULT_BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address internal constant DEFAULT_UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address internal constant DEFAULT_SUSHISWAP_V3_FACTORY = 0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2;
    address internal constant DEFAULT_QUICKSWAP_V3_FACTORY = 0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28;
    address internal constant DEFAULT_RAMSES_V3_FACTORY = 0x2Bef16A0081565E72100D73CBe19B1Bd2d802380;
    address internal constant DEFAULT_AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address internal constant DEFAULT_POOL_MANAGER = 0x67366782805870060151383F4BbFF9daB53e5cD6;
    address internal constant DEFAULT_UNISWAP_V2_FACTORY = 0x9e5a52f57b3038F1b8EEE45f28b3c196dE8ce761;
    address internal constant DEFAULT_SUSHISWAP_V2_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address internal constant DEFAULT_QUICKSWAP_V2_FACTORY = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
    address internal constant DEFAULT_DFYN_V2_FACTORY = 0xE7Fb3e833eFE5F9c441105EB65Ef8b261266423B;
    address internal constant DEFAULT_APESWAP_V2_FACTORY = 0xCf083Be4164828f00cAE704EC15a36D711491284;
    address internal constant DEFAULT_MESHSWAP_V2_FACTORY = 0x9F3044B7945fe442E9A4d76A047783e1d70DCF80;
    address internal constant DEFAULT_JETSWAP_V2_FACTORY = 0x668ad0Ed2622C62e24F0D5ab6B31E99125Ce0F46;
    address internal constant DEFAULT_COMETHSWAP_V2_FACTORY = 0x93bc755FC5d27fa1Fa7c146C0625D1Cd18914d54;
    address internal constant DEFAULT_QUICKSWAP_V4_FACTORY = 0x0000000000000000000000000000000000000001; // ponytail: fill when Algebra Integral deploys on Polygon

    function run() external returns (ArbExecutor executor) {
        address owner = vm.envAddress("OWNER");
        address balancerVault = vm.envOr("BALANCER_VAULT", DEFAULT_BALANCER_VAULT);
        address uniswapV3Factory = vm.envOr("UNISWAP_V3_FACTORY", DEFAULT_UNISWAP_V3_FACTORY);
        address sushiV3Factory = vm.envOr("SUSHISWAP_V3_FACTORY", DEFAULT_SUSHISWAP_V3_FACTORY);
        address quickswapV3Factory = vm.envOr("QUICKSWAP_V3_FACTORY", DEFAULT_QUICKSWAP_V3_FACTORY);
        address ramsesV3Factory = vm.envOr("RAMSES_V3_FACTORY", DEFAULT_RAMSES_V3_FACTORY);
        address aavePool = vm.envOr("AAVE_POOL", DEFAULT_AAVE_POOL);
        address poolManager = vm.envOr("POOL_MANAGER", DEFAULT_POOL_MANAGER);
        address uniswapV2Factory = vm.envOr("UNISWAP_V2_FACTORY", DEFAULT_UNISWAP_V2_FACTORY);
        address sushiV2Factory = vm.envOr("SUSHISWAP_V2_FACTORY", DEFAULT_SUSHISWAP_V2_FACTORY);
        address quickswapV2Factory = vm.envOr("QUICKSWAP_V2_FACTORY", DEFAULT_QUICKSWAP_V2_FACTORY);
        address dfynV2Factory = vm.envOr("DFYN_V2_FACTORY", DEFAULT_DFYN_V2_FACTORY);
        address apeSwapV2Factory = vm.envOr("APESWAP_V2_FACTORY", DEFAULT_APESWAP_V2_FACTORY);
        address meshSwapV2Factory = vm.envOr("MESHSWAP_V2_FACTORY", DEFAULT_MESHSWAP_V2_FACTORY);
        address jetSwapV2Factory = vm.envOr("JETSWAP_V2_FACTORY", DEFAULT_JETSWAP_V2_FACTORY);
        address comethSwapV2Factory = vm.envOr("COMETHSWAP_V2_FACTORY", DEFAULT_COMETHSWAP_V2_FACTORY);
        address quickswapV4Factory = vm.envOr("QUICKSWAP_V4_FACTORY", DEFAULT_QUICKSWAP_V4_FACTORY);

        vm.startBroadcast();

        bytes memory args1 = HuffDeployer.encode1(
                owner, balancerVault, uniswapV3Factory, sushiV3Factory,
                quickswapV3Factory, ramsesV3Factory, aavePool, poolManager
            );
        bytes memory args2 = HuffDeployer.encode2(
                uniswapV2Factory, sushiV2Factory, quickswapV2Factory, dfynV2Factory,
                apeSwapV2Factory, meshSwapV2Factory, jetSwapV2Factory, comethSwapV2Factory, quickswapV4Factory
            );
        bytes memory combinedArgs = abi.encodePacked(args1, args2);
        bytes memory bytecode = HuffDeployer.concatInit(HuffDeployer.BYTECODE, combinedArgs, new bytes(0));

        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        require(addr != address(0), "deploy failed");
        executor = ArbExecutor(payable(addr));

        vm.stopBroadcast();

        console2.log("ArbExecutor deployed:", address(executor));
        console2.log("owner:", owner);
        console2.log("balancerVault:", balancerVault);
        console2.log("uniswapV3Factory:", uniswapV3Factory);
        console2.log("sushiV3Factory:", sushiV3Factory);
        console2.log("quickswapV3Factory:", quickswapV3Factory);
        console2.log("ramsesV3Factory:", ramsesV3Factory);
        console2.log("aavePool:", aavePool);
        console2.log("poolManager:", poolManager);
        console2.log("uniswapV2Factory:", uniswapV2Factory);
        console2.log("sushiV2Factory:", sushiV2Factory);
        console2.log("quickswapV2Factory:", quickswapV2Factory);
        console2.log("dfynV2Factory:", dfynV2Factory);
        console2.log("apeSwapV2Factory:", apeSwapV2Factory);
        console2.log("meshSwapV2Factory:", meshSwapV2Factory);
        console2.log("jetSwapV2Factory:", jetSwapV2Factory);
        console2.log("comethSwapV2Factory:", comethSwapV2Factory);
        console2.log("quickswapV4Factory:", quickswapV4Factory);
    }
}
