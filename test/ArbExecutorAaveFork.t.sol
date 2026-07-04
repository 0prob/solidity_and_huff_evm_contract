// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ArbExecutor, ArbExecutorCodec} from "../src/ArbExecutor.sol";
import {Test} from "forge-std/Test.sol";

import {HuffDeployer} from "./HuffDeployer.sol";

contract ArbExecutorAaveForkTest is Test {
    ArbExecutor public executor;

    // Polygon mainnet addresses
    address constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant SUSHISWAP_V3_FACTORY = 0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2;
    address constant QUICKSWAP_V3_FACTORY = 0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28;
    address constant RAMSES_V3_FACTORY = 0x2Bef16A0081565E72100D73CBe19B1Bd2d802380;
    address constant POOL_MANAGER = 0x67366782805870060151383F4BbFF9daB53e5cD6;
    address constant UNISWAP_V2_FACTORY = 0x9e5a52f57b3038F1b8EEE45f28b3c196dE8ce761;
    address constant SUSHISWAP_V2_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant QUICKSWAP_V2_FACTORY = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
    address constant DFYN_V2_FACTORY = 0xE7Fb3e833eFE5F9c441105EB65Ef8b261266423B;
    address constant APESWAP_V2_FACTORY = 0xCf083Be4164828f00cAE704EC15a36D711491284;
    address constant MESHSWAP_V2_FACTORY = 0x9F3044B7945fe442E9A4d76A047783e1d70DCF80;
    address constant JETSWAP_V2_FACTORY = 0x668ad0Ed2622C62e24F0D5ab6B31E99125Ce0F46;
    address constant COMETHSWAP_V2_FACTORY = 0x93bc755FC5d27fa1Fa7c146C0625D1Cd18914d54;
    address constant QUICKSWAP_V4_FACTORY = 0x0000000000000000000000000000000000000001;
    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant USDC = 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;

    function setUp() public {
        string memory rpc = vm.envOr("POLYGON_RPC_URL", string("https://polygon-bor-rpc.publicnode.com"));
        vm.createSelectFork(rpc);

        bytes memory args1 = HuffDeployer.encode1(
                address(this), BALANCER_VAULT, UNISWAP_V3_FACTORY, SUSHISWAP_V3_FACTORY,
                QUICKSWAP_V3_FACTORY, RAMSES_V3_FACTORY, AAVE_POOL, POOL_MANAGER
            );
        bytes memory args2 = HuffDeployer.encode2(
                UNISWAP_V2_FACTORY, SUSHISWAP_V2_FACTORY, QUICKSWAP_V2_FACTORY, DFYN_V2_FACTORY,
                APESWAP_V2_FACTORY, MESHSWAP_V2_FACTORY, JETSWAP_V2_FACTORY, COMETHSWAP_V2_FACTORY, QUICKSWAP_V4_FACTORY
            );
        address addr = HuffDeployer.deploy_with_args_as("ArbExecutor", bytes.concat(args1, args2), address(this));
        require(addr != address(0), "deploy failed");
        executor = ArbExecutor(payable(addr));
    }

    function testAavePoolAddress() public {
        assertEq(executor.aavePool(), AAVE_POOL);
    }

    function testAavePoolInterfaceGetReserveData() public {
        // Verify the Aave Pool address is a real contract with the expected interface
        // by calling getReserveData() via staticcall on USDC
        (bool ok, bytes memory result) = AAVE_POOL.staticcall(abi.encodeWithSignature("getReserveData(address)", USDC));
        assertTrue(ok, "getReserveData staticcall failed");
        // Return data for a reserve should be > 0 bytes (at least one uint256)
        assertGt(result.length, 32, "getReserveData returned too little data");
    }

    function testExecuteOperationRevertsWithFlashLoanOnly() public {
        // Directly calling executeOperation (not via Aave flash loan) should revert
        // with FlashLoanOnly because msg.sender != aavePool
        vm.expectRevert(ArbExecutor.FlashLoanOnly.selector);
        executor.executeOperation(USDC, 1000, 0, address(this), "");
    }

    function testExecuteArbWithAaveRevertsWithEmptyRoute() public {
        ArbExecutor.Call[] memory calls;
        (bytes memory packedRoute,) = ArbExecutorCodec.buildPackedRoute(
            USDC, 1000, USDC, 0, block.timestamp + 1 days, _toCodecCalls(calls)
        );

        vm.expectRevert(ArbExecutor.EmptyRoute.selector);
        executor.executeArbWithAave(packedRoute);
    }

    function testExecuteArbWithAaveRevertsIfNotAuthorized() public {
        ArbExecutor.Call[] memory calls;
        (bytes memory packedRoute,) = ArbExecutorCodec.buildPackedRoute(
            USDC, 1000, USDC, 0, block.timestamp + 1 days, _toCodecCalls(calls)
        );

        // Call from a non-owner address
        vm.prank(address(0xdeadbeef));
        vm.expectRevert(ArbExecutor.Unauthorized.selector);
        executor.executeArbWithAave(packedRoute);
    }

    function testAavePoolExposesFlashLoanPremium() public view {
        (bool ok, bytes memory result) = AAVE_POOL.staticcall(abi.encodeWithSignature("FLASHLOAN_PREMIUM_TOTAL()"));
        assertTrue(ok, "FLASHLOAN_PREMIUM_TOTAL staticcall failed");
        assertGt(result.length, 0, "FLASHLOAN_PREMIUM_TOTAL returned no data");
    }

    function testAavePoolIsContract() public {
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(AAVE_POOL)
        }
        assertGt(codeSize, 0, "Aave Pool must be a deployed contract on the forked chain");
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
