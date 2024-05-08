// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

abstract contract IConstants {

    // Launch configs
    uint256 constant INITIAL_LAUNCH_SUPPLY = 10;
    uint256 constant INITIAL_LAUNCH_PRICE = 1 ether;

    // General configs
    uint256 constant TRANSFER_DELAY = 7 days;
    uint96 constant ROYALTY_BPS = 250;

    // Floor pool configs
    uint128 constant FLOOR_SPOT_PRICE = 1 ether;
    uint256 constant FLOOR_INITIAL_TOKEN_BALANCE = INITIAL_LAUNCH_SUPPLY * INITIAL_LAUNCH_PRICE;

    // Anchor pool configs
    uint128 constant ANCHOR_DELTA = 1 ether;
    uint128 constant ANCHOR_SPOT_PRICE = 2 ether;
    uint256 constant ANCHOR_INITIAL_SUPPLY = 5;

    // Trade pool configs
    uint128 constant TRADE_INITIAL_SUPPLY = 35;
    uint128 constant TRADE_DELTA = TRADE_INITIAL_SUPPLY; // Represents NFT amount
    uint128 constant TRADE_SPOT_PRICE = ANCHOR_SPOT_PRICE * TRADE_DELTA * 2; // Starts at 2x the price of the anchor

    // Collection configs
    uint256 constant TOTAL_SUPPLY = INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + TRADE_INITIAL_SUPPLY;

    // Fee configs
    uint256 constant FLOOR_DENOM = 3;
    uint256 constant ANCHOR_DENOM = 3;
    uint256 constant TRADE_DENOM = 3;

    // Loan configs
    uint256 constant LOAN_NUM = 95; // 95% ltv relative to floor
    uint256 constant LOAN_DENOM = 100;
    uint256 constant MAX_LOAN_DURATION = 90 days;
    uint256 constant INTEREST_NUM = 2; // Approx 0.02% a day in interest
    uint256 constant INTEREST_DENOM = 864000000; 
    uint256 constant LOAN_GRACE_PERIOD = 1 days;

}