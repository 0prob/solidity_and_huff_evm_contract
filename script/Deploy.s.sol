// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Script, console2} from "forge-std/Script.sol";
import {HuffDeployer} from "../test/HuffDeployer.sol";

/// Deploy ArbExecutor with the same factory/router slots as the live Polygon executor.
/// Constructor rejects any zero address across all 17 config words.
contract DeployScript is Script {
    function run() external {
        address owner = vm.envAddress("OWNER");

        // encode1 → slots 0,7,8,9,10,11,12,13
        bytes memory args1 = HuffDeployer.encode1(
            owner,
            address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), // balancer vault
            address(0x1F98431c8aD98523631AE4a59f267346ea31F984), // uni v3 factory
            address(0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2), // sushi v3
            address(0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28), // quick v3 algebra
            address(0x2Bef16A0081565E72100D73CBe19B1Bd2d802380), // ramses
            address(0x794a61358D6845594F94dc1DB02A252b5b4814aD), // aave pool
            address(0x67366782805870060151383F4BbFF9daB53e5cD6) // v4 pool manager
        );
        // encode2 → slots 14..17 (constructor requires all non-zero)
        bytes memory args2 = HuffDeployer.encode2(
            address(0x9e5a52f57b3038F1b8EEE45f28b3c196dE8ce761), // uni v2
            address(0xc35DADB65012eC5796536bD9864eD8773aBc74C4), // sushi v2
            address(0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32), // quick v2
            address(0x0000000000000000000000000000000000000001) // quick v4 sentinel
        );
        bytes memory args = bytes.concat(args1, args2);

        vm.startBroadcast();
        address deployed = HuffDeployer.deploy_with_args_as("ArbExecutor", args, owner);
        require(deployed != address(0), "deploy failed");
        vm.stopBroadcast();

        console2.log("ArbExecutor deployed:", deployed);
    }
}
