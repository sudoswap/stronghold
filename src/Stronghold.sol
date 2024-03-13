// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {ICurve} from "lssvm2/bonding-curves/ICurve.sol";
import {IPairHooks} from "lssvm2/hooks/IPairHooks.sol";

import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import {IERC2981} from "openzeppelin-contracts/contracts/interfaces/IERC2981.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC721Minimal} from "./ERC721Minimal.sol";
import {PairFactoryLike} from "./PairFactoryLike.sol";

// Is also IPairHooks
contract Stronghold is ERC721Minimal, ERC2981, IPairHooks {

    /*//////////////////////////////////////////////////////////////
                  Struct
    //////////////////////////////////////////////////////////////*/

    struct OwnerOfWithData {
        address owner;
        uint96 lastTransferTimestamp;
    }

    /*//////////////////////////////////////////////////////////////
                       Error
    //////////////////////////////////////////////////////////////*/

    error Cooldown();
    error NoZero();
    error WrongFrom();
    error Unauth();

    /*//////////////////////////////////////////////////////////////
                    Constants x Immutables
    //////////////////////////////////////////////////////////////*/

    uint256 constant TRANSFER_DELAY = 7 days;
    uint96 constant ROYALTY_BPS = 250;

    uint128 constant ANCHOR_DELTA = 1 ether;
    uint128 constant ANCHOR_SPOT_PRICE = 100 ether;

    ICurve immutable LINEAR_CURVE;
    ICurve immutable XYK_CURVE;
    address immutable QUOTE_TOKEN;
    address immutable SUDO_FACTORY;

    /*//////////////////////////////////////////////////////////////
                       State
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => OwnerOfWithData) public ownerOfWithData;

    address public floorPool;
    address public tradePool;
    address public anchorPool;

    /*//////////////////////////////////////////////////////////////
                       Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        ICurve _LINEAR_CURVE,
        ICurve _XYK_CURVE,
        address _QUOTE_TOKEN,
        address _SUDO_FACTORY
    ) ERC721Minimal("Stronghold", "HODL") {

        // Init immutable curve variables
        LINEAR_CURVE = _LINEAR_CURVE;
        XYK_CURVE = _XYK_CURVE;
        QUOTE_TOKEN = _QUOTE_TOKEN;
        SUDO_FACTORY = _SUDO_FACTORY;

        // Init royalty
        _setDefaultRoyalty(address(this), ROYALTY_BPS);
    }

    /* 
    
    Initial mint / claim
    - users (need to check if on list) deposit $YES
    - users claim their NFTs

    Initial launch parameters:
    - 1000 (initial claim)
    - 500 (linear)
    - 3500 (trading)

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

     /*//////////////////////////////////////////////////////////////
                     Pair Hooks
    //////////////////////////////////////////////////////////////*/

    function afterSwapNFTInPair(
        uint256 _tokensOut,
        uint256 _tokensOutProtocolFee,
        uint256 _tokensOutRoyalty,
        uint256[] calldata _nftsIn
    ) external {}

    function afterSwapNFTOutPair(
        uint256 _tokensIn,
        uint256 _tokensInProtocolFee,
        uint256 _tokensInRoyalty,
        uint256[] calldata _nftsOut
    ) external {}

    // Everything else is a no-op
    function afterNewPair() external {}
    function afterDeltaUpdate(uint128 _oldDelta, uint128 _newDelta) external {}
    function afterSpotPriceUpdate(uint128 _oldSpotPrice, uint128 _newSpotPrice) external {}
    function afterFeeUpdate(uint96 _oldFee, uint96 _newFee) external {}
    function afterNFTWithdrawal(uint256[] calldata _nftsOut) external {}
    function afterTokenWithdrawal(uint256 _tokensOut) external {}
    function syncForPair(address pairAddress, uint256 _tokensIn, uint256[] calldata _nftsIn) external {}

    /*//////////////////////////////////////////////////////////////
                      Mint x Pool 
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256[] memory ids) internal virtual {
        uint256 numIds = ids.length;
        unchecked {
            _balanceOf[to] += numIds;
        }
        for (uint256 i; i < numIds;) {
            uint256 id = ids[i];
            ownerOfWithData[id].owner = to;
            emit Transfer(address(0), to, id);
            unchecked {
                ++i;
            }
        }
    }

    function initAnchorPool() public {
        require(anchorPool == address(0));
        uint256[] memory empty = new uint256[](0);
        anchorPool = address(PairFactoryLike(SUDO_FACTORY).createPairERC721ERC20(PairFactoryLike.CreateERC721ERC20PairParams({
            token: ERC20(QUOTE_TOKEN),
            nft: IERC721(address(this)),
            bondingCurve: LINEAR_CURVE,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: ANCHOR_DELTA,
            fee: 0,
            spotPrice: ANCHOR_SPOT_PRICE,
            propertyChecker: address(0),
            initialNFTIDs: empty,
            initialTokenBalance: 0
        })));

        // TODO: mint to anchor pool
    }

    function initFloorPool() public {
        require(floorPool == address(0));
    }
    
    function initTradePool() public {
        require(tradePool == address(0));
    }

    /*//////////////////////////////////////////////////////////////
                   IERC721 Compliance
    //////////////////////////////////////////////////////////////*/

    // TODO
    function tokenURI(uint256 id) public view override returns (string memory) {
        return '';
    }

    // Overrides both ERC721 and ERC2981
    function supportsInterface(bytes4 interfaceId) public pure override(ERC2981, ERC721Minimal) returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == type(IERC2981).interfaceId // ERC165 interface for IERC2981
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function ownerOf(uint256 id) public view override returns (address owner) {
        owner = ownerOfWithData[id].owner;
    }

    function transferFrom(address from, address to, uint256 id) public override {
        if (from != ownerOf(id)) {
            revert WrongFrom();
        }
        if (to == address(0)) {
            revert NoZero();
        }
        if (msg.sender != from && !isApprovedForAll[from][msg.sender] && msg.sender != getApproved[id]) {
            revert Unauth();
        }

        // Underflow of the sender's balance is impossible because we check for
        // ownership above and the recipient's balance can't realistically overflow.
        unchecked {
            _balanceOf[from]--;
            _balanceOf[to]++;
        }
        delete getApproved[id];
        uint256 timestamp = block.timestamp;

        // Always allow transfer if one of the recipients is a sudo pool
        bool isPairOrSelf;
        try PairFactoryLike(SUDO_FACTORY).isValidPair(from) returns (bool result) {
            isPairOrSelf = result;
        } catch {}
        if (!isPairOrSelf) {
            try PairFactoryLike(SUDO_FACTORY).isValidPair(to) returns (bool result) {
                isPairOrSelf = result;
            } catch {}
        }

        // Or if it is coming to or from this address
        if (to == address(this) || from == address(this)) {
            isPairOrSelf = true;
        }

        // If either to or from a pool, always allow it
        if (isPairOrSelf) {
            ownerOfWithData[id].owner = to;
        }
        // If one of the two recipients is not a sudo pool
        else {
            // Check if earlier than allowed, if so, then revert
            if (timestamp < ownerOfWithData[id].lastTransferTimestamp) {
                revert Cooldown();
            }
            // If it is past the cooldown, then we set a new cooldown, and let the transfer go through
            ownerOfWithData[id] = OwnerOfWithData({owner: to, lastTransferTimestamp: uint96(timestamp + TRANSFER_DELAY)});
        }
        emit Transfer(from, to, id);
    }
}