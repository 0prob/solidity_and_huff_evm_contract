// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface Vm {
    function ffi(string[] calldata data) external returns (bytes memory);
    function etch(address target, bytes calldata newCode) external;
}

library HuffDeployer {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function bytecode() internal returns (bytes memory) {
        string[] memory constructorCmd = new string[](3);
        constructorCmd[0] = "bash";
        constructorCmd[1] = "-lc";
        constructorCmd[2] =
            "huffc /home/x/arb/sol/src/ArbExecutor.huff CONSTRUCTOR --evm-version shanghai | xxd -p -c 1000000 | tr -d '\\n'";
        return _hexToBytes(vm.ffi(constructorCmd));
    }

    function runtimeBytecode() internal returns (bytes memory) {
        string[] memory runtimeCmd = new string[](3);
        runtimeCmd[0] = "bash";
        runtimeCmd[1] = "-lc";
        runtimeCmd[2] =
            "huffc /home/x/arb/sol/src/ArbExecutor.huff MAIN --evm-version shanghai | xxd -p -c 1000000 | tr -d '\\n'";
        return _hexToBytes(vm.ffi(runtimeCmd));
    }

    function deploy_with_args(string memory fileName, bytes memory args) internal returns (address) {
        bytes memory initCode = abi.encodePacked(bytecode(), args);
        address deployed;
        assembly ("memory-safe") {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "deploy failed");
        vm.etch(deployed, runtimeBytecode());
        return deployed;
    }

    function deploy_with_args_as(string memory fileName, bytes memory args, address deployer)
        internal
        returns (address)
    {
        deployer;
        return deploy_with_args(fileName, args);
    }

    function _hexToBytes(bytes memory hexData) private pure returns (bytes memory out) {
        uint256 start = 0;
        if (hexData.length >= 2 && hexData[0] == bytes1("0") && (hexData[1] == bytes1("x") || hexData[1] == bytes1("X"))) {
            start = 2;
        }
        uint256 end = hexData.length;
        while (end > start) {
            bytes1 ch = hexData[end - 1];
            if (ch != 0x0a && ch != 0x0d && ch != 0x20 && ch != 0x09) break;
            --end;
        }
        require((end - start) % 2 == 0, "invalid hex");
        out = new bytes((end - start) / 2);
        for (uint256 i = 0; i < out.length; ++i) {
            out[i] = bytes1(
                (_fromHexChar(uint8(hexData[start + 2 * i])) << 4) | _fromHexChar(uint8(hexData[start + 2 * i + 1]))
            );
        }
    }

    function _fromHexChar(uint8 c) private pure returns (uint8) {
        if (c >= 48 && c <= 57) return c - 48;
        if (c >= 97 && c <= 102) return c - 87;
        if (c >= 65 && c <= 70) return c - 55;
        revert("invalid hex");
    }

    function encode1(address a0, address a1, address a2, address a3, address a4, address a5, address a6, address a7)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(a0, a1, a2, a3, a4, a5, a6, a7);
    }

    function encode2(address a0, address a1, address a2, address a3, address a4, address a5, address a6, address a7, address a8)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(a0, a1, a2, a3, a4, a5, a6, a7, a8);
    }
}
