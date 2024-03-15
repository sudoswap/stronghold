// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {LSSVMPair} from "lssvm2/LSSVMPair.sol";
import {ICurve} from "lssvm2/bonding-curves/ICurve.sol";
import {IPairHooks} from "lssvm2/hooks/IPairHooks.sol";

import {ERC2981} from "openzeppelin-contracts/contracts/token/common/ERC2981.sol";
import {IERC2981} from "openzeppelin-contracts/contracts/interfaces/IERC2981.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC721Minimal} from "./ERC721Minimal.sol";
import {PairFactoryLike} from "./PairFactoryLike.sol";

contract Stronghold is ERC721Minimal, ERC2981, IPairHooks {

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

    error Cooldown();
    error NoZero();
    error WrongFrom();
    error Unauth();
    error LoanTooLong();
    error TooEarlyToSieze();

    /*//////////////////////////////////////////////////////////////
                       Events
    //////////////////////////////////////////////////////////////*/

    event LoanOrigination(uint256[] ids, uint256 principalOwed, uint256 interestOwed, uint256 duration);
    event LoanClosure(uint256[] ids, uint256 principalOwed, uint256 interestOwed, address loanCloser);

    /*//////////////////////////////////////////////////////////////
                    Constants x Immutables
    //////////////////////////////////////////////////////////////*/

    // Launch configs
    uint256 constant INITIAL_LAUNCH_SUPPLY = 1000;

    // General configs
    uint256 constant TRANSFER_DELAY = 7 days;
    uint96 constant ROYALTY_BPS = 250;

    // Floor pool configs
    uint128 constant FLOOR_DELTA = 1 ether;
    uint128 constant FLOOR_SPOT_PRICE = 1 ether;
    uint128 constant FLOOR_INITIAL_TOKEN_BALANCE = 10 ether;

    // Anchor pool configs
    uint128 constant ANCHOR_DELTA = 1 ether;
    uint128 constant ANCHOR_SPOT_PRICE = 100 ether;
    uint256 constant ANCHOR_INITIAL_SUPPLY = 500;

    // Trade pool configs
    uint128 constant TRADE_INITIAL_SUPPLY = 3500;
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
    uint256 constant MAX_LOAN_DURATION = 84 days;
    uint256 constant INTEREST_NUM = 2; // Approx 0.02% a day in interest
    uint256 constant INTEREST_DENOM = 864000000; 
    uint256 constant LOAN_GRACE_PERIOD = 1 days;

    // Sudo immutable configs
    ICurve immutable LINEAR_CURVE;
    ICurve immutable XYK_CURVE;
    address immutable QUOTE_TOKEN;
    address immutable SUDO_FACTORY;

    /*//////////////////////////////////////////////////////////////
                       State
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => OwnerOfWithData) public ownerOfWithData;
    mapping(address => Loan) public loanForUser;

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
            IERC20(QUOTE_TOKEN).transfer(floorPool, floorDeposit);
            uint128 newSpotPrice = uint128(LSSVMPair(floorPool).spotPrice() + floorDeposit / TOTAL_SUPPLY);
            LSSVMPair(floorPool).changeSpotPrice(newSpotPrice);
        }

        // Send to anchor pool, no price update
        {
            uint256 anchorDeposit = royaltyAmount / ANCHOR_DENOM;
            IERC20(QUOTE_TOKEN).transfer(anchorPool, anchorDeposit);
        }

        // Send to trade pool, update price
        {
            uint256 tradeDeposit = royaltyAmount / TRADE_DENOM;
            IERC20(QUOTE_TOKEN).transfer(tradePool, tradeDeposit);
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

    // Creates a 0-delta floor pool
    function initFloorPool() public {
        require(floorPool == address(0));
        uint256[] memory empty = new uint256[](0);

        // Approve factory
        IERC20(QUOTE_TOKEN).approve(SUDO_FACTORY, FLOOR_INITIAL_TOKEN_BALANCE);

        // Create pool
        floorPool = address(PairFactoryLike(SUDO_FACTORY).createPairERC721ERC20(PairFactoryLike.CreateERC721ERC20PairParams({
            token: ERC20(QUOTE_TOKEN),
            nft: IERC721(address(this)),
            bondingCurve: LINEAR_CURVE,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: 0,
            fee: 0,
            spotPrice: FLOOR_SPOT_PRICE,
            propertyChecker: address(0),
            initialNFTIDs: empty,
            initialTokenBalance: FLOOR_INITIAL_TOKEN_BALANCE
        })));
    }

    // Create linear pool that gets adjusted
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

        // Mint to anchor pool
        _mint(anchorPool, INITIAL_LAUNCH_SUPPLY + 1, INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY);

        // TODO: sync ids for anchor pool (?)
    }
    
    function initTradePool() public {
        require(tradePool == address(0));
        uint256[] memory empty = new uint256[](0);
        tradePool = address(PairFactoryLike(SUDO_FACTORY).createPairERC721ERC20(PairFactoryLike.CreateERC721ERC20PairParams({
            token: ERC20(QUOTE_TOKEN),
            nft: IERC721(address(this)),
            bondingCurve: LINEAR_CURVE,
            assetRecipient: payable(address(0)),
            poolType: LSSVMPair.PoolType.TRADE,
            delta: TRADE_DELTA,
            fee: 0,
            spotPrice: TRADE_SPOT_PRICE,
            propertyChecker: address(0),
            initialNFTIDs: empty,
            initialTokenBalance: 0
        })));

        // Mint to trade pool
        _mint(anchorPool, INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + 1, INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + TRADE_INITIAL_SUPPLY);

        // TODO: sync ids for anchor pool (?)
    }

    /*//////////////////////////////////////////////////////////////
                      Borrow x Margin
    //////////////////////////////////////////////////////////////*/

    function borrow(uint256[] calldata idsToDeposit, uint256 loanDurationInSeconds) external returns (uint256) {
        
        // Check if loan duration is too long
        if (loanDurationInSeconds > MAX_LOAN_DURATION) {
            revert LoanTooLong();
        }

        // Take NFTs from caller
        uint256 numToDeposit = idsToDeposit.length;
        for (uint i; i < numToDeposit; ++i) {
            IERC721(address(this)).transferFrom(msg.sender, address(this), idsToDeposit[i]);
        }

        // Calculate loan and interest amount
        uint256 loanAmount = getLoanAmount(numToDeposit);
        uint256 interestAmount = getInterestOwed(loanAmount, loanDurationInSeconds);

        // Withdraw and send the loan (minus interest) to the caller
        LSSVMPair(floorPool).withdrawERC20(ERC20(QUOTE_TOKEN), loanAmount);
        ERC20(QUOTE_TOKEN).transfer(msg.sender, loanAmount);

        // Store the loan data
        loanForUser[msg.sender] = Loan({
            idsDeposited: idsToDeposit,
            loanExpiry: block.timestamp + loanDurationInSeconds,
            principalOwed: loanAmount,
            interestOwed: interestAmount
        });
        
        emit LoanOrigination(idsToDeposit, loanAmount, interestAmount, loanDurationInSeconds);
    }

    // TODO
    function borrowWithMargin(uint256[] calldata idsToBuyAndDeposit, uint256 loanDurationInSeconds) external {

    }

    // Allows a user to repay their own loan
    function repay() external {
        _repayLoanForUser(msg.sender, msg.sender);
    }

    // Anyone can close an open loan if it's expired and past the grace period
    function seizeLoan(address loanOriginator) external {

        Loan memory userLoan = loanForUser[loanOriginator]; 

        // Can only sieze loan if it's past the expiry + grace period
        if (block.timestamp < userLoan.loanExpiry + LOAN_GRACE_PERIOD) {
            revert TooEarlyToSieze();
        }

        _repayLoanForUser(loanOriginator, msg.sender);
    }

    function _repayLoanForUser(address loanOriginator, address loanCloser) internal {

        // Get loan amount owed by loanOriginator
        Loan memory userLoan = loanForUser[loanOriginator]; 
        uint256 amountToRepay = userLoan.interestOwed + userLoan.principalOwed;

        // Take repayment from loanCloser
        ERC20(QUOTE_TOKEN).transferFrom(loanCloser, address(this), amountToRepay);

        // Send original amount back to the floor pool
        ERC20(QUOTE_TOKEN).transfer(floorPool, userLoan.principalOwed);

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

    // 
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

    // Everything else is a no-op, just for hook compatibility
    function afterNewPair() external {}
    function afterDeltaUpdate(uint128 , uint128 ) external {}
    function afterSpotPriceUpdate(uint128 , uint128 ) external {}
    function afterFeeUpdate(uint96 , uint96 ) external {}
    function afterNFTWithdrawal(uint256[] calldata ) external {}
    function afterTokenWithdrawal(uint256 ) external {}
    function syncForPair(address , uint256 , uint256[] calldata ) external {}
}