defmodule ZenCex.Adapters.Bybit.RetryConfigTest do
  use ExUnit.Case, async: true

  describe "retry configuration" do
    # Read the generated endpoints file directly
    @endpoints_path Path.join([
                      __DIR__,
                      "..",
                      "..",
                      "..",
                      "..",
                      "lib",
                      "zen_cex",
                      "adapters",
                      "bybit",
                      "generated_endpoints.ex"
                    ])

    test "critical order operations have no retries" do
      # Read and evaluate the generated endpoints file
      {endpoints, _} = Code.eval_file(@endpoints_path)

      # Check place_order
      place_order = Enum.find(endpoints, &(&1.operation == :place_order))
      assert place_order.max_retries == 0
      assert place_order.retry_on == []

      # Check place_batch_orders
      place_batch = Enum.find(endpoints, &(&1.operation == :place_batch_orders))
      assert place_batch.max_retries == 0
      assert place_batch.retry_on == []

      # Check amend_order (should also have no retries to avoid duplicate amendments)
      amend_order = Enum.find(endpoints, &(&1.operation == :amend_order))
      assert amend_order.max_retries == 0
      assert amend_order.retry_on == []

      # Check amend_batch_orders
      amend_batch = Enum.find(endpoints, &(&1.operation == :amend_batch_orders))
      assert amend_batch.max_retries == 0
      assert amend_batch.retry_on == []
    end

    test "cancel operations can have limited retries (idempotent)" do
      {endpoints, _} = Code.eval_file(@endpoints_path)

      # Cancel is idempotent, so limited retry is safe
      cancel_order = Enum.find(endpoints, &(&1.operation == :cancel_order))
      assert cancel_order.max_retries == 1
      assert cancel_order.retry_on == [:timeout]

      cancel_batch = Enum.find(endpoints, &(&1.operation == :cancel_batch_orders))
      assert cancel_batch.max_retries == 1
      assert cancel_batch.retry_on == [:timeout]
    end

    test "read operations can have retries" do
      {endpoints, _} = Code.eval_file(@endpoints_path)

      # Get operations should allow retries
      get_balance = Enum.find(endpoints, &(&1.operation == :get_wallet_balance))
      assert get_balance.max_retries > 0

      get_positions = Enum.find(endpoints, &(&1.operation == :get_position_list))
      assert get_positions.max_retries > 0
    end
  end
end
