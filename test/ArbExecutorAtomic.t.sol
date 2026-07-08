// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {
    ArbExecutor,
    ArbExecutorCodec,
    IBalancerVault,
    IERC20Minimal,
    IFlashLoanRecipient,
    IFlashLoanSimpleReceiver
} from "../src/ArbExecutor.sol";
import {HuffDeployer} from "./HuffDeployer.sol";

contract MockToken is IERC20Minimal {
    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balances[msg.sender] >= amount, "insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowances[from][msg.sender];
        require(allowed >= amount, "insufficient allowance");
        require(balances[from] >= amount, "insufficient balance");
        if (allowed != type(uint256).max) {
            allowances[from][msg.sender] = allowed - amount;
        }
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }
}

contract MockAavePool is IFlashLoanSimpleReceiver {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16
    ) external {
        MockToken(asset).mint(receiverAddress, amount);
        uint256 premium = amount / 2000;
        bool ok = IFlashLoanSimpleReceiver(receiverAddress).executeOperation(
            asset, amount, premium, msg.sender, params
        );
        require(ok, "executeOperation failed");
        MockToken(asset).transferFrom(receiverAddress, address(this), amount + premium);
    }

    function executeOperation(address, uint256, uint256, address, bytes calldata) external pure returns (bool) {
        revert("not a receiver");
    }
}

contract CallbackVault {
    address public lastRecipient;

    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external {
        require(tokens.length == 1 && amounts.length == 1, "single token only");
        lastRecipient = address(recipient);
        MockToken(address(tokens[0])).mint(address(recipient), amounts[0]);
        uint256[] memory fees = new uint256[](1);
        recipient.receiveFlashLoan(tokens, amounts, fees, userData);
    }
}

contract BatchSwapTarget {
    uint256 public hits;

    function batchSwap(
        IBalancerVault.SwapKind,
        IBalancerVault.BatchSwapStep[] memory,
        address[] memory,
        IBalancerVault.FundManagement memory,
        int256[] memory,
        uint256
    ) external payable returns (int256[] memory deltas) {
        hits += 1;
        deltas = new int256[](0);
    }
}

contract NoCallbackVault {
    function flashLoan(IFlashLoanRecipient, IERC20Minimal[] memory, uint256[] memory, bytes memory) external pure {
        // Malformed vault for boundary testing: returns without invoking receiveFlashLoan.
    }
}

contract RecorderTarget {
    uint256 public count;

    function record() external {
        count += 1;
    }
}

contract RevertingTarget {
    function fail() external pure {
        revert("route call failed");
    }
}

