// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {HuffDeployer} from "./HuffDeployer.sol";

contract ArbExecutorPrintTest is Test {
    function testDeployAndLog() public {
        bytes memory args1 = HuffDeployer.encode1(
                address(0x1111), address(0x2222), address(0x3333), address(0x4444),
                address(0x5555), address(0x6666), address(0x7777), address(0x8888)
            );
        bytes memory args2 = HuffDeployer.encode2(
                address(0x9999), address(0xaaaa), address(0xbbbb), address(0xcccc),
                address(0xdddd), address(0xeeee), address(0xffff), address(0x1000), address(0x1001)
            );
        bytes memory bytecode = HuffDeployer.concatInit(HuffDeployer.BYTECODE, args1, args2);
        address addr;
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        console.log("Deployed address:", addr);
        if (addr != address(0)) {
            console.log("Slot 0 (owner):", uint256(vm.load(addr, bytes32(uint256(0)))));
            console.log("Slot 7 (balancer):", uint256(vm.load(addr, bytes32(uint256(7)))));
            console.log("Slot 8 (uniV3):", uint256(vm.load(addr, bytes32(uint256(8)))));
            console.log("Slot 9 (sushiV3):", uint256(vm.load(addr, bytes32(uint256(9)))));
            console.log("Slot 10 (quickV3):", uint256(vm.load(addr, bytes32(uint256(10)))));
            console.log("Slot 11 (ramses):", uint256(vm.load(addr, bytes32(uint256(11)))));
            console.log("Slot 12 (aave):", uint256(vm.load(addr, bytes32(uint256(12)))));
            console.log("Slot 13 (poolManager):", uint256(vm.load(addr, bytes32(uint256(13)))));
            console.log("Slot 14 (uniV2):", uint256(vm.load(addr, bytes32(uint256(14)))));
            console.log("Slot 15 (sushiV2):", uint256(vm.load(addr, bytes32(uint256(15)))));
            console.log("Slot 16 (quickV2):", uint256(vm.load(addr, bytes32(uint256(16)))));
            console.log("Slot 17 (dfynV2):", uint256(vm.load(addr, bytes32(uint256(17)))));
            console.log("Slot 18 (apeV2):", uint256(vm.load(addr, bytes32(uint256(18)))));
            console.log("Slot 19 (meshV2):", uint256(vm.load(addr, bytes32(uint256(19)))));
            console.log("Slot 20 (jetV2):", uint256(vm.load(addr, bytes32(uint256(20)))));
            console.log("Slot 21 (comethV2):", uint256(vm.load(addr, bytes32(uint256(21)))));
            console.log("Slot 22 (quickV4):", uint256(vm.load(addr, bytes32(uint256(22)))));
            console.log("Slot 6 (locked):", uint256(vm.load(addr, bytes32(uint256(6)))));
        }
    }
}
