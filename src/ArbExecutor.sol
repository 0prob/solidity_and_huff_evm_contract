// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface IERC20Minimal {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface IFlashLoanRecipient {
    function receiveFlashLoan(
        IERC20Minimal[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;
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

abstract contract ArbExecutor is IFlashLoanRecipient {
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

    function owner() external view virtual returns (address);
    function aavePool() external view virtual returns (address);
    function approveIfNeeded(address token, address spender, uint256 amount) external virtual;
    function preApprove(address token, address spender) external virtual;
    function transferAll(address token, address to) external virtual;
    function executeArb(bytes calldata packedRoute) external virtual;
    function executeArbWithAave(bytes calldata packedRoute) external virtual;
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
