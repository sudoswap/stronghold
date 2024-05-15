// SPDX-License-Identifier: AGPL-3.0

/* solhint-disable private-vars-leading-underscore */
/* solhint-disable var-name-mixedcase */
/* solhint-disable func-param-name-mixedcase */
/* solhint-disable no-unused-vars */
/* solhint-disable func-name-mixedcase */

/*
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Sudo specific imports
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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

import {ERC20} from "solmate/tokens/ERC20.sol";

import {Test20} from "./Test20.sol";

import {Stronghold} from "../src/Stronghold.sol";
import {IConstants} from "../src/IConstants.sol";

contract StrongholdTest is Test, IConstants {

    LSSVMPairFactory pairFactory;
    LinearCurve linearCurve;
    XykCurve xykCurve;
    Test20 quoteToken;
    Stronghold stronghold;

    address constant ALICE = address(123);
    address constant BOB = address(456);
    address constant CAROL = address(789);

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

        // Initialize quote token
        quoteToken = new Test20();

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
        stronghold = new Stronghold(
            linearCurve,
            xykCurve,
            address(quoteToken),
            address(pairFactory),
            hashes[2]
        );

        // Mint enough tokens to ALICE, BOB, CAROL
        // Approve Stronghold for each
        quoteToken.mint(ALICE, LARGE_TOKEN_AMOUNT);
        quoteToken.mint(BOB, LARGE_TOKEN_AMOUNT);        
        quoteToken.mint(CAROL, LARGE_TOKEN_AMOUNT);

        vm.startPrank(ALICE);
        quoteToken.approve(address(stronghold), LARGE_TOKEN_AMOUNT);
        vm.stopPrank();        
        
        vm.startPrank(BOB);
        quoteToken.approve(address(stronghold), LARGE_TOKEN_AMOUNT);
        vm.stopPrank();

        vm.startPrank(CAROL);
        quoteToken.approve(address(stronghold), LARGE_TOKEN_AMOUNT);
        vm.stopPrank();
    }

        minting
        - allowed user can mint [x]
        - disallowed user cannot mint [x]

        pools
        - can deploy pools after minting out (is this a prereq?) [x]

        swapping
        - can buy linear
        - check rebalance logic after linear pool is breached
        - can buy trade pool after
        - swaps add to the pool invariants

        rebalancing
        - check more specific rebalancing logic

        borrowing
        - user can borrow
        - user cannot borrow more
        - user cannot borrow ids they do not have
        - user can swap and borrow
        - user cannot swap and borrow if it leaves the flash loaner insolvent
        - user can repay loan if late
        - user can repay loan if early
        - another user can liquidate loan if late
        - another user cannot liquidate loan if late

    function test_allowedMintSucceedsWithEnoughBalance() public {

        // Prank as ALICE
        vm.startPrank(ALICE);

        // Attempt to mint 1 token
        stronghold.mint(1, proof);

        // Assert ALICE has balance of 1
        assertEq(stronghold.balanceOf(ALICE), 1);

        // Assert that stronghold has INITIAL_LAUNCH_PRICE tokens
        assertEq(quoteToken.balanceOf(address(stronghold)), INITIAL_LAUNCH_PRICE);

        vm.stopPrank();
    }

    function test_allowedMintSucceedsWithEnoughBalanceConsecutive() public {

        // Prank as ALICE
        vm.startPrank(ALICE);

        // Attempt to mint 1 token
        stronghold.mint(1, proof);
        // Attempt to mint another token
        stronghold.mint(1, proof);

        // Assert ALICE has balance of 1
        assertEq(stronghold.balanceOf(ALICE), 2);

        // Assert that stronghold has INITIAL_LAUNCH_PRICE * 2 tokens
        assertEq(quoteToken.balanceOf(address(stronghold)), INITIAL_LAUNCH_PRICE * 2);

        vm.stopPrank();
    }

    function test_allowedMintFailsWithNotEnoughBalance() public {
    
        // Prank as ALICE
        vm.startPrank(ALICE);

        // Send all tokens out
        quoteToken.transfer(address(1), quoteToken.balanceOf(ALICE));

        // Attempt to mint 1 token, should revert
        vm.expectRevert();
        stronghold.mint(1, proof);

        vm.stopPrank();
    }

    // An address not on the list cannot mint 
    function test_disallowedMintFails() public {

        // Prank as CAROL
        vm.startPrank(CAROL);

        vm.expectRevert(Stronghold.NotOnList.selector);

        // Attempt to mint 1 token
        stronghold.mint(1, proof);

        vm.stopPrank();
    }

    function test_disallowedMintSucceedsIfRootIsZero() public {
        Stronghold zeroStronghold = new Stronghold(
            linearCurve,
            xykCurve,
            address(quoteToken),
            address(pairFactory),
            bytes32(0)
        );
        vm.startPrank(CAROL);
        quoteToken.approve(address(zeroStronghold), LARGE_TOKEN_AMOUNT);
        zeroStronghold.mint(1, proof);
        vm.stopPrank();
    }

    function _finishMintAndInitPools() internal {
        vm.startPrank(ALICE);
        stronghold.mint(IConstants.INITIAL_LAUNCH_SUPPLY, proof); 
        stronghold.initFloorPool();
        stronghold.initAnchorPool();
        stronghold.initTradePool();
        vm.stopPrank();
    }

    function test_createPoolsSucceedAfterInitialMint() public {

        _finishMintAndInitPools();

        // Check that trying to recreate them also fails
        vm.expectRevert(Stronghold.PoolAlreadyExists.selector);
        stronghold.initFloorPool();

        vm.expectRevert(Stronghold.PoolAlreadyExists.selector);
        stronghold.initAnchorPool();

        vm.expectRevert(Stronghold.PoolAlreadyExists.selector);
        stronghold.initTradePool();
    }

    function test_createPoolsFailBeforeInitialMintComplete() public {

        // Mint out all INITIAL_LAUNCH_SUPPLY-1 NFTs
        vm.startPrank(ALICE);

        // Mint them all
        stronghold.mint(IConstants.INITIAL_LAUNCH_SUPPLY-1, proof);

        // Attempt to create all 3 pools
        vm.expectRevert(Stronghold.InitialMintIncomplete.selector);
        stronghold.initFloorPool();

        vm.expectRevert(Stronghold.InitialMintIncomplete.selector);
        stronghold.initAnchorPool();

        vm.expectRevert(Stronghold.InitialMintIncomplete.selector);
        stronghold.initTradePool();
    }
}
*/