contract ArbExecutorAtomicTest {
    MockToken internal token;
    RecorderTarget internal recorder;
    RevertingTarget internal reverter;

    function _deployExecutor(address vault) internal returns (ArbExecutor) {
        bytes memory args1 = HuffDeployer.encode1(
                address(this), vault,
                address(0x1001), address(0x1002), address(0x1003), address(0x1004),
                address(0x1005), address(0x1006)
            );
        bytes memory args2 = HuffDeployer.encode2(
                address(0x1007), address(0x1008), address(0x1009), address(0x100a),
                address(0x100b), address(0x100c), address(0x100d), address(0x100e), address(0x100f)
            );
        address addr = HuffDeployer.deploy_with_args("ArbExecutor", bytes.concat(args1, args2));
        require(addr != address(0), "deploy failed");
        return ArbExecutor(payable(addr));
    }

    function _baseCalls(uint256 count) internal view returns (ArbExecutor.Call[] memory calls) {
        calls = new ArbExecutor.Call[](count);
        calls[0] = ArbExecutor.Call({
            target: address(recorder), value: 0, data: abi.encodeWithSelector(RecorderTarget.record.selector)
        });
        if (count > 1) {
            calls[1] = ArbExecutor.Call({
                target: address(reverter), value: 0, data: abi.encodeWithSelector(RevertingTarget.fail.selector)
            });
        }
    }

    function _packedRoute(ArbExecutor.Call[] memory calls) internal view returns (bytes memory) {
        (bytes memory packedRoute,) =
            ArbExecutorCodec.buildPackedRoute(address(token), 100, address(token), 0, block.timestamp + 1 days, _toCodecCalls(calls));
        return packedRoute;
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

    function _callExecute(ArbExecutor executor, ArbExecutor.Call[] memory calls)
        internal
        returns (bool ok, bytes memory data)
    {
        bytes memory packedRoute = _packedRoute(calls);
        return address(executor).call(abi.encodeWithSelector(ArbExecutor.executeArb.selector, packedRoute));
    }

    function _callExecuteDirect(ArbExecutor executor, ArbExecutor.Call[] memory calls)
        internal
        returns (bool ok, bytes memory data)
    {
        bytes memory packedRoute = _packedRoute(calls);
        return address(executor).call(abi.encodeWithSelector(ArbExecutor.executeArbDirect.selector, packedRoute));
    }

    function _deployExecutorWithAave(address vault, address aavePool) internal returns (ArbExecutor) {
        bytes memory args1 = HuffDeployer.encode1(
                address(this), vault,
                address(0x1001), address(0x1002), address(0x1003), address(0x1004),
                aavePool, address(0x1006)
            );
        bytes memory args2 = HuffDeployer.encode2(
                address(0x1007), address(0x1008), address(0x1009), address(0x100a),
                address(0x100b), address(0x100c), address(0x100d), address(0x100e), address(0x100f)
            );
        address addr = HuffDeployer.deploy_with_args("ArbExecutor", bytes.concat(args1, args2));
        require(addr != address(0), "deploy failed");
        return ArbExecutor(payable(addr));
    }

    function _callExecuteAave(ArbExecutor executor, ArbExecutor.Call[] memory calls)
        internal
        returns (bool ok, bytes memory data)
    {
        bytes memory packedRoute = _packedRoute(calls);
        return address(executor).call(abi.encodeWithSelector(ArbExecutor.executeArbWithAave.selector, packedRoute));
    }

    function testExecuteArbRevertsIfFlashLoanCallbackNeverCompletes() public {
        token = new MockToken();
        recorder = new RecorderTarget();
        reverter = new RevertingTarget();
        ArbExecutor executor = _deployExecutor(address(new NoCallbackVault()));
        ArbExecutor.Call[] memory calls = _baseCalls(1);

        (bool ok,) = _callExecute(executor, calls);

        require(!ok, "executeArb must fail closed if flash loan callback does not complete");
        require(recorder.count() == 0, "route calls must not execute without callback");
    }

    function testRouteCallFailureRollsBackEarlierCalls() public {
        token = new MockToken();
        recorder = new RecorderTarget();
        reverter = new RevertingTarget();
        ArbExecutor executor = _deployExecutor(address(new CallbackVault()));
        ArbExecutor.Call[] memory calls = _baseCalls(2);

        (bool ok,) = _callExecute(executor, calls);

        require(!ok, "executeArb must revert when any embedded route call fails");
        require(recorder.count() == 0, "successful earlier route calls must roll back on later failure");
        require(token.balances(address(executor)) == 0, "executor flash-token balance must roll back");
    }

    function testExecuteArbDirectRunsBatchSwapCallWithoutFlashLoan() public {
        token = new MockToken();
        recorder = new RecorderTarget();
        BatchSwapTarget batchTarget = new BatchSwapTarget();
        ArbExecutor executor = _deployExecutor(address(batchTarget));

        // Full ABI encoding so the Solidity decoder reaches the function body.
        IBalancerVault.BatchSwapStep[] memory swaps;
        address[] memory assets;
        IBalancerVault.FundManagement memory funds;
        int256[] memory limits;
        ArbExecutor.Call[] memory calls = new ArbExecutor.Call[](1);
        calls[0] = ArbExecutor.Call({
            target: address(batchTarget),
            value: 0,
            data: abi.encodeWithSelector(
                IBalancerVault.batchSwap.selector,
                IBalancerVault.SwapKind.GIVEN_IN,
                swaps,
                assets,
                funds,
                limits,
                block.timestamp + 1
            )
        });

        (bool ok, bytes memory data) = _callExecuteDirect(executor, calls);

        require(ok, string(data));
        require(batchTarget.hits() == 1, "batchSwap route call should execute once");
    }

    function testFlashLoanCallbackRejectsBalancerVaultRouteCalls() public {
        token = new MockToken();
        CallbackVault vault = new CallbackVault();
        ArbExecutor executor = _deployExecutor(address(vault));
        ArbExecutor.Call[] memory calls = new ArbExecutor.Call[](1);
        calls[0] = ArbExecutor.Call({
            target: address(vault),
            value: 0,
            data: abi.encodeWithSelector(RecorderTarget.record.selector)
        });

        (bool ok,) = _callExecute(executor, calls);

        require(!ok, "executeArb must reject Balancer Vault calls inside a Vault flash-loan callback");
    }

    function testExecuteArbWithAaveApprovesPoolForRepayment() public {
        token = new MockToken();
        recorder = new RecorderTarget();
        MockAavePool aavePool = new MockAavePool();
        ArbExecutor executor = _deployExecutorWithAave(address(new CallbackVault()), address(aavePool));
        ArbExecutor.Call[] memory calls = _baseCalls(1);

        token.mint(address(executor), 1);
        (bool ok, bytes memory data) = _callExecuteAave(executor, calls);

        require(ok, string(data));
        require(recorder.count() == 1, "route call should execute inside Aave callback");
        require(token.balances(address(executor)) == 1, "profit token dust should remain");
        require(token.balances(address(aavePool)) == 100, "pool should pull repayment + premium");
        require(token.allowances(address(executor), address(aavePool)) > 0, "executor should approve pool");
    }

    function testExecuteOperationRevertsIfNotAavePool() public {
        token = new MockToken();
        recorder = new RecorderTarget();
        MockAavePool aavePool = new MockAavePool();
        ArbExecutor executor = _deployExecutorWithAave(address(new CallbackVault()), address(aavePool));

        (bool ok, bytes memory data) = address(executor).call(
            abi.encodeWithSelector(
                ArbExecutor.executeOperation.selector, address(token), uint256(100), uint256(0), address(executor), bytes("")
            )
        );

        require(!ok, "direct executeOperation must revert");
        bytes4 selector;
        assembly {
            selector := mload(add(data, 32))
        }
        require(selector == ArbExecutor.FlashLoanOnly.selector, "expected FlashLoanOnly");
    }

    function testSuccessfulRouteCompletesThroughFlashLoanCallback() public {
        token = new MockToken();
        recorder = new RecorderTarget();
        reverter = new RevertingTarget();
        CallbackVault vault = new CallbackVault();
        ArbExecutor executor = _deployExecutor(address(vault));
        ArbExecutor.Call[] memory calls = _baseCalls(1);

        (bool ok, bytes memory data) = _callExecute(executor, calls);

        require(ok, string(data));
        require(data.length == 32, "executeArb should return one ABI word");
        require(abi.decode(data, (uint256)) == 0, "mock route should report zero realized profit");
        require(recorder.count() == 1, "successful route call should execute once");
        require(token.balances(address(executor)) == 0, "flash amount should be repaid");
        require(token.balances(address(vault)) == 100, "vault should receive repayment");
    }
}
