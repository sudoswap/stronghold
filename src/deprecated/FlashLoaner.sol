// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/*
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Owned} from "solmate/auth/Owned.sol";

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";

import {Stronghold} from "./Stronghold.sol";

contract FlashLoaner is ERC20, Owned {

    error TooLow();

    ERC20 immutable quoteToken;
    Stronghold immutable stronghold;
    LSSVMPair immutable tradePool;

    constructor(ERC20 _quoteToken, Stronghold _stronghold, LSSVMPair _tradePool) ERC20("Flash YES", "fYES", 18) Owned (msg.sender){
        quoteToken = _quoteToken;
        stronghold = _stronghold;
        tradePool = _tradePool;
    }

    function withdraw(uint256 amount, address a) external onlyOwner {
        ERC20(a).transfer(msg.sender, amount);
    }

    function leverage(uint256[] calldata idsToSwapAndLend, uint256 marginAmount, uint256 loanDurationInSeconds) external {
        
        // Calculate loan amount and swap quote
        // If the loan amount + posted margin amount is not enough, revert
        uint256 numNFTs = idsToSwapAndLend.length;
        uint256 loanAmount = stronghold.getLoanAmount(numNFTs);
        (,,, uint256 quoteAmount,,) = tradePool.getBuyNFTQuote(1, numNFTs);
        if (loanAmount + marginAmount < quoteAmount) {
            revert TooLow();
        }

        // If the loan + margin is enough, transfer the margin amount in 
        // approve and swap for the NFTs
        quoteToken.transferFrom(msg.sender, address(this), marginAmount);
        ERC20(quoteToken).approve(address(tradePool), quoteAmount);
        tradePool.swapTokenForSpecificNFTs(idsToSwapAndLend, quoteAmount, address(this), false, address(0));
        ERC20(quoteToken).approve(address(tradePool), 0);

        // Approve and open a loan for the caller
        IERC721(address(stronghold)).setApprovalForAll(address(stronghold), true);
        stronghold.borrow(idsToSwapAndLend, loanDurationInSeconds, msg.sender);
        IERC721(address(stronghold)).setApprovalForAll(address(stronghold), false);
    }

}
*/