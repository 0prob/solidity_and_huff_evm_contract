// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {HuffDeployer} from "./HuffDeployer.sol";

contract ArbExecutorPrintTest is Test {
    function testDeployAndLog() public {
        bytes memory args1 = HuffDeployer.encode1(
                address(0x1111), address(0x2222), address(0x3333), address(0x4444),
                address(0x5555), address(0x6666), address(0x7777)
            );
        bytes memory args2 = HuffDeployer.encode2(
                address(0x8888), address(0x9999), address(0xaaaa), address(0xbbbb)
            );
        address addr = HuffDeployer.deploy_with_args_as("ArbExecutor", bytes.concat(args1, args2), address(this));
        require(addr != address(0), "deploy failed");
        console.log("Deployed address:", addr);
        assertEq(uint256(vm.load(addr, bytes32(uint256(0)))), 0x1111, "slot 0 owner");
        assertEq(uint256(vm.load(addr, bytes32(uint256(7)))), 0x2222, "slot 7 balancer");
        assertEq(uint256(vm.load(addr, bytes32(uint256(8)))), 0x3333, "slot 8 uniV3");
        assertEq(uint256(vm.load(addr, bytes32(uint256(9)))), 0x4444, "slot 9 sushiV3");
        assertEq(uint256(vm.load(addr, bytes32(uint256(10)))), 0x5555, "slot 10 quickV3");
        assertEq(uint256(vm.load(addr, bytes32(uint256(11)))), 0x6666, "slot 11 aave");
        assertEq(uint256(vm.load(addr, bytes32(uint256(12)))), 0x7777, "slot 12 poolManager");
        assertEq(uint256(vm.load(addr, bytes32(uint256(13)))), 0x8888, "slot 13 uniV2");
        assertEq(uint256(vm.load(addr, bytes32(uint256(14)))), 0x9999, "slot 14 sushiV2");
        assertEq(uint256(vm.load(addr, bytes32(uint256(15)))), 0xaaaa, "slot 15 quickV2");
        assertEq(uint256(vm.load(addr, bytes32(uint256(16)))), 0xbbbb, "slot 16 quickV4");
        assertEq(uint256(vm.load(addr, bytes32(uint256(6)))), 1, "slot 6 lock unlocked");
    }

    /// Mirrors script/deploy_mainnet.sh: bare runtime deployed first, storage
    /// configured by a post-deploy initialize(address x11) call.
    function testInitializeConfiguresBareRuntime() public {
        address addr = address(0x1234567890AbcdEF1234567890aBcdef12345678);
        vm.etch(addr, HuffDeployer.runtimeBytecode());

        bytes memory initCall = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,address,address,address,address)",
            address(0x1111), address(0x2222), address(0x3333), address(0x4444),
            address(0x5555), address(0x6666), address(0x7777), address(0x8888),
            address(0x9999), address(0xaaaa), address(0xbbbb)
        );
        (bool ok, bytes memory data) = addr.call(initCall);
        require(ok, string(data));

        assertEq(uint256(vm.load(addr, bytes32(uint256(0)))), 0x1111, "slot 0 owner");
        assertEq(uint256(vm.load(addr, bytes32(uint256(7)))), 0x2222, "slot 7 balancer");
        assertEq(uint256(vm.load(addr, bytes32(uint256(12)))), 0x7777, "slot 12 poolManager");
        assertEq(uint256(vm.load(addr, bytes32(uint256(16)))), 0xbbbb, "slot 16 quickV4");
        assertEq(uint256(vm.load(addr, bytes32(uint256(6)))), 1, "slot 6 lock unlocked");

        (bool okOwner, bytes memory ownerData) = addr.staticcall(abi.encodeWithSignature("owner()"));
        require(okOwner, "owner() failed");
        assertEq(abi.decode(ownerData, (address)), address(0x1111), "owner() getter");

        // Second initialize must be rejected (slot 0 already set).
        (bool okAgain,) = addr.call(initCall);
        require(!okAgain, "re-initialize must revert");
    }
}
