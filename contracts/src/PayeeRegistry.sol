// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title PayeeRegistry
/// @notice A simple Confirmation-of-Payee registry: human-readable names mapped to
///         addresses, so a payer (or an agent about to pay) can verify that the address
///         on an invoice is the address the payee actually registered under their name
///         before any money moves.
/// @dev The official ERC-8004 registry on QDay is still in internal testing and is not
///      open for the Aevum Builder Challenge, so projects keep their own name mapping —
///      exactly what this contract is. Names are keyed by keccak256 of the exact string
///      (case-sensitive). Whoever registers a name first controls it: only that
///      registrant can update or remove it.
contract PayeeRegistry {
    mapping(bytes32 nameHash => address account) private _accounts;
    mapping(bytes32 nameHash => address registrant) private _registrants;

    event PayeeRegistered(
        bytes32 indexed nameHash, string name, address indexed account, address indexed registrant
    );
    event PayeeUpdated(
        bytes32 indexed nameHash, string name, address indexed account, address indexed registrant
    );
    event PayeeRemoved(bytes32 indexed nameHash, string name, address indexed registrant);

    error EmptyName();
    error ZeroAddress();
    error NameTaken(bytes32 nameHash);
    error NameNotRegistered(bytes32 nameHash);
    error NotRegistrant(bytes32 nameHash, address caller);

    /// @notice Register `name` for `account`. The caller becomes the name's registrant.
    function register(string calldata name, address account) external {
        bytes32 nameHash = _hash(name);
        if (account == address(0)) revert ZeroAddress();
        if (_accounts[nameHash] != address(0)) revert NameTaken(nameHash);
        _accounts[nameHash] = account;
        _registrants[nameHash] = msg.sender;
        emit PayeeRegistered(nameHash, name, account, msg.sender);
    }

    /// @notice Point a registered name at a new address. Only the registrant.
    function update(string calldata name, address account) external {
        bytes32 nameHash = _checkRegistrant(name);
        if (account == address(0)) revert ZeroAddress();
        _accounts[nameHash] = account;
        emit PayeeUpdated(nameHash, name, account, msg.sender);
    }

    /// @notice Remove a registration, freeing the name. Only the registrant.
    function remove(string calldata name) external {
        bytes32 nameHash = _checkRegistrant(name);
        delete _accounts[nameHash];
        delete _registrants[nameHash];
        emit PayeeRemoved(nameHash, name, msg.sender);
    }

    /// @notice The address registered under `name`, or address(0) if none.
    function resolve(string calldata name) external view returns (address) {
        return _accounts[_hash(name)];
    }

    /// @notice Confirmation-of-Payee check: true only if `name` is registered to
    ///         exactly `expected`. Check this before paying an invoice in that name.
    function verify(string calldata name, address expected) external view returns (bool) {
        return expected != address(0) && _accounts[_hash(name)] == expected;
    }

    function isRegistered(string calldata name) external view returns (bool) {
        return _accounts[_hash(name)] != address(0);
    }

    function registrantOf(string calldata name) external view returns (address) {
        return _registrants[_hash(name)];
    }

    function _hash(string calldata name) private pure returns (bytes32 nameHash) {
        if (bytes(name).length == 0) revert EmptyName();
        return keccak256(bytes(name));
    }

    function _checkRegistrant(string calldata name) private view returns (bytes32 nameHash) {
        nameHash = _hash(name);
        if (_accounts[nameHash] == address(0)) revert NameNotRegistered(nameHash);
        if (_registrants[nameHash] != msg.sender) revert NotRegistrant(nameHash, msg.sender);
    }
}
