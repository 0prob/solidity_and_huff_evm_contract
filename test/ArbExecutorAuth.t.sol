// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ArbExecutor, ArbExecutorCodec} from "../src/ArbExecutor.sol";

import {HuffDeployer} from "./HuffDeployer.sol";

contract ArbExecutorAuthTest is Test {
    ArbExecutor public executor;
    address public owner = address(0x1);
    address public notOwner = address(0x2);

    function setUp() public {
        bytes memory args1 = HuffDeployer.encode1(
                owner, address(0x1000), address(0x1001), address(0x1002),
                address(0x1003), address(0x1005), address(0x1006)
            );
        bytes memory args2 = HuffDeployer.encode2(
                address(0x1007), address(0x1008), address(0x1009), address(0x100a)
            );
        address addr = HuffDeployer.deploy_with_args_as("ArbExecutor", bytes.concat(args1, args2), owner);
        require(addr != address(0), "deploy failed");
        executor = ArbExecutor(payable(addr));
    }

    function test_OnlyOwnerCanExecuteArb() public {
        ArbExecutor.Call[] memory calls = new ArbExecutor.Call[](1);
        calls[0] = ArbExecutor.Call({target: address(0xdead), value: 0, data: ""});
        (bytes memory packedRoute,) =
            ArbExecutorCodec.buildPackedRoute(address(0xcafe), 100, address(0xbeef), 0, block.timestamp + 1 days, _toCodecCalls(calls));

        // Non-owner should revert
        vm.prank(notOwner);
        vm.expectRevert();
        executor.executeArb(packedRoute);

        // Owner should NOT revert with Unauthorized (it might revert with something else due to mock addresses, but not Unauthorized)
        vm.prank(owner);
        try executor.executeArb(packedRoute) {
        // success or other revert
        }
        catch (bytes memory reason) {
            // Check that it's NOT Unauthorized
            bytes4 unauthorizedSelector = ArbExecutor.Unauthorized.selector;
            bytes4 receivedSelector;
            if (reason.length >= 4) {
                assembly {
                    receivedSelector := mload(add(reason, 32))
                }
            }
            assertTrue(receivedSelector != unauthorizedSelector, "Should not be unauthorized");
        }
    }

    function test_ApproveIfNeeded_Auth() public {
        // Owner should be able to call it
        vm.prank(owner);
        try executor.approveIfNeeded(address(0xcafe), address(0xface), 100) {}
        catch (bytes memory reason) {
            bytes4 unauthorizedSelector = ArbExecutor.Unauthorized.selector;
            bytes4 receivedSelector;
            if (reason.length >= 4) {
                assembly {
                    receivedSelector := mload(add(reason, 32))
                }
            }
            assertTrue(receivedSelector != unauthorizedSelector, "Owner should not be unauthorized");
        }

        // Non-owner should revert
        vm.prank(notOwner);
        vm.expectRevert(ArbExecutor.Unauthorized.selector);
        executor.approveIfNeeded(address(0xcafe), address(0xface), 100);
    }

    function test_PreApprove_Auth() public {
        // Non-owner should revert
        vm.prank(notOwner);
        vm.expectRevert(ArbExecutor.Unauthorized.selector);
        executor.preApprove(address(0xcafe), address(0xface));
    }

    function _toCodecCalls(ArbExecutor.Call[] memory calls)
        internal
        pure
        returns (ArbExecutorCodec.Call[] memory codecCalls)
    {
        codecCalls = new ArbExecutorCodec.Call[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            codecCalls[i] =
                ArbExecutorCodec.Call({target: calls[i].target, value: calls[i].value, data: calls[i].data});
        }
    }
}
