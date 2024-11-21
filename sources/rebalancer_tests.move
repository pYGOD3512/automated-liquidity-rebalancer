#[test_only]
module liquidity_rebalancer::rebalancer_tests {
    use sui::test_scenario::{Self as test, Scenario, next_tx, ctx};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::clock::{Self, Clock};
    use liquidity_rebalancer::rebalancer::{Self, RebalancerConfig, LiquidityPool};

    // Test constants
    const ADMIN: address = @0xAD;
    const USER1: address = @0x1;
    const USER2: address = @0x2;
    const INITIAL_AMOUNT: u64 = 1000000000; // 1 SUI

    // Helper function to set up test scenario
    fun setup_test(): Scenario {
        let scenario = test::begin(ADMIN);
        
        // Create and share clock for testing
        next_tx(&mut scenario, ADMIN); {
            clock::create_for_testing(ctx(&mut scenario));
        };

        // Initialize rebalancer
        next_tx(&mut scenario, ADMIN); {
            rebalancer::init(ctx(&mut scenario));
        };

        scenario
    }

    #[test]
    fun test_initialization() {
        let scenario = setup_test();
        
        next_tx(&mut scenario, ADMIN); {
            // Verify config exists and is properly initialized
            let config = test::take_shared<RebalancerConfig>(&scenario);
            assert!(rebalancer::admin(&config) == ADMIN, 1);
            test::return_shared(config);
        };

        test::end(scenario);
    }

    #[test]
    fun test_create_pool() {
        let scenario = setup_test();

        next_tx(&mut scenario, USER1); {
            rebalancer::create_pool(ctx(&mut scenario));
        };

        next_tx(&mut scenario, USER1); {
            // Verify pool exists
            let pool = test::take_shared<LiquidityPool>(&scenario);
            assert!(rebalancer::pool_balance(&pool) == 0, 1);
            test::return_shared(pool);
        };

        test::end(scenario);
    }

    #[test]
    fun test_deposit_and_withdraw() {
        let scenario = setup_test();

        // Create pool
        next_tx(&mut scenario, USER1); {
            rebalancer::create_pool(ctx(&mut scenario));
        };

        // Mint some SUI for testing
        next_tx(&mut scenario, USER1); {
            let coin = coin::mint_for_testing<SUI>(INITIAL_AMOUNT, ctx(&mut scenario));
            let pool = test::take_shared<LiquidityPool>(&scenario);
            let clock = test::take_shared<Clock>(&scenario);

            // Test deposit
            rebalancer::deposit(&mut pool, coin, &clock, ctx(&mut scenario));
            assert!(rebalancer::pool_balance(&pool) == INITIAL_AMOUNT, 1);

            test::return_shared(pool);
            test::return_shared(clock);
        };

        // Test withdrawal
        next_tx(&mut scenario, USER1); {
            let pool = test::take_shared<LiquidityPool>(&scenario);
            let clock = test::take_shared<Clock>(&scenario);

            let withdraw_amount = INITIAL_AMOUNT / 2;
            let withdrawn_coin = rebalancer::withdraw(&mut pool, withdraw_amount, &clock, ctx(&mut scenario));
            assert!(coin::value(&withdrawn_coin) == withdraw_amount, 1);
            assert!(rebalancer::pool_balance(&pool) == INITIAL_AMOUNT - withdraw_amount, 2);

            // Clean up
            coin::burn_for_testing(withdrawn_coin);
            test::return_shared(pool);
            test::return_shared(clock);
        };

        test::end(scenario);
    }

    #[test]
    fun test_price_updates_and_volatility() {
        let scenario = setup_test();

        next_tx(&mut scenario, USER1); {
            rebalancer::create_pool(ctx(&mut scenario));
        };

        // Update price and check volatility calculations
        next_tx(&mut scenario, ADMIN); {
            let config = test::take_shared<RebalancerConfig>(&scenario);
            let pool = test::take_shared<LiquidityPool>(&scenario);
            let clock = test::take_shared<Clock>(&scenario);

            // Update price multiple times to simulate market movement
            rebalancer::update_price_and_volatility(&mut config, &mut pool, 1000, &clock, ctx(&mut scenario));
            
            // Advance clock
            clock::increment_for_testing(&mut clock, 3600000); // 1 hour
            rebalancer::update_price_and_volatility(&mut config, &mut pool, 1100, &clock, ctx(&mut scenario));

            // Verify price update
            assert!(rebalancer::current_price(&pool) == 1100, 1);
            
            test::return_shared(config);
            test::return_shared(pool);
            test::return_shared(clock);
        };

        test::end(scenario);
    }

    #[test]
    fun test_rebalancing() {
        let scenario = setup_test();

        next_tx(&mut scenario, USER1); {
            rebalancer::create_pool(ctx(&mut scenario));
        };

        // Test rebalancing logic
        next_tx(&mut scenario, ADMIN); {
            let config = test::take_shared<RebalancerConfig>(&scenario);
            let pool = test::take_shared<LiquidityPool>(&scenario);
            let clock = test::take_shared<Clock>(&scenario);

            // Update price to trigger volatility
            rebalancer::update_price_and_volatility(&mut config, &mut pool, 1000, &clock, ctx(&mut scenario));
            clock::increment_for_testing(&mut clock, 300000); // 5 minutes
            
            // Perform rebalancing
            rebalancer::rebalance_pool(&config, &mut pool, &clock, ctx(&mut scenario));

            test::return_shared(config);
            test::return_shared(pool);
            test::return_shared(clock);
        };

        test::end(scenario);
    }
}