// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { TBillToken } from "./TBillToken.sol";

contract TBillTokenV2 is TBillToken {
    string public complianceUri;

    event ComplianceUriUpdated(string oldUri, string newUri);

    function setComplianceUri(string calldata newUri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emit ComplianceUriUpdated(complianceUri, newUri);
        complianceUri = newUri;
    }

    function version() public pure override returns (string memory) {
        return "2.0.0";
    }
}
