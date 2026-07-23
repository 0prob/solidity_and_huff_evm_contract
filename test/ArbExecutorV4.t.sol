// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ArbExecutor, ArbExecutorCodec, IERC20Minimal} from "../src/ArbExecutor.sol";
import {HuffDeployer} from "./HuffDeployer.sol";
import {MockToken} from "./ArbExecutorAtomic.t.sol";

/// Mock of Uniswap V4 PoolManager semantics the executor relies on:
/// unlock(data) -> unlockCallback(data) on the caller, swap() records signed
/// BalanceDelta (positive = manager owes caller), debts settled via
/// sync -> transfer -> settle, credits collected via take. unlock reverts
/// CurrencyNotSettled unless every touched currency nets to zero.
contract MockPoolManager {
    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    error AlreadyUnlocked();
    error ManagerLocked();
    error CurrencyNotSettled();

    bool public unlocked;
    uint256 public rateNum = 1;
    uint256 public rateDen = 1;

    mapping(address => int256) public currencyDelta;
    address[] internal touched;
    uint256 public nonzeroDeltaCount;

    address internal syncedCurrency;
    uint256 internal syncedReserves;
    bool internal syncPending;

    function setRate(uint256 num, uint256 den) external {
        rateNum = num;
        rateDen = den;
    }

    function unlock(bytes calldata data) external returns (bytes memory result) {
        if (unlocked) revert AlreadyUnlocked();
        unlocked = true;
        (bool ok, bytes memory ret) =
            msg.sender.call(abi.encodeWithSignature("unlockCallback(bytes)", data));
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
        if (nonzeroDeltaCount != 0) revert CurrencyNotSettled();
        unlocked = false;
        for (uint256 i; i < touched.length; ++i) {
            delete currencyDelta[touched[i]];
        }
        delete touched;
        result = ret;
    }

    function swap(PoolKey memory key, SwapParams memory params, bytes memory)
        external
        returns (int256 delta)
    {
        if (!unlocked) revert ManagerLocked();
        require(key.currency0 < key.currency1, "mock: unsorted key");
        require(params.amountSpecified < 0, "mock: exact-input only");
        uint256 amtIn = uint256(-params.amountSpecified);
        uint256 amtOut = amtIn * rateNum / rateDen;
        (address cIn, address cOut) =
            params.zeroForOne ? (key.currency0, key.currency1) : (key.currency1, key.currency0);
        _applyDelta(cIn, params.amountSpecified);
        _applyDelta(cOut, int256(amtOut));
        int256 a0 = params.zeroForOne ? params.amountSpecified : int256(amtOut);
        int256 a1 = params.zeroForOne ? int256(amtOut) : params.amountSpecified;
        delta = (a0 << 128) | (a1 & int256(uint256(type(uint128).max)));
    }

    function sync(address currency) external {
        syncedCurrency = currency;
        syncedReserves = IERC20Minimal(currency).balanceOf(address(this));
        syncPending = true;
    }

    function settle() external payable returns (uint256 paid) {
        require(syncPending, "mock: sync before settle");
        paid = IERC20Minimal(syncedCurrency).balanceOf(address(this)) - syncedReserves;
        _applyDelta(syncedCurrency, int256(paid));
        syncPending = false;
    }

    function take(address currency, address to, uint256 amount) external {
        if (!unlocked) revert ManagerLocked();
        _applyDelta(currency, -int256(amount));
        require(IERC20Minimal(currency).transfer(to, amount), "mock: take transfer");
    }

    function _applyDelta(address currency, int256 change) internal {
        int256 prev = currencyDelta[currency];
        int256 next = prev + change;
        if (prev == 0 && next != 0) {
            nonzeroDeltaCount++;
            touched.push(currency);
        }
        if (prev != 0 && next == 0) {
            nonzeroDeltaCount--;
        }
        currencyDelta[currency] = next;
    }
}

