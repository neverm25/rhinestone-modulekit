// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { AccountInstance } from "../RhinestoneModuleKit.sol";
import { ValidatorLib } from "kernel/utils/ValidationTypeLib.sol";
import { ValidationType, ValidationMode, ValidationId } from "kernel/types/Types.sol";
import "kernel/types/Constants.sol";
import { ENTRYPOINT_ADDR } from "../predeploy/EntryPoint.sol";
import { IEntryPoint } from "kernel/interfaces/IEntryPoint.sol";
import { IERC7579Account } from "erc7579/interfaces/IERC7579Account.sol";
import { MockFallback } from "kernel/mock/MockFallback.sol";
import { HelperBase } from "./HelperBase.sol";
import { Kernel } from "kernel/Kernel.sol";
import { etch } from "../utils/Vm.sol";
import { IValidator } from "kernel/interfaces/IERC7579Modules.sol";

contract SetSelector is Kernel {
    constructor(IEntryPoint _entrypoint) Kernel(_entrypoint) { }

    function setSelector(ValidationId vId, bytes4 selector, bool allowed) external {
        _setSelector(vId, selector, allowed);
    }
}

contract KernelHelpers is HelperBase {
    function getNonce(
        AccountInstance memory instance,
        bytes memory callData,
        address txValidator
    )
        public
        virtual
        override
        returns (uint256 nonce)
    {
        ValidationType vType;
        if (txValidator == address(instance.defaultValidator)) {
            vType = VALIDATION_TYPE_ROOT;
        } else {
            enableValidator(instance, callData, txValidator);
            vType = VALIDATION_TYPE_VALIDATOR;
        }
        nonce = encodeNonce(vType, false, instance.account, txValidator);
    }

    function encodeNonce(
        ValidationType vType,
        bool enable,
        address account,
        address validator
    )
        public
        view
        returns (uint256 nonce)
    {
        uint192 nonceKey = 0;
        if (vType == VALIDATION_TYPE_ROOT) {
            nonceKey = 0;
        } else if (vType == VALIDATION_TYPE_VALIDATOR) {
            ValidationMode mode = VALIDATION_MODE_DEFAULT;
            if (enable) {
                mode = VALIDATION_MODE_ENABLE;
            }
            nonceKey = ValidatorLib.encodeAsNonceKey(
                ValidationMode.unwrap(mode),
                ValidationType.unwrap(vType),
                bytes20(validator),
                0 // parallel key
            );
        } else {
            revert("Invalid validation type");
        }
        return IEntryPoint(ENTRYPOINT_ADDR).getNonce(account, nonceKey);
    }

    function enableValidator(
        AccountInstance memory instance,
        bytes memory callData,
        address txValidator
    )
        internal
    {
        ValidationId vId = ValidatorLib.validatorToIdentifier(IValidator(txValidator));
        bytes4 selector;
        assembly {
            selector := mload(add(callData, 32))
        }
        bool isAllowedSelector = Kernel(payable(instance.account)).isAllowedSelector(vId, selector);
        if (!isAllowedSelector) {
            bytes memory accountCode = instance.account.code;
            address _setSelector = address(new SetSelector(IEntryPoint(ENTRYPOINT_ADDR)));
            etch(instance.account, _setSelector.code);
            SetSelector(payable(instance.account)).setSelector(vId, selector, true);
            etch(instance.account, accountCode);
        }
    }

    /**
     * @dev
     * https://github.com/zerodevapp/kernel/blob/a807c8ec354a77ebb7cdb73c5be9dd315cda0df2/src/Kernel.sol#L311-L321
     */
    function getInstallValidatorData(
        address, /* account */
        address, /* module */
        bytes memory initData
    )
        public
        pure
        virtual
        override
        returns (bytes memory data)
    {
        data = abi.encodePacked(address(0), abi.encode(initData, abi.encodePacked("")));
    }

    /**
     * @dev
     * https://github.com/zerodevapp/kernel/blob/a807c8ec354a77ebb7cdb73c5be9dd315cda0df2/src/Kernel.sol#L324-L334
     */
    function getInstallExecutorData(
        address, /* account */
        address, /* module */
        bytes memory initData
    )
        public
        pure
        virtual
        override
        returns (bytes memory data)
    {
        data = abi.encodePacked(address(0), abi.encode(initData, abi.encodePacked("")));
    }

    /**
     * @dev
     * https://github.com/zerodevapp/kernel/blob/a807c8ec354a77ebb7cdb73c5be9dd315cda0df2/src/Kernel.sol#L336-L345
     */
    function getInstallFallbackData(
        address, /* account */
        address, /* module */
        bytes memory initData
    )
        public
        pure
        virtual
        override
        returns (bytes memory data)
    {
        data = abi.encodePacked(
            MockFallback.fallbackFunction.selector,
            address(0),
            abi.encode(initData, abi.encodePacked(""))
        );
    }

    /**
     * @dev
     * https://github.com/zerodevapp/kernel/blob/a807c8ec354a77ebb7cdb73c5be9dd315cda0df2/src/Kernel.sol#L402-L403
     */
    function getUninstallFallbackData(
        address, /* account */
        address, /* module */
        bytes memory deinitData
    )
        public
        pure
        virtual
        override
        returns (bytes memory data)
    {
        data = abi.encodePacked(MockFallback.fallbackFunction.selector, deinitData);
    }

    function isModuleInstalled(
        AccountInstance memory instance,
        uint256 moduleTypeId,
        address module
    )
        public
        view
        virtual
        override
        returns (bool)
    {
        if (moduleTypeId == MODULE_TYPE_HOOK) {
            return true;
        }
        bytes memory data;

        return isModuleInstalled(instance, moduleTypeId, module, data);
    }

    function isModuleInstalled(
        AccountInstance memory instance,
        uint256 moduleTypeId,
        address module,
        bytes memory data
    )
        public
        view
        virtual
        override
        returns (bool)
    {
        if (moduleTypeId == MODULE_TYPE_HOOK) {
            return true;
        }

        return IERC7579Account(instance.account).isModuleInstalled(moduleTypeId, module, data);
    }
}