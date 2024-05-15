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
    
            borrowing
        - user can borrow [x]
        - user borrow fails if loan duration is too long [x]
        - user cannot borrow more than 1 at a time [x]
        - user cannot borrow ids they do not have [x]
        
        - user can swap and borrow [x]
        - user cannot swap and borrow if it leaves the flash loaner insolvent [ ] (i.e. if they don't put up enough ETH)
        (assert that prev balance and after balance is the same after a flash swap)

        - user can repay loan if late [ ]
        - user can repay loan if early [ ]
        - interest is collected / computed correctly [ ]

        - another user can liquidate loan if late [ ]
        - another user cannot liquidate loan if late [ ]
    */

    function test_borrowSucceedsForUser() public {

        // Mint out all NFTs
        _finishMintAndInitPools();

        // Take a out loan for DAVE, approve ALICE first
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

        // Approve the flash loaner as BOB
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

}