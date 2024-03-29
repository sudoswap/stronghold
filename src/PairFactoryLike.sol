// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ICurve} from "lssvm2/bonding-curves/ICurve.sol";
import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

interface PairFactoryLike {
    function isValidPair(address pairAddress) external view returns (bool);

    struct CreateERC721ERC20PairParams {
        ERC20 token;
        IERC721 nft;
        ICurve bondingCurve;
        address payable assetRecipient;
        LSSVMPair.PoolType poolType;
        uint128 delta;
        uint96 fee;
        uint128 spotPrice;
        address propertyChecker;
        uint256[] initialNFTIDs;
        uint256 initialTokenBalance;
        address hookAddress;
        address referralAddress;
    }

    function createPairERC721ERC20(CreateERC721ERC20PairParams calldata params) external returns (LSSVMPair pair);
}