contract ArbExecutorV4Test is Test {
    bytes4 constant UNLOCK_CALLBACK_SELECTOR = 0x91dd7346;
    bytes4 constant CALLBACK_ONLY = 0xc21d53e8; // CallbackOnly()
    bytes4 constant INVALID_FLASH_LOAN_CONTEXT = 0xadd4adc0; // InvalidFlashLoanContext()
    bytes4 constant INSUFFICIENT_PROFIT = 0x4e88422a; // InsufficientProfit(uint256,uint256)

    MockToken tokenA; // currency0 (lower address)
    MockToken tokenB; // currency1
    MockPoolManager pm;
    ArbExecutor executor;

    function setUp() public {
        pm = new MockPoolManager();
        MockToken t0 = new MockToken();
        MockToken t1 = new MockToken();
        (tokenA, tokenB) = address(t0) < address(t1) ? (t0, t1) : (t1, t0);

        bytes memory args1 = HuffDeployer.encode1(
                address(this), address(0x1000), address(0x1001), address(0x1002),
                address(0x1003), address(0x1005), address(pm)
            );
        bytes memory args2 = HuffDeployer.encode2(
                address(0x1007), address(0x1008), address(0x1009), address(0x100a)
            );
        address addr = HuffDeployer.deploy_with_args("ArbExecutor", bytes.concat(args1, args2));
        require(addr != address(0), "deploy failed");
        executor = ArbExecutor(payable(addr));
    }

    /// Route step: PM.unlock(abi.encode(PoolKey, SwapParams)) — the layout
    /// UNLOCK_CALLBACK consumes (8 words: key then params).
    function _v4UnlockCall(bool zeroForOne, int256 amountSpecified)
        internal
        view
        returns (ArbExecutorCodec.Call[] memory calls)
    {
        MockPoolManager.PoolKey memory key = MockPoolManager.PoolKey({
            currency0: address(tokenA),
            currency1: address(tokenB),
            fee: 3000,
            tickSpacing: 60,
            hooks: address(0)
        });
        MockPoolManager.SwapParams memory params = MockPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: 0
        });
        calls = new ArbExecutorCodec.Call[](1);
        calls[0] = ArbExecutorCodec.Call({
            target: address(pm),
            value: 0,
            data: abi.encodeWithSelector(MockPoolManager.unlock.selector, abi.encode(key, params))
        });
    }

    function _executeDirect(address profitToken, uint256 minProfit, ArbExecutorCodec.Call[] memory calls)
        internal
        returns (bool ok, bytes memory data)
    {
        (bytes memory packedRoute,) = ArbExecutorCodec.buildPackedRoute(
            address(tokenA), 0, profitToken, minProfit, block.timestamp + 1 days, calls
        );
        (ok, data) =
            address(executor).call(abi.encodeWithSelector(ArbExecutor.executeArbDirect.selector, packedRoute));
    }

    function testV4SwapZeroForOnePaysCurrency0TakesCurrency1() public {
        tokenA.mint(address(executor), 100 ether);
        tokenB.mint(address(pm), 1000 ether);

        (bool ok, bytes memory data) =
            _executeDirect(address(tokenB), 1, _v4UnlockCall(true, -int256(100 ether)));

        require(ok, string(data));
        require(abi.decode(data, (uint256)) == 100 ether, "profit must equal swap output");
        require(tokenA.balances(address(executor)) == 0, "input tokens must be paid to PM");
        require(tokenA.balances(address(pm)) == 100 ether, "PM must receive settled input");
        require(tokenB.balances(address(executor)) == 100 ether, "output tokens must be taken");
        require(pm.nonzeroDeltaCount() == 0, "all deltas settled");
    }

    function testV4SwapOneForZeroPaysCurrency1TakesCurrency0() public {
        tokenB.mint(address(executor), 100 ether);
        tokenA.mint(address(pm), 1000 ether);
        pm.setRate(2, 1); // non-1:1 rate: 100 in -> 200 out

        (bool ok, bytes memory data) =
            _executeDirect(address(tokenA), 1, _v4UnlockCall(false, -int256(100 ether)));

        require(ok, string(data));
        require(abi.decode(data, (uint256)) == 200 ether, "profit must equal swap output");
        require(tokenB.balances(address(executor)) == 0, "input tokens must be paid to PM");
        require(tokenB.balances(address(pm)) == 100 ether, "PM must receive settled input");
        require(tokenA.balances(address(executor)) == 200 ether, "output tokens must be taken");
    }

    function testV4InsufficientProfitRollsBackAtomically() public {
        tokenA.mint(address(executor), 100 ether);
        tokenB.mint(address(pm), 1000 ether);

        (bool ok, bytes memory data) =
            _executeDirect(address(tokenB), 200 ether, _v4UnlockCall(true, -int256(100 ether)));

        require(!ok, "must revert on insufficient profit");
        require(bytes4(data) == INSUFFICIENT_PROFIT, "wrong revert selector");
        require(tokenA.balances(address(executor)) == 100 ether, "input balance must roll back");
        require(tokenB.balances(address(executor)) == 0, "output balance must roll back");
        require(tokenB.balances(address(pm)) == 1000 ether, "PM liquidity must roll back");
    }

    function testV4CallbackRejectsNonPoolManagerCaller() public {
        (bool ok, bytes memory data) =
            address(executor).call(abi.encodeWithSelector(UNLOCK_CALLBACK_SELECTOR, bytes("")));
        require(!ok, "must revert for non-PM caller");
        require(bytes4(data) == CALLBACK_ONLY, "wrong revert selector");
    }

    function testV4CallbackRejectsPoolManagerOutsideRoute() public {
        vm.prank(address(pm));
        (bool ok, bytes memory data) =
            address(executor).call(abi.encodeWithSelector(UNLOCK_CALLBACK_SELECTOR, bytes("")));
        require(!ok, "must revert outside execution phase");
        require(bytes4(data) == INVALID_FLASH_LOAN_CONTEXT, "wrong revert selector");
    }
}
