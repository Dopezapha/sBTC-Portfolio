# sBTC Portfolio Manager Smart Contract

## Overview

The sBTC Portfolio Manager is a Clarity smart contract designed for the Stacks blockchain that enables users to deposit sBTC and allocate their funds across multiple investment strategies. This contract provides a secure and flexible framework for portfolio management, strategy creation, performance tracking, and fee collection.

## Features

- **Multi-Strategy Portfolio Management**: Users can diversify their sBTC across various investment strategies
- **Performance Tracking**: Strategy performance metrics are recorded and tracked over time
- **Fee Management**: Configurable performance and platform fees with designated collectors
- **Permissioned Roles**: Distinct roles for contract owner, strategy managers, and users
- **Risk Categorization**: Strategies are classified by risk level and performance multipliers
- **Allocation Caps**: Safety limits on maximum allocation per strategy
- **Event Logging**: Comprehensive event tracking for portfolio activities

## Contract Structure

### Constants

- Error codes for various failure scenarios
- Fee percentages (scaled for precision)

### Data Variables

- `contract-owner`: Principal who has admin rights over the contract
- `contract-paused`: Boolean flag to halt contract operations in emergencies
- `total-managed-amount`: Total sBTC managed by the contract
- `performance-fee-percent`: Fee percentage charged on strategy profits
- `platform-fee-percent`: Fee percentage charged on all managed assets
- `fee-collector`: Principal who receives collected fees
- `strategy-counter`: Counter used to generate unique strategy IDs

### Maps

- `strategies`: Stores strategy details including risk level, manager, and allocation cap
- `user-balances`: Tracks total deposited balance per user
- `user-strategy-allocations`: Maps users to their allocations in each strategy
- `strategy-performance`: Records performance metrics for strategies over time

## Public Functions

### Administrative Functions

- `set-contract-owner`: Transfer contract ownership
- `set-fee-collector`: Update the fee collection address
- `set-performance-fee`: Adjust the performance fee percentage
- `set-platform-fee`: Adjust the platform fee percentage
- `toggle-contract-pause`: Enable/disable contract operations

### Strategy Management

- `create-strategy`: Create a new investment strategy
- `update-strategy`: Modify an existing strategy's parameters
- `update-strategy-allocation-cap`: Adjust maximum allowed allocation
- `set-strategy-performance`: Record performance metrics for a period

### User Functions

- `deposit`: Deposit sBTC into the contract
- `withdraw`: Withdraw unallocated sBTC from the contract
- `allocate-to-strategy`: Allocate funds to a specific strategy
- `deallocate-from-strategy`: Remove funds from a strategy

### Read-Only Functions

- `get-user-balance`: Get total balance for a user
- `get-user-allocated-balance`: Get total allocated amount for a user
- `get-user-unallocated-balance`: Get available unallocated balance
- `get-user-strategy-allocation`: Get amount allocated to a specific strategy
- `get-strategy`: Get details for a specific strategy
- `get-strategy-performance-data`: Get performance data for a strategy
- `get-total-managed-amount`: Get total sBTC managed by the contract
- `get-contract-owner`: Get current contract owner
- `is-contract-paused`: Check if contract is paused
- `get-performance-fee`: Get current performance fee percentage
- `get-platform-fee`: Get current platform fee percentage
- `get-user-strategies`: Get list of strategies a user has allocated to

## Events

- `emit-deposit-event`: Triggered when a user deposits sBTC
- `emit-withdrawal-event`: Triggered when a user withdraws sBTC
- `emit-strategy-allocation-event`: Triggered when a user allocates to a strategy
- `emit-strategy-created-event`: Triggered when a new strategy is created

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| u1 | ERR-UNAUTHORIZED | Caller doesn't have required permissions |
| u2 | ERR-INVALID-AMOUNT | Amount is invalid (zero or exceeds limits) |
| u3 | ERR-INSUFFICIENT-BALANCE | User has insufficient balance for operation |
| u4 | ERR-STRATEGY-EXISTS | Strategy with same ID already exists |
| u5 | ERR-STRATEGY-NOT-FOUND | Requested strategy doesn't exist |
| u6 | ERR-ALLOCATION-EXCEEDED | Strategy allocation cap would be exceeded |
| u7 | ERR-TRANSFER-FAILED | sBTC transfer operation failed |
| u8 | ERR-PAUSED | Contract is currently paused |

## Usage Examples

### Creating a Strategy

```clarity
(contract-call? .sbtc-portfolio-manager create-strategy 
  "Yield Farming" 
  "Strategy focused on yield farming across DeFi protocols" 
  u5 
  u200 
  u1000000000)
```

### Depositing sBTC

```clarity
(contract-call? .sbtc-portfolio-manager deposit u1000000)
```

### Allocating to a Strategy

```clarity
(contract-call? .sbtc-portfolio-manager allocate-to-strategy u1 u500000)
```

### Withdrawing Funds

```clarity
(contract-call? .sbtc-portfolio-manager withdraw u250000)
```

## Security Considerations

- The contract uses permission checks to ensure only authorized users can perform certain operations
- All sensitive operations include balance checks to prevent overdrafts
- Allocation caps prevent any single strategy from holding too much of the total managed amount
- The contract can be paused in case of emergency
- All state-changing functions use appropriate assertions to validate inputs

## Development and Deployment

### Prerequisites

- Clarity CLI or Clarinet for local development and testing
- Account with sufficient STX for contract deployment

### Deployment Steps

1. Deploy the contract to the Stacks blockchain:
   ```bash
   clarinet deploy --network mainnet
   ```

2. Initialize the contract parameters:
   ```clarity
   (contract-call? .sbtc-portfolio-manager set-fee-collector 'SP...')
   (contract-call? .sbtc-portfolio-manager set-performance-fee u200)
   (contract-call? .sbtc-portfolio-manager set-platform-fee u50)
   ```

3. Create initial strategies:
   ```clarity
   (contract-call? .sbtc-portfolio-manager create-strategy ...)
   ```