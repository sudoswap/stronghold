// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */
/* solhint-disable func-name-mixedcase */

pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Sudo specific imports
import {LSSVMPairFactory} from "lib/lssvm2/src/LSSVMPairFactory.sol";
import {RoyaltyEngine} from "lib/lssvm2/src/RoyaltyEngine.sol";
import {LSSVMPairERC721ETH} from "lib/lssvm2/src/erc721/LSSVMPairERC721ETH.sol";
import {LSSVMPairERC1155ETH} from "lib/lssvm2/src/erc1155/LSSVMPairERC1155ETH.sol";
import {LSSVMPairERC721ERC20} from "lib/lssvm2/src/erc721/LSSVMPairERC721ERC20.sol";
import {LSSVMPairERC1155ERC20} from "lib/lssvm2/src/erc1155/LSSVMPairERC1155ERC20.sol";
import {LSSVMPair} from "lib/lssvm2/src/LSSVMPair.sol";
import {LinearCurve} from "lib/lssvm2/src/bonding-curves/LinearCurve.sol";
import {XykCurve} from "lib/lssvm2/src/bonding-curves/XykCurve.sol";
import {ICurve} from "lib/lssvm2/src/bonding-curves/ICurve.sol";

import {Test20} from "./Test20.sol";

import {StrongholdETH} from "../src/StrongholdETH.sol";
import {FlashLoanerETH} from "../src/FlashLoanerETH.sol";
import {IConstants} from "../src/IConstants.sol";

