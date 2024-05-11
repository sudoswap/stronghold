// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */

pragma solidity ^0.8.0;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {LSSVMPair} from "lssvm2/LSSVMPair.sol";

import {StrongholdETH} from "./StrongholdETH.sol";

contract FlashLoanerETH is Owned {

    using SafeTransferLib for address payable;

    error NotEnoughTokensSent();

    StrongholdETH immutable stronghold;
    LSSVMPair immutable tradePool;

    constructor(StrongholdETH _stronghold, LSSVMPair _tradePool) Owned (msg.sender){
        stronghold = _stronghold;
        tradePool = _tradePool;
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        payable(msg.sender).safeTransferETH(amount);
    }

    function leverage(uint256[] calldata idsToSwapAndLend, uint256 loanDurationInSeconds) payable external {
        
        // Calculate loan amount and swap quote
        // If the loan amount + posted margin amount is not enough, revert
        uint256 numNFTs = idsToSwapAndLend.length;
        uint256 loanAmount = stronghold.getLoanAmount(numNFTs);
        (,,, uint256 quoteAmount,,) = tradePool.getBuyNFTQuote(1, numNFTs);
        if (loanAmount + msg.value < quoteAmount) {
            revert NotEnoughTokensSent();
        }

        // If the loan + margin is enough, transfer the margin amount in 
        // approve and swap for the NFTs
        tradePool.swapTokenForSpecificNFTs{value: quoteAmount}(idsToSwapAndLend, quoteAmount, address(this), false, address(0));

        // Approve and open a loan for the caller
        IERC721(address(stronghold)).setApprovalForAll(address(stronghold), true);
        stronghold.borrow(idsToSwapAndLend, loanDurationInSeconds, msg.sender);
        IERC721(address(stronghold)).setApprovalForAll(address(stronghold), false);
    }

}