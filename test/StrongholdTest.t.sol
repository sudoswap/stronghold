// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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

contract StrongholdTest is Test {

    LSSVMPairFactory pairFactory;
    LinearCurve linearCurve;
    XykCurve xykCurve;
    Test20 quoteToken;
    Stronghold stronghold;

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

        // Init stronghold
        stronghold = new Stronghold(
            linearCurve,
            xykCurve,
            address(quoteToken),
            address(pairFactory)
        );
    }

    function test_foo() public {
        
    }


}