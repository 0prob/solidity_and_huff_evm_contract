// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {ArbExecutor, ArbExecutorCodec} from "../src/ArbExecutor.sol";
import {Test, console2} from "forge-std/Test.sol";
import {HuffDeployer} from "./HuffDeployer.sol";
import {IERC20Minimal} from "../src/ArbExecutor.sol";

/// Reproduce live dry-run: Algebra/QuickSwap V3 hop0 IIA on
/// WMATIC/SAND pool 0xD85A25332b57cc447a791100E7317e534d553761.
contract ArbExecutorAlgebraIiaTest is Test {
    ArbExecutor public executor;

    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant SUSHISWAP_V3_FACTORY = 0x917933899c6a5F8E37F31E19f92CdBFF7e8FF0e2;
    address constant QUICKSWAP_V3_FACTORY = 0x411b0fAcC3489691f28ad58c47006AF5E3Ab3A28;
    address constant AAVE_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;
    address constant POOL_MANAGER = 0x67366782805870060151383F4BbFF9daB53e5cD6;
    address constant UNISWAP_V2_FACTORY = 0x9e5a52f57b3038F1b8EEE45f28b3c196dE8ce761;
    address constant SUSHISWAP_V2_FACTORY = 0xc35DADB65012eC5796536bD9864eD8773aBc74C4;
    address constant QUICKSWAP_V2_FACTORY = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32;
    address constant QUICKSWAP_V4_FACTORY = 0x0000000000000000000000000000000000000001;

    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address constant SAND = 0xBbba073C31bF03b8ACf7c28EF0738DeCF3695683;
    address constant ALGEBRA_POOL = 0xD85A25332b57cc447a791100E7317e534d553761;
    /// Live dry-run input (1.6e18 + 16).
    uint256 constant AIN = 1600000000000000016;
    uint160 constant MIN_SQRT_PLUS = 4295128740; // TickMath.MIN_SQRT_RATIO + 1

    function setUp() public {
        string memory rpc = vm.envOr("POLYGON_RPC_URL", string("https://polygon-bor-rpc.publicnode.com"));
        vm.createSelectFork(rpc);

        bytes memory args1 = HuffDeployer.encode1(
            address(this),
            BALANCER_VAULT,
            UNISWAP_V3_FACTORY,
            SUSHISWAP_V3_FACTORY,
            QUICKSWAP_V3_FACTORY,
            AAVE_POOL,
            POOL_MANAGER
        );
        bytes memory args2 = HuffDeployer.encode2(
            UNISWAP_V2_FACTORY, SUSHISWAP_V2_FACTORY, QUICKSWAP_V2_FACTORY, QUICKSWAP_V4_FACTORY
        );
        address addr = HuffDeployer.deploy_with_args_as("ArbExecutor", bytes.concat(args1, args2), address(this));
        require(addr != address(0), "deploy failed");
        executor = ArbExecutor(payable(addr));
    }

    function testAlgebraExactInCallbackPaysWmatic() public {
        // Fund executor like a Balancer flash would.
        deal(WMATIC, address(executor), AIN * 2);

        // Callback data: (uint8 protoId=3 Algebra, token0, token1, uint24 feePips)
        // fee is unused by poolByPair but must be present for huff offsets.
        bytes memory cb = abi.encode(uint8(3), WMATIC, SAND, uint24(500));

        // IUniswapV3Pool.swap(recipient, zeroForOne, amountSpecified, sqrtPriceLimitX96, data)
        // zeroForOne=true: WMATIC(token0) -> SAND(token1), exact-in positive amount.
        bytes memory swapData = abi.encodeWithSelector(
            bytes4(keccak256("swap(address,bool,int256,uint160,bytes)")),
            address(executor),
            true,
            int256(uint256(AIN)),
            MIN_SQRT_PLUS,
            cb
        );

        ArbExecutor.Call[] memory calls = new ArbExecutor.Call[](1);
        calls[0] = ArbExecutor.Call({target: ALGEBRA_POOL, value: 0, data: swapData});

        // profitToken = SAND so ASSERT_PROFIT sees the swap output (not a full cycle).
        (bytes memory packedRoute,) = ArbExecutorCodec.buildPackedRoute(
            WMATIC, AIN, SAND, 0, block.timestamp + 1 days, _toCodecCalls(calls)
        );

        uint256 wmaticBefore = IERC20Minimal(WMATIC).balanceOf(address(executor));
        uint256 sandBefore = IERC20Minimal(SAND).balanceOf(address(executor));

        uint256 profit = executor.executeArbDirect(packedRoute);
        uint256 wmaticAfter = IERC20Minimal(WMATIC).balanceOf(address(executor));
        uint256 sandAfter = IERC20Minimal(SAND).balanceOf(address(executor));
        console2.log("realized profit (SAND)", profit);
        console2.log("wmatic spent", wmaticBefore - wmaticAfter);
        console2.log("sand gained", sandAfter - sandBefore);
        assertGt(sandAfter, sandBefore, "should receive SAND (callback paid WMATIC, not IIA)");
        assertLt(wmaticAfter, wmaticBefore, "should spend WMATIC");
        assertGt(profit, 0, "SAND balance should rise");
    }

    function _toCodecCalls(ArbExecutor.Call[] memory calls)
        internal
        pure
        returns (ArbExecutorCodec.Call[] memory out)
    {
        out = new ArbExecutorCodec.Call[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            out[i] = ArbExecutorCodec.Call({target: calls[i].target, value: calls[i].value, data: calls[i].data});
        }
    }
}
