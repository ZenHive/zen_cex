defmodule ZenCex.ReqHelpers do
  @moduledoc """
  Helper functions for working with REQ request private data.

  The private field in Req.Request is the idiomatic place to store
  custom metadata that isn't an HTTP concern (like rate limit weights,
  exchange identifiers, or request tracking information).
  """

  @doc """
  Put custom metadata in the request's private field.

  ## Examples

      iex> request |> put_private(:rate_limit_weight, 10)
      %Req.Request{private: %{rate_limit_weight: 10}, ...}
  """
  @spec put_private(Req.Request.t(), atom(), any()) :: Req.Request.t()
  def put_private(%Req.Request{} = request, key, value) when is_atom(key) do
    Req.Request.put_private(request, key, value)
  end

  @doc """
  Get custom metadata from the request's private field.

  ## Examples

      iex> request |> get_private(:rate_limit_weight)
      10
      
      iex> request |> get_private(:missing_key, :default)
      :default
  """
  @spec get_private(Req.Request.t(), atom(), any()) :: any()
  def get_private(%Req.Request{private: private}, key, default \\ nil) when is_atom(key) do
    Map.get(private || %{}, key, default)
  end

  @doc """
  Merge multiple private fields at once.

  ## Examples

      iex> request |> merge_private(%{
      ...>   rate_limit_weight: 10,
      ...>   exchange: :binance,
      ...>   operation_type: :trading
      ...> })
      %Req.Request{private: %{rate_limit_weight: 10, exchange: :binance, ...}}
  """
  @spec merge_private(Req.Request.t(), map()) :: Req.Request.t()
  def merge_private(%Req.Request{private: private} = request, metadata) when is_map(metadata) do
    merged = Map.merge(private || %{}, metadata)
    %{request | private: merged}
  end

  @doc """
  Update a private field value using a function.

  ## Examples

      iex> request |> update_private(:counter, 0, &(&1 + 1))
      %Req.Request{private: %{counter: 1}, ...}
  """
  @spec update_private(Req.Request.t(), atom(), any(), (any() -> any())) :: Req.Request.t()
  def update_private(%Req.Request{private: private} = request, key, default, fun)
      when is_atom(key) and is_function(fun, 1) do
    current_value = Map.get(private || %{}, key, default)
    new_value = fun.(current_value)
    put_private(request, key, new_value)
  end

  @doc """
  Check if a private field exists.

  ## Examples

      iex> request |> has_private?(:rate_limit_weight)
      true
  """
  @spec has_private?(Req.Request.t(), atom()) :: boolean()
  def has_private?(%Req.Request{private: private}, key) when is_atom(key) do
    Map.has_key?(private || %{}, key)
  end

  @doc """
  Delete a private field.

  ## Examples

      iex> request |> delete_private(:temporary_data)
      %Req.Request{private: %{}, ...}
  """
  @spec delete_private(Req.Request.t(), atom()) :: Req.Request.t()
  def delete_private(%Req.Request{private: private} = request, key) when is_atom(key) do
    updated = Map.delete(private || %{}, key)
    %{request | private: updated}
  end
end
