// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

/// @dev Balancer V2 IFlashLoanRecipient — abis/balancer-v2/IFlashLoanRecipient.sol
///      (upstream: balancer/balancer-v2-monorepo pkg/interfaces/contracts/vault/IFlashLoanRecipient.sol)
interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
}

/// @dev Aave V3 IFlashLoanSimpleReceiver — abis/aave-v3/IFlashLoanSimpleReceiver.sol
///      (upstream: aave/aave-v3-core contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol)
interface IFlashLoanSimpleReceiver {
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

/// @dev Aave V3 IPool flash-loan entry — abis/aave-v3/IPool.sol
///      (upstream: aave/aave-v3-core contracts/interfaces/IPool.sol)
interface IAaveV3Pool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

/// @dev Balancer V2 IVault swap + flash loan surface — abis/balancer-v2/IVault.sol
///      (upstream: balancer/balancer-v2-monorepo pkg/interfaces/contracts/vault/IVault.sol)
interface IBalancerVault {
    enum SwapKind {
        GIVEN_IN,
        GIVEN_OUT
    }

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    function flashLoan(
        IFlashLoanRecipient recipient,
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;

    function batchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds,
        int256[] memory limits,
        uint256 deadline
    ) external payable returns (int256[] memory assetDeltas);
}

library ArbExecutorCodec {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function packExecutorCalls(Call[] memory calls) internal pure returns (bytes memory out) {
        out = abi.encodePacked(bytes32(uint256(calls.length)));
        for (uint256 i = 0; i < calls.length; ++i) {
            out = abi.encodePacked(
                out,
                bytes32(uint256(uint160(calls[i].target))),
                bytes32(calls[i].value),
                bytes32(uint256(calls[i].data.length)),
                calls[i].data
            );
        }
    }

    function computeRouteHash(bytes memory packedCalls) internal pure returns (bytes32) {
        return keccak256(packedCalls);
    }

    function buildPackedRoute(
        address flashToken,
        uint256 flashAmount,
        address profitToken,
        uint256 minProfit,
        uint256 deadline,
        Call[] memory calls
    ) internal pure returns (bytes memory payload, bytes32 routeHash) {
        bytes memory packedCalls = packExecutorCalls(calls);
        routeHash = keccak256(packedCalls);
        payload = abi.encodePacked(
            bytes32(uint256(uint160(flashToken))),
            bytes32(flashAmount),
            bytes32(uint256(uint160(profitToken))),
            bytes32(minProfit),
            bytes32(deadline),
            routeHash,
            packedCalls
        );
    }
}

abstract contract ArbExecutor is IFlashLoanRecipient, IFlashLoanSimpleReceiver {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    struct FlashParams {
        address profitToken;
        uint256 minProfit;
        uint256 deadline;
        bytes32 routeHash;
        Call[] calls;
    }

    error Unauthorized();
    error DeadlineExpired();
    error EmptyRoute();
    error TooManyCalls();
    error FlashLoanRequired();
    error InvalidRouteHash();
    error FlashLoanOnly();
    error InvalidFlashLoanContext();
    error CallbackOnly();
    error InvalidCallbackSource();
    error UnsupportedProtocol(uint8 protocolId);
    error InvalidPoolCaller(address expected, address actual);
    error ExternalCallFailed(uint256 index, address target, bytes reason);
    error InsufficientProfit(uint256 finalBalance, uint256 requiredBalance);
    error TransferFailed(address token, address to, uint256 amount);
    error ApproveFailed(address token, address spender);
    error ZeroAddress();
    error BalancerVaultReentrancy();

    function owner() external view virtual returns (address);
    function aavePool() external view virtual returns (address);
    function approveIfNeeded(address token, address spender, uint256 amount) external virtual;
    function preApprove(address token, address spender) external virtual;
    function transferAll(address token, address to) external virtual;
    function executeArb(bytes calldata packedRoute) external virtual returns (uint256 realizedProfit);
    /// @notice Run a route without a flash loan. Use for Balancer `batchSwap` / flash-swap routes
    ///         (the Vault is non-reentrant and cannot be called from `receiveFlashLoan`).
    function executeArbDirect(bytes calldata packedRoute) external virtual returns (uint256 realizedProfit);
    function executeArbWithAave(bytes calldata packedRoute) external virtual returns (uint256 realizedProfit);
    /// @notice Flash via DODO V2 `flashLoan`. `flashToken` field is the DODO pool; flash asset is `profitToken`.
    function executeArbWithDodo(bytes calldata packedRoute) external virtual returns (uint256 realizedProfit);
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        virtual
        returns (bool);

    function packExecutorCalls(Call[] memory calls) public pure returns (bytes memory out) {
        ArbExecutorCodec.Call[] memory codecCalls = new ArbExecutorCodec.Call[](calls.length);
        for (uint256 i = 0; i < calls.length; ++i) {
            codecCalls[i] = ArbExecutorCodec.Call({target: calls[i].target, value: calls[i].value, data: calls[i].data});
        }
        out = ArbExecutorCodec.packExecutorCalls(codecCalls);
    }

    function computeRouteHash(bytes memory packedCalls) public pure returns (bytes32) {
        return ArbExecutorCodec.computeRouteHash(packedCalls);
    }

    function buildPackedRoute(
        address flashToken,
        uint256 flashAmount,
        address profitToken,
        uint256 minProfit,
        uint256 deadline,
        Call[] memory calls
    ) public pure returns (bytes memory payload, bytes32 routeHash) {
        bytes memory packedCalls = packExecutorCalls(calls);
        routeHash = keccak256(packedCalls);
        payload = abi.encodePacked(
            bytes32(uint256(uint160(flashToken))),
            bytes32(flashAmount),
            bytes32(uint256(uint160(profitToken))),
            bytes32(minProfit),
            bytes32(deadline),
            routeHash,
            packedCalls
        );
    }
}
