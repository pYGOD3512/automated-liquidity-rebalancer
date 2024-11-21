module liquidity_rebalancer::rebalancer {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::clock::{Self, Clock};
    use sui::table::{Self, Table};
    use sui::math;
    
    /// Errors
    const E_INSUFFICIENT_BALANCE: u64 = 1;
    const E_INVALID_FEE_PERCENTAGE: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;
    const E_TOO_EARLY_TO_REBALANCE: u64 = 4;
    const E_INVALID_PRICE: u64 = 5;

    /// Constants for rebalancing logic
    const VOLATILITY_WINDOW: u64 = 3600000; // 1 hour in milliseconds
    const MAX_PRICE_CHANGE_THRESHOLD: u64 = 50; // 5% price change threshold
    const MIN_REBALANCE_INTERVAL: u64 = 300000; // 5 minutes in milliseconds

    /// Stores the configuration for the rebalancer
    struct RebalancerConfig has key {
        id: UID,
        base_fee: u64,
        volatility_multiplier: u64,
        admin: address,
        min_rebalance_interval: u64,
        price_history: PriceHistory,
    }

    /// Represents a liquidity pool in the system
    struct LiquidityPool has key {
        id: UID,
        balance: Balance<sui::sui::SUI>,
        last_rebalance_timestamp: u64,
        current_fee_rate: u64,
        target_ratio: u64, // Target ratio for this pool (in basis points)
        current_price: u64, // Current price in base currency
        volatility_score: u64, // Current volatility score
    }

    /// Event when deposit occurs
    struct DepositEvent has copy, drop {
        pool_id: ID,
        amount: u64,
        fee: u64,
        timestamp: u64,
    }

    /// Event when withdrawal occurs
    struct WithdrawEvent has copy, drop {
        pool_id: ID,
        amount: u64,
        timestamp: u64,
    }

    /// Stores price data points for volatility calculation
    struct PriceHistory has store {
        prices: Table<u64, u64>, // timestamp -> price
        last_prices_count: u64,
    }

    /// Initialize the rebalancer
    fun init(ctx: &mut TxContext) {
        let config = RebalancerConfig {
            id: object::new(ctx),
            base_fee: 100, // 0.1% as base fee
            volatility_multiplier: 2, // Double fees in high volatility
            admin: tx_context::sender(ctx),
            min_rebalance_interval: MIN_REBALANCE_INTERVAL,
            price_history: PriceHistory {
                prices: table::new(ctx),
                last_prices_count: 0,
            }
        };

        transfer::share_object(config);
    }

    /// Create a new liquidity pool
    public fun create_pool(ctx: &mut TxContext) {
        let pool = LiquidityPool {
            id: object::new(ctx),
            balance: balance::zero(),
            last_rebalance_timestamp: 0,
            current_fee_rate: 100, // Start with base fee
            target_ratio: 10000, // 100% as target ratio
            current_price: 0,
            volatility_score: 0,
        };

        transfer::share_object(pool);
    }

    /// Deposit funds into a pool
    public fun deposit(
        pool: &mut LiquidityPool,
        coin: Coin<SUI>,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&coin);
        let fee_amount = calculate_fee(pool, amount);
        
        // Convert Coin to Balance and add to pool
        let balance = coin::into_balance(coin);
        balance::join(&mut pool.balance, balance);
        
        // Update last interaction time
        pool.last_rebalance_timestamp = clock::timestamp_ms(clock);

        // Emit deposit event
        event::emit(DepositEvent {
            pool_id: object::uid_to_inner(&pool.id),
            amount,
            fee: fee_amount,
            timestamp: clock::timestamp_ms(clock),
        });
    }

    /// Withdraw funds from a pool
    public fun withdraw(
        pool: &mut LiquidityPool,
        amount: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ): Coin<SUI> {
        assert!(balance::value(&pool.balance) >= amount, E_INSUFFICIENT_BALANCE);
        
        // Split the balance and convert to Coin
        let withdrawn_balance = balance::split(&mut pool.balance, amount);
        let coin = coin::from_balance(withdrawn_balance, ctx);
        
        // Update last interaction time
        pool.last_rebalance_timestamp = clock::timestamp_ms(clock);

        // Emit withdrawal event
        event::emit(WithdrawEvent {
            pool_id: object::uid_to_inner(&pool.id),
            amount,
            timestamp: clock::timestamp_ms(clock),
        });

        coin
    }

    /// Calculate fee based on current market conditions
    fun calculate_fee(pool: &LiquidityPool, amount: u64): u64 {
        // For now, we'll use a simple fee calculation
        // In the next phase, we'll make this more sophisticated with volatility
        (amount * pool.current_fee_rate) / 100_000 // Fee in basis points
    }

    /// Update fee rate based on market conditions
    public fun update_fee_rate(
        config: &RebalancerConfig,
        pool: &mut LiquidityPool,
        new_fee_rate: u64,
        ctx: &TxContext
    ) {
        // Only admin can update fee rate
        assert!(tx_context::sender(ctx) == config.admin, E_UNAUTHORIZED);
        assert!(new_fee_rate <= 1000, E_INVALID_FEE_PERCENTAGE); // Max 1% fee
        
        pool.current_fee_rate = new_fee_rate;
    }

    /// Record new price and calculate volatility
    public fun update_price_and_volatility(
        config: &mut RebalancerConfig,
        pool: &mut LiquidityPool,
        new_price: u64,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        assert!(new_price > 0, E_INVALID_PRICE);
        
        let timestamp = clock::timestamp_ms(clock);
        table::add(&mut config.price_history.prices, timestamp, new_price);
        config.price_history.last_prices_count = 
            math::min(config.price_history.last_prices_count + 1, 24); // Keep last 24 prices
        
        pool.current_price = new_price;
        pool.volatility_score = calculate_volatility(config, clock);
        
        // Adjust fee based on volatility
        adjust_fee_rate(config, pool);
    }

    /// Calculate volatility based on price history
    fun calculate_volatility(config: &RebalancerConfig, clock: &Clock): u64 {
        if (config.price_history.last_prices_count < 2) {
            return 0
        };
        
        let current_time = clock::timestamp_ms(clock);
        let max_price = 0;
        let min_price = 0;
        
        let i = 0;
        while (i < config.price_history.last_prices_count) {
            let price = *table::borrow(&config.price_history.prices, current_time - (i * 3600000));
            if (i == 0) {
                max_price = price;
                min_price = price;
            } else {
                if (price > max_price) max_price = price;
                if (price < min_price) min_price = price;
            };
            i = i + 1;
        };

        // Calculate price range as percentage
        ((max_price - min_price) * 10000) / min_price
    }

    /// Adjust fee rate based on volatility
    fun adjust_fee_rate(config: &RebalancerConfig, pool: &mut LiquidityPool) {
        let new_fee_rate = if (pool.volatility_score > MAX_PRICE_CHANGE_THRESHOLD) {
            config.base_fee * config.volatility_multiplier
        } else {
            config.base_fee
        };
        
        pool.current_fee_rate = new_fee_rate;
    }

    /// Rebalance pool based on market conditions
    public fun rebalance_pool(
        config: &RebalancerConfig,
        pool: &mut LiquidityPool,
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let current_time = clock::timestamp_ms(clock);
        
        // Check if enough time has passed since last rebalance
        assert!(
            current_time >= pool.last_rebalance_timestamp + config.min_rebalance_interval,
            E_TOO_EARLY_TO_REBALANCE
        );

        // Implement rebalancing logic based on volatility and target ratio
        if (pool.volatility_score > MAX_PRICE_CHANGE_THRESHOLD) {
            // In high volatility, adjust target ratio more conservatively
            pool.target_ratio = pool.target_ratio * 90 / 100; // Reduce exposure by 10%
        } else {
            // In low volatility, maintain or increase target ratio
            pool.target_ratio = math::min(pool.target_ratio * 110 / 100, 10000); // Increase up to max 100%
        };

        pool.last_rebalance_timestamp = current_time;
    }
}