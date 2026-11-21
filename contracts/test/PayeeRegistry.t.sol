// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PayeeRegistry} from "../src/PayeeRegistry.sol";

contract PayeeRegistryTest is Test {
    PayeeRegistry registry;
    address registrant = makeAddr("registrant");
    address payee = makeAddr("payee");
    address payee2 = makeAddr("payee2");
    address stranger = makeAddr("stranger");

    string constant NAME = "toko-berkah";
    bytes32 constant NAME_HASH = keccak256(bytes(NAME));

    function setUp() public {
        registry = new PayeeRegistry();
    }

    function _register() internal {
        vm.prank(registrant);
        registry.register(NAME, payee);
    }

    function test_register_resolveAndVerify() public {
        vm.expectEmit(true, false, true, true, address(registry));
        emit PayeeRegistry.PayeeRegistered(NAME_HASH, NAME, payee, registrant);
        _register();

        assertEq(registry.resolve(NAME), payee);
        assertEq(registry.registrantOf(NAME), registrant);
        assertTrue(registry.isRegistered(NAME));
        assertTrue(registry.verify(NAME, payee));
    }

    function test_verify_falseForWrongOrZeroAddress() public {
        _register();
        assertFalse(registry.verify(NAME, payee2));
        assertFalse(registry.verify(NAME, address(0)));
        assertFalse(registry.verify("nama-lain", payee));
    }

    function test_resolve_unknownNameReturnsZero() public view {
        assertEq(registry.resolve("belum-ada"), address(0));
        assertFalse(registry.isRegistered("belum-ada"));
    }

    function test_register_revertsOnTakenName() public {
        _register();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PayeeRegistry.NameTaken.selector, NAME_HASH));
        registry.register(NAME, payee2);
    }

    function test_register_revertsOnZeroAddress() public {
        vm.prank(registrant);
        vm.expectRevert(PayeeRegistry.ZeroAddress.selector);
        registry.register(NAME, address(0));
    }

    function test_register_revertsOnEmptyName() public {
        vm.prank(registrant);
        vm.expectRevert(PayeeRegistry.EmptyName.selector);
        registry.register("", payee);
    }

    function test_register_namesAreCaseSensitive() public {
        _register();
        vm.prank(stranger);
        registry.register("Toko-Berkah", payee2);
        assertEq(registry.resolve("Toko-Berkah"), payee2);
        assertEq(registry.resolve(NAME), payee);
    }

    function test_update_byRegistrant() public {
        _register();
        vm.prank(registrant);
        vm.expectEmit(true, false, true, true, address(registry));
        emit PayeeRegistry.PayeeUpdated(NAME_HASH, NAME, payee2, registrant);
        registry.update(NAME, payee2);
        assertEq(registry.resolve(NAME), payee2);
        assertTrue(registry.verify(NAME, payee2));
    }

    function test_update_revertsForStranger() public {
        _register();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PayeeRegistry.NotRegistrant.selector, NAME_HASH, stranger));
        registry.update(NAME, payee2);
    }

    function test_update_revertsForUnknownName() public {
        vm.prank(registrant);
        vm.expectRevert(abi.encodeWithSelector(PayeeRegistry.NameNotRegistered.selector, NAME_HASH));
        registry.update(NAME, payee);
    }

    function test_remove_byRegistrant_freesName() public {
        _register();
        vm.prank(registrant);
        registry.remove(NAME);
        assertEq(registry.resolve(NAME), address(0));
        assertFalse(registry.isRegistered(NAME));

        vm.prank(stranger);
        registry.register(NAME, payee2);
        assertEq(registry.resolve(NAME), payee2);
        assertEq(registry.registrantOf(NAME), stranger);
    }

    function test_remove_revertsForStranger() public {
        _register();
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(PayeeRegistry.NotRegistrant.selector, NAME_HASH, stranger));
        registry.remove(NAME);
    }
}
