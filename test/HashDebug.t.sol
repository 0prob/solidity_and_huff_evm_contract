// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;
import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ArbExecutor} from "../src/ArbExecutor.sol";

contract RecorderTarget { function record() external {} }

contract HashDebug is Test {
    function testHashMatch() public {
        RecorderTarget r = new RecorderTarget();
        ArbExecutor.Call[] memory calls = new ArbExecutor.Call[](1);
        calls[0] = ArbExecutor.Call(address(r), 0, abi.encodeWithSelector(RecorderTarget.record.selector));
        bytes memory raw = abi.encode(calls);
        console.log("raw len:", raw.length);
        bytes32 w0; assembly { w0 := mload(add(raw, 0x20)) }
        console.logBytes32(w0);
        bytes32 w1; assembly { w1 := mload(add(raw, 0x40)) }
        console.logBytes32(w1);
        bytes32 w2; assembly { w2 := mload(add(raw, 0x60)) }
        console.logBytes32(w2);
        bytes32 w3; assembly { w3 := mload(add(raw, 0x80)) }
        console.logBytes32(w3);
        bytes32 w4; assembly { w4 := mload(add(raw, 0xa0)) }
        console.logBytes32(w4);
        bytes32 w5; assembly { w5 := mload(add(raw, 0xc0)) }
        console.logBytes32(w5);
        bytes32 w6; assembly { w6 := mload(add(raw, 0xe0)) }
        console.logBytes32(w6);
        bytes32 w7; assembly { w7 := mload(add(raw, 0x100)) }
        console.logBytes32(w7);
    }
}