contract StrongholdTest is Test, IConstants {

    LSSVMPairFactory pairFactory;
    LinearCurve linearCurve;
    XykCurve xykCurve;
    StrongholdETH stronghold;
    FlashLoanerETH flashLoaner;

    address constant ALICE = address(123);
    address constant BOB = address(456);
    address constant CAROL = address(789);
    address constant DAVE = address(101112);

    uint256 constant LARGE_TOKEN_AMOUNT = 1000000 ether;
    bytes32[] proof;

    function setUp() public {
        
        // Initialize sudo factory
        RoyaltyEngine royaltyEngine = new RoyaltyEngine(address(0)); // We use a fake registry
        LSSVMPairERC721ETH erc721ETHTemplate = new LSSVMPairERC721ETH(royaltyEngine);
        LSSVMPairERC721ERC20 erc721ERC20Template = new LSSVMPairERC721ERC20(royaltyEngine);
        LSSVMPairERC1155ETH erc1155ETHTemplate = new LSSVMPairERC1155ETH(royaltyEngine);
        LSSVMPairERC1155ERC20 erc1155ERC20Template = new LSSVMPairERC1155ERC20(royaltyEngine);
        pairFactory = new LSSVMPairFactory(
            erc721ETHTemplate,
            erc721ERC20Template,
            erc1155ETHTemplate,
            erc1155ERC20Template,
            payable(address(0)),
            0, // Zero protocol fee
            address(this)
        );
        linearCurve = new LinearCurve();
        xykCurve = new XykCurve();
        pairFactory.setBondingCurveAllowed(ICurve(address(linearCurve)), true);
        pairFactory.setBondingCurveAllowed(ICurve(address(xykCurve)), true);

        // Init allow list
        // Create merkle tree
        address[2] memory allowedUsers = [ALICE, BOB];
        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = keccak256(abi.encodePacked(allowedUsers[0]));
        hashes[1] = keccak256(abi.encodePacked(allowedUsers[1]));
        hashes[2] = keccak256(abi.encodePacked(hashes[1], hashes[0]));

        // Create encoded merkle proof list
        proof = new bytes32[](1);
        proof[0] = hashes[1];

        // Init stronghold
        stronghold = new StrongholdETH(
            linearCurve,
            xykCurve,
            address(pairFactory),
            hashes[2]
        );

        // Mint enough ETH to ALICE, BOB, CAROL
        vm.deal(ALICE, LARGE_TOKEN_AMOUNT);
        vm.deal(BOB, LARGE_TOKEN_AMOUNT);        
        vm.deal(CAROL, LARGE_TOKEN_AMOUNT);
    }

    /**
        minting
        - allowed user can mint [x]
        - disallowed user cannot mint [x]
        - cannot call distribute fees before pools are deployed

        pools
        - can deploy pools after minting out (is this a prereq?) [x]
        - pools have the right delta/spot price [x]
        - pools have the right bonding curve [x]

        swapping
        - can buy linear
        - check rebalance logic after linear pool is breached
        - can buy trade pool after
        - swaps add to the pool invariants

        rebalancing
        - check more specific rebalancing logic
     */

    function test_allowedMintSucceedsWithEnoughBalance() public {

        // Prank as ALICE
        vm.startPrank(ALICE);

        // Attempt to mint 1 token
        stronghold.mint{value: INITIAL_LAUNCH_PRICE}(1, proof);

        // Assert ALICE has balance of 1
        assertEq(stronghold.balanceOf(ALICE), 1);

        // Assert that stronghold has INITIAL_LAUNCH_PRICE tokens
        assertEq(address(stronghold).balance, INITIAL_LAUNCH_PRICE);

        vm.stopPrank();
    }

    function test_allowedMintSucceedsWithEnoughBalanceConsecutive() public {

        // Prank as ALICE
        vm.startPrank(ALICE);

        // Attempt to mint 1 token
        stronghold.mint{value: INITIAL_LAUNCH_PRICE}(1, proof);
        // Attempt to mint another token
        stronghold.mint{value: INITIAL_LAUNCH_PRICE}(1, proof);

        // Assert ALICE has balance of 1
        assertEq(stronghold.balanceOf(ALICE), 2);

        // Assert that stronghold has INITIAL_LAUNCH_PRICE * 2 tokens
        assertEq(address(stronghold).balance, INITIAL_LAUNCH_PRICE * 2);

        vm.stopPrank();
    }

    function test_allowedMintFailsIfInsufficientFundsSent() public {

        // Prank as ALICE
        vm.startPrank(ALICE);

        // Attempt to mint 1 token
        vm.expectRevert(StrongholdETH.TokenNotPaid.selector);
        stronghold.mint{value: INITIAL_LAUNCH_PRICE - 1}(1, proof);

        vm.stopPrank();
    }

    function test_mintFailsIfNotOnListBeforeDeadline() public {

        // Prank as CAROL
        vm.startPrank(CAROL);

        vm.expectRevert(StrongholdETH.NotOnList.selector);

        // Attempt to mint 1 token
        stronghold.mint{value: INITIAL_LAUNCH_PRICE}(1, proof);

        vm.stopPrank();
    }

    function test_disallowedMintSucceedsIfRootIsZero() public {
        StrongholdETH zeroStronghold = new StrongholdETH(
            linearCurve,
            xykCurve,
            address(pairFactory),
            bytes32(0)
        );
        vm.startPrank(CAROL);
        zeroStronghold.mint{value: INITIAL_LAUNCH_PRICE}(1, proof);
        vm.stopPrank();
    }

    function test_disallowedMintSucceedsIfRootIsNonzeroButEnoughTimeHasPassed() public {
        StrongholdETH zeroStronghold = new StrongholdETH(
            linearCurve,
            xykCurve,
            address(pairFactory),
            bytes32("1")
        );
        vm.startPrank(CAROL);
        vm.warp(block.timestamp + DELAY_BEFORE_PUBLIC_MINT + 1);
        zeroStronghold.mint{value: INITIAL_LAUNCH_PRICE}(1, proof);
        vm.stopPrank();
    }

    function test_distributeFeesFailsIfPoolsNotAllDeployed() public {
        vm.expectRevert();
        stronghold.distributeFees(0);
    }

    function _finishMintAndInitPools() internal {
        vm.startPrank(ALICE);
        stronghold.mint{value: INITIAL_LAUNCH_SUPPLY * INITIAL_LAUNCH_PRICE}(INITIAL_LAUNCH_SUPPLY, proof); 
        stronghold.initFloorPool();
        stronghold.initAnchorPool();
        stronghold.initTradePool();
        vm.stopPrank();
    }

    function test_createPoolsSucceedAfterInitialMint() public {

        _finishMintAndInitPools();

        // Check that trying to recreate them also fails
        vm.expectRevert(StrongholdETH.PoolAlreadyExists.selector);
        stronghold.initFloorPool();

        vm.expectRevert(StrongholdETH.PoolAlreadyExists.selector);
        stronghold.initAnchorPool();

        vm.expectRevert(StrongholdETH.PoolAlreadyExists.selector);
        stronghold.initTradePool();

        // Assert that floor and anchor use linear curve
        assertEq(address(LSSVMPair(stronghold.floorPool()).bondingCurve()), address(linearCurve));
        assertEq(address(LSSVMPair(stronghold.anchorPool()).bondingCurve()), address(linearCurve));

        // Assert that trade pool uses xyk curve
        assertEq(address(LSSVMPair(stronghold.tradePool()).bondingCurve()), address(xykCurve));

        // Assert that the spot price and deltas are as expected
        assertEq(LSSVMPair(stronghold.floorPool()).spotPrice(), FLOOR_SPOT_PRICE);
        assertEq(LSSVMPair(stronghold.floorPool()).delta(), 0);

        assertEq(LSSVMPair(stronghold.anchorPool()).spotPrice(), ANCHOR_SPOT_PRICE);
        assertEq(LSSVMPair(stronghold.anchorPool()).delta(), ANCHOR_DELTA);
        assertEq(stronghold.balanceOf(stronghold.anchorPool()), ANCHOR_INITIAL_SUPPLY);

        assertEq(LSSVMPair(stronghold.tradePool()).spotPrice(), TRADE_SPOT_PRICE);
        assertEq(LSSVMPair(stronghold.tradePool()).delta(), TRADE_DELTA);
        assertEq(stronghold.balanceOf(stronghold.tradePool()), TRADE_INITIAL_SUPPLY);
    }

    function test_createPoolsFailBeforeInitialMintComplete() public {

        // Mint out all INITIAL_LAUNCH_SUPPLY-1 NFTs
        vm.startPrank(ALICE);

        // Mint them all
        stronghold.mint{value: (INITIAL_LAUNCH_SUPPLY-1) * INITIAL_LAUNCH_PRICE}(INITIAL_LAUNCH_SUPPLY-1, proof);

        // Attempt to create all 3 pools
        vm.expectRevert(StrongholdETH.InitialMintIncomplete.selector);
        stronghold.initFloorPool();

        vm.expectRevert(StrongholdETH.InitialMintIncomplete.selector);
        stronghold.initAnchorPool();

        vm.expectRevert(StrongholdETH.InitialMintIncomplete.selector);
        stronghold.initTradePool();
    }

    /**
    - borrow succeeds when taking out on behalf of other user
    - multi borrow succeeds []
    - multi borrow succeeds on behalf of other user
    - borrow fails if duration is too long
    - borrow fails if already active loan
    - borrow for other fails if no approval
    - swapping on leverage (flash loan, swap, borrow, close loan) succeeds
    - multi swap on leverage succeeds []
    - swapping on leverage fails if insufficent value sent
    - can borrow and repay early
    - can borrow and repay late
    - sieze borrow fails if too early
    - sieze borrow succeeds if grace period has paased
    - size multiple borrow succeeds if grace period has passed
    */

    function test_borrowSucceedsForApprovedUser() public {

        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for DAVE, approve ALICE to give them a loan first
        vm.startPrank(DAVE);
        stronghold.setApprovalForAll(ALICE, true);

        // Take out loan as ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        stronghold.borrow(id, 1, DAVE, DAVE);
        vm.stopPrank();

        assertEq(address(DAVE).balance, stronghold.getLoanAmount(1));
    }

    function test_borrowSucceedsForOwner() public {

        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for ALICE
        vm.startPrank(ALICE);

        // Take out loan as DAVE
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        uint256 prevBalance = address(ALICE).balance;
        stronghold.borrow(id, 1, ALICE, ALICE);
        vm.stopPrank();

        assertEq(address(ALICE).balance - prevBalance, stronghold.getLoanAmount(1));
    }

    function test_multiBorrowSucceeds() public {

        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan as ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(ALICE, true);

        // Take out loan as ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory ids = new uint256[](3);

        ids[0] = 0;
        ids[1] = 1;
        ids[2] = 2;

        uint256 prevBalance = address(ALICE).balance;
        stronghold.borrow(ids, 1, ALICE, ALICE);
        vm.stopPrank();

        assertEq(address(ALICE).balance - prevBalance, stronghold.getLoanAmount(3));
    }

    function test_borrowFailsIfDurationIsTooLong() public {
         _finishMintAndInitPools();

        // Take a out loan for DAVE, approve ALICE first
        vm.startPrank(DAVE);
        stronghold.setApprovalForAll(ALICE, true);

        // Swap to ALICE
        vm.startPrank(ALICE);

        // Take a out loan for DAVE
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        
        vm.expectRevert(StrongholdETH.LoanTooLong.selector);
        stronghold.borrow(id, MAX_LOAN_DURATION + 1, DAVE, DAVE);

        vm.stopPrank();
    }

    function test_borrowFailsIfLoanAlreadyExists() public {
        _finishMintAndInitPools();

        vm.startPrank(ALICE);

        // Take a out loan for ALICE for herself
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        stronghold.borrow(id, 1, ALICE, ALICE);

        // Take out another loan (should fail)
        id[0] = 1;
        vm.expectRevert(StrongholdETH.LoanAlreadyExists.selector);
        stronghold.borrow(id, 1, ALICE, ALICE);

        vm.stopPrank();
    }

    function test_borrowFailsIfUserDoesNotOwnNFT() public {
        _finishMintAndInitPools();

        // Take a out loan as BOB
        vm.startPrank(BOB);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        vm.expectRevert();
        stronghold.borrow(id, 1, BOB, BOB);
    }

    function test_borrowForOthersFailsIfUserDoesNotApprove() public {

        _finishMintAndInitPools();

        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        vm.expectRevert(StrongholdETH.UnauthLoan.selector);
        stronghold.borrow(id, 1, BOB, ALICE);

        vm.expectRevert(StrongholdETH.UnauthLoan.selector);
        stronghold.borrow(id, 1, BOB, BOB);
    }

    function test_swapBorrowAndBuy() public {

        _finishMintAndInitPools();

        // Init flash loaner with ETH
        flashLoaner = new FlashLoanerETH(stronghold, LSSVMPair(stronghold.tradePool()));
        vm.deal(address(flashLoaner), 10 ether);

        // Call flash loaner and margin swap for 1 NFT
        uint256[] memory ids = new uint256[](1);

        // Get the first ID put into the trade pool
        ids[0] = INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + 1;

        uint256 flashLoanerStartBalance = address(flashLoaner).balance;

        // As BOB, approve flash loaner to take out loans for them
        vm.startPrank(BOB);
        stronghold.setApprovalForAll(address(flashLoaner), true);
        flashLoaner.openLeverage{value: flashLoaner.getMarginAmount(1)}(ids, 1);

        uint256 flashLoanerEndBalance = address(flashLoaner).balance;

        // Ensure the end balance is greater
        assertGtDecimal(flashLoanerEndBalance, flashLoanerStartBalance, 0);

        // Ensure the loan exists
        (uint256[] memory marginedIds, , , ) = stronghold.getLoanDataForUser(BOB);

        // Check that ids[0] = ids[0]
        assertEq(marginedIds[0], ids[0]);
    }

    function test_swapBorrowAndBuyMultiple() public {

        _finishMintAndInitPools();

        // Init flash loaner with ETH
        flashLoaner = new FlashLoanerETH(stronghold, LSSVMPair(stronghold.tradePool()));
        vm.deal(address(flashLoaner), 10 ether);

        // Call flash loaner and margin swap for 1 NFT
        uint256[] memory ids = new uint256[](3);

        // Get the first ID put into the trade pool
        ids[0] = INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + 1;
        ids[1] = INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + 2;
        ids[2] = INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + 3;

        uint256 flashLoanerStartBalance = address(flashLoaner).balance;

        // As BOB, approve flash loaner to take out loans for them
        vm.startPrank(BOB);
        stronghold.setApprovalForAll(address(flashLoaner), true);
        flashLoaner.openLeverage{value: flashLoaner.getMarginAmount(3)}(ids, 1);

        uint256 flashLoanerEndBalance = address(flashLoaner).balance;

        // Ensure the end balance is greater
        assertGtDecimal(flashLoanerEndBalance, flashLoanerStartBalance, 0);

        // Ensure the loan exists
        (uint256[] memory marginedIds, , , ) = stronghold.getLoanDataForUser(BOB);

        // Check that ids[0] = ids[0]
        assertEq(marginedIds[0], ids[0]);
        assertEq(marginedIds[1], ids[1]);
        assertEq(marginedIds[2], ids[2]);
    }

    function test_swapBorrowAndBuyFailsIfInsufficientTokensSent() public {

        _finishMintAndInitPools();

        // Init flash loaner with ETH
        flashLoaner = new FlashLoanerETH(stronghold, LSSVMPair(stronghold.tradePool()));
        vm.deal(address(flashLoaner), 10 ether);

        // Call flash loaner and margin swap for 1 NFT
        uint256[] memory ids = new uint256[](1);

        // Get the first ID put into the trade pool
        ids[0] = INITIAL_LAUNCH_SUPPLY + ANCHOR_INITIAL_SUPPLY + 1;

        // Approve the flash loaner as BOB
        vm.startPrank(BOB);
        stronghold.setApprovalForAll(address(flashLoaner), true);

        // Specifically send less than needed
        uint256 insufficientAmount = flashLoaner.getMarginAmount(1) - 1;

        // Expect revert
        vm.expectRevert(FlashLoanerETH.NotEnoughTokensSent.selector);
        flashLoaner.openLeverage{value: insufficientAmount}(ids, 1);
    }

    function test_canBorrowAndRepayEarly() public {
        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        uint256 loanDuration = 24 hours;
        stronghold.borrow(id, loanDuration, ALICE, ALICE);

        // Wait loan duration, then repay
        vm.warp(block.timestamp + loanDuration);
        (, , uint256 principal, uint256 interest) = stronghold.getLoanDataForUser(ALICE);
        stronghold.repay{value: principal + interest}();

        // Ensure the loan is deleted
        (uint256[] memory marginedIds, uint256 loanExpiry, uint256 principalOwed, uint256 interestOwed) = stronghold.getLoanDataForUser(ALICE);

        // Check that the loan is zeroed out
        assertEq(marginedIds.length, 0);
        assertEq(loanExpiry, 0);
        assertEq(principalOwed, 0);
        assertEq(interestOwed, 0);
    }

    function test_canBorrowAndRepayLate() public {
        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        uint256 loanDuration = 24 hours;
        stronghold.borrow(id, loanDuration, ALICE, ALICE);

        // Wait loan duration plus 1, then repay
        vm.warp(block.timestamp + loanDuration + 1);
        (, , uint256 principal, uint256 interest) = stronghold.getLoanDataForUser(ALICE);
        stronghold.repay{value: principal + interest}();

        // Ensure the loan is deleted
        (uint256[] memory marginedIds, uint256 loanExpiry, uint256 principalOwed, uint256 interestOwed) = stronghold.getLoanDataForUser(ALICE);

        // Check that the loan is zeroed out
        assertEq(marginedIds.length, 0);
        assertEq(loanExpiry, 0);
        assertEq(principalOwed, 0);
        assertEq(interestOwed, 0);
    }
    
    function test_seizeBorrowFailsIfTooEarly() public {
        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        uint256 loanDuration = 24 hours;
        stronghold.borrow(id, loanDuration, ALICE, ALICE);

        // Wait loan duration, then attempt to repay
        vm.warp(block.timestamp + loanDuration);
        vm.startPrank(BOB);
        (, , uint256 principal, uint256 interest) = stronghold.getLoanDataForUser(ALICE);

        // Should fail because too early
        vm.expectRevert(StrongholdETH.TooEarlyToSeize.selector);
        stronghold.seizeLoan{value: principal + interest}(ALICE);
    }

    function test_seizeBorrowSucceeds() public {
        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for ALICE
        vm.startPrank(ALICE);
        stronghold.setApprovalForAll(address(stronghold), true);
        uint256[] memory id = new uint256[](1);
        uint256 loanDuration = 24 hours;
        stronghold.borrow(id, loanDuration, ALICE, ALICE);

        // Wait loan duration, then attempt to repay as BOB
        vm.warp(block.timestamp + loanDuration + LOAN_GRACE_PERIOD + 1);
        vm.startPrank(BOB);
        (uint256[] memory ids, , uint256 principal, uint256 interest) = stronghold.getLoanDataForUser(ALICE);
        stronghold.seizeLoan{value: principal + interest}(ALICE);

        // Assert BOB owns the seized id now
        assertEq(stronghold.ownerOf(ids[0]), BOB);

        // Assert the loan is cleared
        (ids, , principal, interest) = stronghold.getLoanDataForUser(ALICE);
        assertEq(principal, 0);
        assertEq(interest, 0);
        assertEq(ids.length, 0);
    }
}