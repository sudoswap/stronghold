// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */

pragma solidity ^0.8.0;

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {LSSVMPairETH} from "lssvm2/LSSVMPairETH.sol";
import {LSSVMPairFactory} from "lssvm2/LSSVMPairFactory.sol";
import {ICurve} from "lssvm2/bonding-curves/ICurve.sol";
import {IPairHooks} from "lssvm2/hooks/IPairHooks.sol";

import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solmate/utils/ReentrancyGuard.sol";

import {ERC721Minimal} from "./ERC721Minimal.sol";
import {PairFactoryLike} from "./PairFactoryLike.sol";
import {IConstants} from "./IConstants.sol";

contract StrongholdETH is ERC721Minimal, ERC2981, IPairHooks, IConstants, ReentrancyGuard {

    using SafeTransferLib for address payable;

    /*//////////////////////////////////////////////////////////////
                  Structs
    //////////////////////////////////////////////////////////////*/

    struct OwnerOfWithData {
        address owner;
        uint96 lastTransferTimestamp;
    }

    struct Loan {
        uint256[] idsDeposited;
        uint256 loanExpiry;
        uint256 principalOwed;
        uint256 interestOwed;
    }

    /*//////////////////////////////////////////////////////////////
                       Errors
    //////////////////////////////////////////////////////////////*/
    
    error NotOnList();
    error TooMany();
    error TokenNotPaid();
    error Cooldown();
    error PoolAlreadyExists();
    error InitialMintIncomplete();
    error NoZero();
    error WrongFrom();
    error Unauth();
    error UnauthLoan();
    error LoanTooLong();
    error LoanAlreadyExists();
    error TooEarlyToSieze();

    /*//////////////////////////////////////////////////////////////
                       Events
    //////////////////////////////////////////////////////////////*/

    event LoanOrigination(uint256[] ids, uint256 principalOwed, uint256 interestOwed, uint256 duration);
    event LoanClosure(uint256[] ids, uint256 principalOwed, uint256 interestOwed, address loanCloser);

    /*//////////////////////////////////////////////////////////////
                    Immutables
    //////////////////////////////////////////////////////////////*/

    // For merkle root
    bytes32 immutable MERKLE_ROOT;

    // Sudo immutable configs
    ICurve immutable LINEAR_CURVE;
    ICurve immutable XYK_CURVE;
    address immutable SUDO_FACTORY;
    uint256 immutable START_TIME;

    /*//////////////////////////////////////////////////////////////
                       State
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => OwnerOfWithData) public ownerOfWithData;
    mapping(address => Loan) public loanForUser;

    address public floorPool;
    address public tradePool;
    address public anchorPool;

    uint256 public totalSupply;

    /*//////////////////////////////////////////////////////////////
                       Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(
        ICurve _LINEAR_CURVE,
        ICurve _XYK_CURVE,
        address _SUDO_FACTORY,
        bytes32 _MERKLE_ROOT
    ) ERC721Minimal("Stronghold", "HODL") {
        LINEAR_CURVE = _LINEAR_CURVE;
        XYK_CURVE = _XYK_CURVE;
        SUDO_FACTORY = _SUDO_FACTORY;
        MERKLE_ROOT = _MERKLE_ROOT;
        START_TIME = block.timestamp;
        _setDefaultRoyalty(address(this), ROYALTY_BPS);
    }

    /*//////////////////////////////////////////////////////////////
                     Pair Hook x Rebalance Logic
    //////////////////////////////////////////////////////////////*/

    function afterSwapNFTInPair(
        uint256 ,
        uint256 ,
        uint256 _tokensOutRoyalty,
        uint256[] calldata 
    ) external {

        // Auto rebalance on swaps if coming from floor/anchor/trade pool
        if (msg.sender == floorPool || msg.sender == anchorPool || msg.sender == tradePool) {
            distributeFees(_tokensOutRoyalty);
        }

    }

    function afterSwapNFTOutPair(
        uint256 ,
        uint256 ,
        uint256 _tokensInRoyalty,
        uint256[] calldata 
    ) external {

        // Auto rebalance on swaps if coming from floor/anchor/trade pool
        if (msg.sender == floorPool || msg.sender == anchorPool || msg.sender == tradePool) {
            distributeFees(_tokensInRoyalty);
        }
    }

    // Intended to be called by `afterSwapNFTInPair` and `afterSwapNFTOutPair`
    // but can also be called manually if needed
    function distributeFees(uint256 royaltyAmount) public {

        // Send to floor pool, and update price
        {
            uint256 floorDeposit = royaltyAmount / FLOOR_DENOM;
            payable(floorPool).safeTransferETH(floorDeposit);
            uint128 newSpotPrice = uint128(LSSVMPair(floorPool).spotPrice() + floorDeposit / TOTAL_SUPPLY);
            LSSVMPair(floorPool).changeSpotPrice(newSpotPrice);
        }

        // Send to anchor pool, no price update
        {
            uint256 anchorDeposit = royaltyAmount / ANCHOR_DENOM;
            payable(anchorPool).safeTransferETH(anchorDeposit);
        }

        // Send to trade pool, update price
        {
            uint256 tradeDeposit = royaltyAmount / TRADE_DENOM;
            payable(tradePool).safeTransferETH(tradeDeposit);
            uint128 newSpotPrice = uint128(LSSVMPair(tradePool).spotPrice() + tradeDeposit);
            LSSVMPair(tradePool).changeSpotPrice(newSpotPrice);
        }
    }

    /*//////////////////////////////////////////////////////////////
                      Mint x Pool 
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 startInclusive, uint256 endExclusive) internal virtual {
        uint256 numIds = endExclusive - startInclusive;
        unchecked {
            _balanceOf[to] += numIds;
        }
        for (uint256 i; i < numIds;) {
            uint256 id = startInclusive + i;
            ownerOfWithData[id].owner = to;
            emit Transfer(address(0), to, id);
            unchecked {
                ++i;
            }
        }
    }

    function mint(uint256 amountToMint, bytes32[] calldata proof) payable external {
        
        // Verify caller is allowed if nonzero merkle root
        if ((MERKLE_ROOT != bytes32(0)) && (block.timestamp < START_TIME + DELAY_BEFORE_PUBLIC_MINT)) {
            if (!MerkleProof.verify(proof, MERKLE_ROOT, keccak256(abi.encodePacked(msg.sender)))) {
            revert NotOnList();
            }
        }
        
        if (totalSupply + amountToMint > INITIAL_LAUNCH_SUPPLY) {
            revert TooMany();
        }

        // Take in input tokens
        uint256 mintPrice = INITIAL_LAUNCH_PRICE * amountToMint;
        if (msg.value != mintPrice) {
            revert TokenNotPaid();
        }

        // Mint to caller
        uint256 prevTotalSupply = totalSupply;
        _mint(msg.sender, prevTotalSupply, prevTotalSupply + amountToMint);

        // Update total supply
        totalSupply += amountToMint;
    }

    // Creates a 0-delta floor pool
    function initFloorPool() public {

        if (floorPool != address(0)) {
            revert PoolAlreadyExists();
        }
        if (totalSupply < INITIAL_LAUNCH_SUPPLY) {
            revert InitialMintIncomplete();
        }
        uint256[] memory empty = new uint256[](0);
        floorPool = address(PairFactoryLike(SUDO_FACTORY).createPairERC721ETH{value: FLOOR_INITIAL_TOKEN_BALANCE}(
            IERC721(address(this)), 
            LINEAR_CURVE, 
            payable(address(0)), 
            LSSVMPair.PoolType.TRADE, 
            0, 
            0, 
            FLOOR_SPOT_PRICE, 
            address(0), 
            empty, 
            address(this), 
            address(0)
        ));
    }

    // Create linear pool that gets adjusted
    function initAnchorPool() public {

        if (anchorPool != address(0)) {
            revert PoolAlreadyExists();
        }
        if (totalSupply < INITIAL_LAUNCH_SUPPLY) {
            revert InitialMintIncomplete();
        }

        uint256[] memory empty = new uint256[](0);
        anchorPool = address(PairFactoryLike(SUDO_FACTORY).createPairERC721ETH(
            IERC721(address(this)), 
            LINEAR_CURVE, 
            payable(address(0)), 
            LSSVMPair.PoolType.TRADE, 
            ANCHOR_DELTA, 
            0, 
            ANCHOR_SPOT_PRICE, 
            address(0), 
            empty, 
            address(this), 
            address(0)
        ));

        // Mint to anchor pool
        _mint(anchorPool, INITIAL_LAUNCH_SUPPLY, INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY);

        // Update total supply
        totalSupply += ANCHOR_INITIAL_SUPPLY;

        // TODO: sync ids for anchor pool (?)
    }
    
    function initTradePool() public {

        if (tradePool != address(0)) {
            revert PoolAlreadyExists();
        }
        if (totalSupply < INITIAL_LAUNCH_SUPPLY) {
            revert InitialMintIncomplete();
        }

        uint256[] memory empty = new uint256[](0);
        tradePool = address(PairFactoryLike(SUDO_FACTORY).createPairERC721ETH(
            IERC721(address(this)), 
            XYK_CURVE, 
            payable(address(0)), 
            LSSVMPair.PoolType.TRADE, 
            TRADE_DELTA, 
            0, 
            TRADE_SPOT_PRICE, 
            address(0), 
            empty, 
            address(this), 
            address(0)
        ));

        // Mint to trade pool
        _mint(tradePool, INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY, INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + TRADE_INITIAL_SUPPLY);

        // Update total supply
        totalSupply += TRADE_INITIAL_SUPPLY;

        // TODO: sync ids for anchor pool (?)
    }

    /*//////////////////////////////////////////////////////////////
                      Borrow x Margin
    //////////////////////////////////////////////////////////////*/

    function borrow(uint256[] calldata idsToDeposit, uint256 loanDurationInSeconds, address loanOwner, address loanRecipient) external nonReentrant returns (uint256 loanAmount) {
        
        // Check if loan duration is too long
        if (loanDurationInSeconds > MAX_LOAN_DURATION) {
            revert LoanTooLong();
        }

        // Can only open loans for a user if they don't have an open loan
        if (loanForUser[loanOwner].principalOwed != 0) {
            revert LoanAlreadyExists();
        }

        // Can only open loans for a user if they have approved the caller
        if (loanOwner != msg.sender && !isApprovedForAll[loanOwner][msg.sender]) {
            revert UnauthLoan();
        }

        // Take NFTs from caller
        uint256 numToDeposit = idsToDeposit.length;
        for (uint i; i < numToDeposit; ++i) {
            IERC721(address(this)).transferFrom(msg.sender, address(this), idsToDeposit[i]);
        }

        // Calculate loan and interest amount
        loanAmount = getLoanAmount(numToDeposit);
        uint256 interestAmount = getInterestOwed(loanAmount, loanDurationInSeconds);

        // Withdraw and send the loan amount to the caller
        LSSVMPairETH(payable(floorPool)).withdrawETH(loanAmount);
        payable(loanRecipient).safeTransferETH(loanAmount);

        // Store the loan data
        loanForUser[loanOwner] = Loan({
            idsDeposited: idsToDeposit,
            loanExpiry: block.timestamp + loanDurationInSeconds,
            principalOwed: loanAmount,
            interestOwed: interestAmount
        });
        
        emit LoanOrigination(idsToDeposit, loanAmount, interestAmount, loanDurationInSeconds);
    }

    // Allows a user to repay their own loan
    function repay() payable external {
        _repayLoanForUser(msg.sender, msg.sender);
    }

    // Anyone can close an open loan if it's expired and past the grace period
    function seizeLoan(address loanOriginator) external {

        Loan storage userLoan = loanForUser[loanOriginator]; 

        // Can only sieze loan if it's past the expiry + grace period
        if (block.timestamp < userLoan.loanExpiry + LOAN_GRACE_PERIOD) {
            revert TooEarlyToSieze();
        }

        _repayLoanForUser(loanOriginator, msg.sender);
    }

    function _repayLoanForUser(address loanOriginator, address loanCloser) internal {

        // Get loan amount owed by loanOriginator
        Loan storage userLoan = loanForUser[loanOriginator]; 
        uint256 amountToRepay = userLoan.interestOwed + userLoan.principalOwed;

        // Take repayment from loanCloser
        if (msg.value < amountToRepay) {
            revert TokenNotPaid();
        }

        // Send original amount back to the floor pool
        payable(floorPool).safeTransferETH(userLoan.principalOwed);

        // Interest owed is used as fees to redistribute
        distributeFees(userLoan.interestOwed);

        // Send NFTs back to the loanCloser
        for (uint i; i < userLoan.idsDeposited.length; ++i) {
            IERC721(address(this)).transferFrom(address(this), loanCloser, userLoan.idsDeposited[i]);
        }

        // Clear out the user's loan info
        delete loanForUser[loanOriginator];

        emit LoanClosure(userLoan.idsDeposited, userLoan.principalOwed, userLoan.interestOwed, loanCloser);
    }

    function getLoanAmount(uint256 numNFTsToDeposit) public view returns (uint256 loanAmount) {
        loanAmount = (LSSVMPair(floorPool).spotPrice() * numNFTsToDeposit * LOAN_NUM) / LOAN_DENOM;
    }

    function getInterestOwed(uint256 loanAmount, uint256 loanDurationInSeconds) public pure returns (uint256 interestOwed) {
        interestOwed = (loanAmount * loanDurationInSeconds * INTEREST_NUM) / INTEREST_DENOM;
    }

    /*//////////////////////////////////////////////////////////////
                   IERC721 Compliance
    //////////////////////////////////////////////////////////////*/

    // TODO
    function tokenURI(uint256) public pure override returns (string memory) {
        return '';
    }

    // Overrides both ERC721 and ERC2981
    function supportsInterface(bytes4 interfaceId) public pure override(ERC2981, ERC721Minimal) returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x80ac58cd // ERC165 Interface ID for ERC721
            || interfaceId == 0x2a55205a // ERC165 interface for IERC2981
            || interfaceId == 0x5b5e139f; // ERC165 Interface ID for ERC721Metadata
    }

    function ownerOf(uint256 id) public view override returns (address owner) {
        owner = ownerOfWithData[id].owner;
    }

    // Transfers that are not to or from a sudoswap pool (or this address (for loans)) incur a 7 day delay
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

        // Always allow transfer if one of the recipients is a sudo pool or if it's to the NFT itself
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

    function getLoanDataForUser(address user) external view returns (uint256[] memory, uint256, uint256, uint256) {
        Loan storage l = loanForUser[user];
        return (
            l.idsDeposited,
            l.loanExpiry,
            l.principalOwed,
            l.interestOwed
        );
    }

    receive() external payable {}

    // Everything else is a no-op, just for hook compatibility
    function afterNewPair() external {}
    function afterDeltaUpdate(uint128 , uint128 ) external {}
    function afterSpotPriceUpdate(uint128 , uint128 ) external {}
    function afterFeeUpdate(uint96 , uint96 ) external {}
    function afterNFTWithdrawal(uint256[] calldata ) external {}
    function afterTokenWithdrawal(uint256 ) external {}
    function syncForPair(address , uint256 , uint256[] calldata ) external {}
}