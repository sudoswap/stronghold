// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

contract Stronghold {

    constructor() {
    }

    /* 
    
    Initial mint / claim
    - users (need to check if on list) deposit $YES
    - users claim their NFTs

    Initialize pools
    - create floor pool
    - create anchor pool
    - create trading pool

    Rebalance (on fees accrued)
    - recalculate RFV, move floor pool up
    - move anchor pool up (?)
    - deepen liquidity on the trading pool

    Loan
    - up to 7 days (?)
    - deposit NFT, get out $YES (below RFV)
    - needs to repay within 7 days, or anyone can liquidate (NFT goes back into either anchor or xyk pool), rfv is updated

    Margin
    - same as loan, except it optimistically fronts the $YES first, takes $YES from the caller, then buys an NFT from a pool
    - turns into the same loan
    - each address can have 1 loan open at a time to simplify things

    Bond (?)
    - have some amount of NFTs in reserve, look into ETH<>NFT pairings later (maybe even a sibling collection or smth)

    */
}