// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract RevertingRewardsDistributor {
    function distributeSupplierReward(address, address) external pure {
        revert("RD_FAIL");
    }

    function distributeBorrowerReward(address, address) external pure {
        revert("RD_FAIL");
    }
}