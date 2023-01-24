// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13 <0.9.0;

import { ISablierV2Lockup } from "src/interfaces/ISablierV2Lockup.sol";

import { Linear_Test } from "test/unit/lockup/linear/Linear.t.sol";
import { GetWithdrawnAmount_Test } from "test/unit/lockup/shared/get-withdrawn-amount/getWithdrawnAmount.t.sol";

contract GetWithdrawnAmount_Linear_Test is Linear_Test, GetWithdrawnAmount_Test {
    function setUp() public virtual override(Linear_Test, GetWithdrawnAmount_Test) {
        GetWithdrawnAmount_Test.setUp();
        lockup = ISablierV2Lockup(linear);
    }
}